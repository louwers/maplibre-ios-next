// Based on platform/darwin/src/MLNStyle.mm at ios-v7.0.0

#import "MLNStyle_Private.h"

#import "MLNBackgroundStyleLayer.h"
#import "MLNCircleStyleLayer.h"
#import "MLNColorReliefStyleLayer.h"
#import "MLNFillExtrusionStyleLayer.h"
#import "MLNFillStyleLayer.h"
#import "MLNHeatmapStyleLayer.h"
#import "MLNHillshadeStyleLayer.h"
#import "MLNLineStyleLayer.h"
#import "MLNMapView_Private.h"
#import "MLNRasterStyleLayer.h"
#import "MLNStyleLayer.h"
#import "MLNStyleLayer_Private.h"
#import "MLNSymbolStyleLayer.h"

#import "MLNImageSource.h"
#import "MLNLight_Private.h"
#import "MLNRasterDEMSource.h"
#import "MLNRasterTileSource.h"
#import "MLNShapeSource.h"
#import "MLNSource.h"
#import "MLNSource_Private.h"
#import "MLNTileSource_Private.h"
#import "MLNVectorTileSource_Private.h"

#import "MLNAttributionInfo_Private.h"
#import "MLNLoggingConfiguration_Private.h"
#import "MLNStyleValue_Private.h"

#import "MLNFFIMap+Style.h"
#import "MLNStyleSpec.h"

#import "NSDate+MLNAdditions.h"

#import "MLNCustomStyleLayer.h"
#import "MLNCustomStyleLayer_Private.h"

#if TARGET_OS_IPHONE
#import "UIImage+MLNAdditions.h"
#else
#import "NSImage+MLNAdditions.h"
#endif

NSString *const MLNInternalStyleIdentifierPrefix = @"org.maplibre.next.";

const MLNExceptionName MLNInvalidStyleURLException = @"MLNInvalidStyleURLException";
const MLNExceptionName MLNRedundantLayerException = @"MLNRedundantLayerException";
const MLNExceptionName MLNRedundantLayerIdentifierException =
    @"MLNRedundantLayerIdentifierException";
const MLNExceptionName MLNRedundantSourceException = @"MLNRedundantSourceException";
const MLNExceptionName MLNRedundantSourceIdentifierException =
    @"MLNRedundantSourceIdentifierException";

/**
 Model class for localization changes.
 */
@interface MLNTextLanguage : NSObject
@property (strong, nonatomic) NSString *originalTextField;
@property (strong, nonatomic) NSString *updatedTextField;

- (instancetype)initWithTextLanguage:(NSString *)originalTextField
                    updatedTextField:(NSString *)updatedTextField;

@end

@implementation MLNTextLanguage
- (instancetype)initWithTextLanguage:(NSString *)originalTextField
                    updatedTextField:(NSString *)updatedTextField {
  if (self = [super init]) {
    _originalTextField = originalTextField;
    _updatedTextField = updatedTextField;
  }
  return self;
}
@end

@interface MLNStyle ()

@property (nonatomic, readonly, weak) id<MLNStylable> stylable;
@property (nonatomic, readonly, nullable) MLNFFIMap *mgl_map;
@property (readonly, copy, nullable) NSURL *URL;
@property (nonatomic, readwrite, strong)
    NSMutableDictionary<NSString *, MLNCustomStyleLayer *> *customLayers;
@property (nonatomic) NSMutableDictionary<NSString *, NSDictionary<NSObject *, MLNTextLanguage *> *>
    *localizedLayersByIdentifier;

@end

@implementation MLNStyle {
  NSMapTable<NSString *, MLNStyleLayer *> *_layerObjects;
  NSMapTable<NSString *, MLNSource *> *_sourceObjects;
  // Hidden sources standing in for sources that layers refer to:
  // placeholder identifier -> the source's identifier.
  NSMutableDictionary<NSString *, NSString *> *_placeholderSources;
  NSDictionary *_loadedStyle;
}

// MARK: Predefined style URLs

+ (NSArray<MLNDefaultStyle *> *)predefinedStyles {
  return MLNSettings.tileServerOptions.defaultStyles;
}

+ (MLNDefaultStyle *)defaultStyle {
  MLNTileServerOptions *opts = MLNSettings.tileServerOptions;
  return opts.defaultStyle;
}

+ (NSURL *)defaultStyleURL {
  MLNDefaultStyle *styleDefinition = [MLNStyle defaultStyle];
  if (styleDefinition != nil) {
    return styleDefinition.url;
  }

  return nil;
}

+ (MLNDefaultStyle *)predefinedStyle:(NSString *)withStyleName {
  for (MLNDefaultStyle *style in MLNSettings.tileServerOptions.defaultStyles) {
    if ([style.name isEqualToString:withStyleName]) {
      return style;
    }
  }
  return nil;
}

// MARK: -

- (instancetype)initWithMap:(MLNFFIMap *)map stylable:(id<MLNStylable>)stylable {
  MLNLogInfo(@"Initializing %@ with stylable: %@", NSStringFromClass([self class]), stylable);
  if (self = [super init]) {
    _stylable = stylable;
    _mgl_map = map;
    _layerObjects = [NSMapTable strongToWeakObjectsMapTable];
    _sourceObjects = [NSMapTable strongToWeakObjectsMapTable];
    _placeholderSources = [NSMutableDictionary dictionary];
    _customLayers = [NSMutableDictionary dictionary];
    _localizedLayersByIdentifier = [NSMutableDictionary dictionary];
    MLNLogDebug(@"Initializing with style name: %@ stylable: %@", self.name, stylable);
  }
  return self;
}

- (NSURL *)URL {
  return [NSURL URLWithString:[self.mgl_map styleURL] ?: @""];
}

// The C API has no style name getter; read it from the loaded document, which
// is what mbgl::style::Style::getName() reported.
- (NSString *)name {
  if (!_loadedStyle) {
    NSData *data = [self.styleJSON dataUsingEncoding:NSUTF8StringEncoding];
    id style = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    _loadedStyle = [style isKindOfClass:[NSDictionary class]] ? style : @{};
  }
  NSString *name = _loadedStyle[@"name"];
  return [name isKindOfClass:[NSString class]] && name.length ? name : nil;
}

- (NSString *)styleJSON {
  // Return empty string if no style is set
  return [self.mgl_map loadedStyleJSON] ?: @"";
}

- (void)setStyleJSON:(NSString *)styleJSON {
  [self.mgl_map loadStyleJSON:styleJSON message:nil];
}

// MARK: Object identity

- (void)mgl_invalidate {
  for (MLNStyleLayer *layer in _layerObjects.objectEnumerator) {
    [layer mgl_invalidate];
  }
  for (MLNSource *source in _sourceObjects.objectEnumerator) {
    [source mgl_invalidate];
  }
  [_layerObjects removeAllObjects];
  [_sourceObjects removeAllObjects];
  [_placeholderSources removeAllObjects];
  _mgl_map = nil;
}

- (void)mgl_registerLayer:(MLNStyleLayer *)layer {
  [_layerObjects setObject:layer forKey:layer.identifier];
}

- (void)mgl_unregisterLayer:(MLNStyleLayer *)layer {
  if ([_layerObjects objectForKey:layer.identifier] == layer) {
    [_layerObjects removeObjectForKey:layer.identifier];
  }
}

- (MLNStyleLayer *)mgl_registeredLayerWithIdentifier:(NSString *)identifier {
  return [_layerObjects objectForKey:identifier];
}

- (void)mgl_registerSource:(MLNSource *)source {
  [_sourceObjects setObject:source forKey:source.identifier];
}

- (void)mgl_unregisterSource:(MLNSource *)source {
  if ([_sourceObjects objectForKey:source.identifier] == source) {
    [_sourceObjects removeObjectForKey:source.identifier];
  }
}

- (MLNSource *)mgl_registeredSourceWithIdentifier:(NSString *)identifier {
  return [_sourceObjects objectForKey:identifier];
}

- (NSString *)mgl_placeholderSourceForSource:(NSString *)identifier layerType:(NSString *)layerType {
  NSString *kind;
  NSDictionary *source;
  if ([layerType isEqualToString:@"raster"]) {
    kind = @"raster";
    source = @{@"type" : @"raster", @"tiles" : @[]};
  } else if ([layerType isEqualToString:@"hillshade"] || [layerType isEqualToString:@"color-relief"]) {
    kind = @"raster-dem";
    source = @{@"type" : @"raster-dem", @"tiles" : @[]};
  } else {
    kind = @"vector";
    source = @{@"type" : @"geojson", @"data" : @{@"type" : @"FeatureCollection", @"features" : @[]}};
  }
  NSString *placeholder = [NSString
      stringWithFormat:@"%@placeholder.%@.%@", MLNInternalStyleIdentifierPrefix, kind, identifier];
  if (_placeholderSources[placeholder]) {
    return placeholder;
  }
  NSString *message;
  if ([self.mgl_map addStyleSourceJSON:source identifier:placeholder message:&message] != MLN_STATUS_OK) {
    MLNLogError(@"Failed to stand in for source %@: %@", identifier, message);
    return nil;
  }
  _placeholderSources[placeholder] = identifier;
  return placeholder;
}

- (NSString *)mgl_sourceIdentifierForMapSource:(NSString *)identifier {
  return _placeholderSources[identifier] ?: identifier;
}

/// Moves the layers that use placeholders for a source onto the source, now
/// that it was added: they are taken out, the placeholders removed, and the
/// layers put back where they were with the source.
- (void)mgl_movePlaceholderLayersToSource:(NSString *)identifier {
  NSSet<NSString *> *placeholders =
      [_placeholderSources keysOfEntriesPassingTest:^BOOL(NSString *key, NSString *value, BOOL *stop) {
        return [value isEqualToString:identifier];
      }];
  if (!placeholders.count) {
    return;
  }
  NSArray<MLNFFILayerInfo *> *layers = [self.mgl_map styleLayers];
  NSMutableArray<NSArray *> *moved = [NSMutableArray array];
  for (NSUInteger i = 0; i < layers.count; i++) {
    if (![placeholders containsObject:layers[i].sourceIdentifier]) {
      continue;
    }
    NSString *before;
    for (NSUInteger j = i + 1; j < layers.count; j++) {
      if (![placeholders containsObject:layers[j].sourceIdentifier]) {
        before = layers[j].identifier;
        break;
      }
    }
    NSMutableDictionary *json = [MLNReparsableLayerJSON([self.mgl_map styleLayerJSON:layers[i].identifier] ?: @{}) mutableCopy];
    json[@"source"] = identifier;
    [moved addObject:@[ json, before ?: [NSNull null] ]];
  }
  for (NSArray *entry in moved) {
    [self.mgl_map removeStyleLayer:entry[0][@"id"] message:nil];
  }
  for (NSString *placeholder in placeholders) {
    [self.mgl_map removeStyleSource:placeholder message:nil];
    [_placeholderSources removeObjectForKey:placeholder];
  }
  for (NSArray *entry in moved) {
    NSString *before = entry[1] == [NSNull null] ? nil : entry[1];
    NSString *message;
    if ([self.mgl_map addStyleLayerJSON:entry[0] belowLayer:before message:&message] != MLN_STATUS_OK) {
      MLNLogError(@"Failed to move layer %@ onto source %@: %@", entry[0][@"id"], identifier, message);
    }
  }
}

// MARK: Sources

/// The style's sources in creation order, without the SDK's own.
- (NSArray<MLNFFISourceInfo *> *)mgl_sourceInfos {
  NSMutableArray *infos = [NSMutableArray array];
  for (MLNFFISourceInfo *info in [self.mgl_map styleSources]) {
    if (![info.identifier hasPrefix:MLNInternalStyleIdentifierPrefix]) {
      [infos addObject:info];
    }
  }
  return infos;
}

- (NSSet<__kindof MLNSource *> *)sources {
  NSArray<MLNFFISourceInfo *> *infos = [self mgl_sourceInfos];
  NSMutableSet<__kindof MLNSource *> *sources = [NSMutableSet setWithCapacity:infos.count];
  for (MLNFFISourceInfo *info in infos) {
    [sources addObject:[self sourceFromSourceInfo:info]];
  }
  return sources;
}

- (void)setSources:(NSSet<__kindof MLNSource *> *)sources {
  MLNLogDebug(@"Setting: %lu sources", sources.count);
  for (MLNSource *source in self.sources) {
    [self removeSource:source];
  }
  for (MLNSource *source in sources) {
    [self addSource:source];
  }
}

- (NSUInteger)countOfSources {
  return [self mgl_sourceInfos].count;
}

- (MLNSource *)memberOfSources:(MLNSource *)object {
  return [self sourceWithIdentifier:object.identifier];
}

- (MLNSource *)sourceWithIdentifier:(NSString *)identifier {
  MLNLogDebug(@"Querying source with identifier: %@", identifier);
  MLNFFISourceInfo *info = identifier ? [self.mgl_map styleSourceWithIdentifier:identifier] : nil;
  if (!info || [identifier hasPrefix:MLNInternalStyleIdentifierPrefix]) {
    return nil;
  }
  return [self sourceFromSourceInfo:info];
}

- (MLNSource *)sourceFromSourceInfo:(MLNFFISourceInfo *)info {
  if (MLNSource *source = [self mgl_registeredSourceWithIdentifier:info.identifier]) {
    return source;
  }

  Class sourceClass;
  // The annotation source was of the core's own type, which no darwin class
  // represented.
  if ([info.identifier isEqualToString:@"org.maplibre.annotations"]) {
    info.type = MLN_STYLE_SOURCE_TYPE_ANNOTATIONS;
  }
  switch (info.type) {
    case MLN_STYLE_SOURCE_TYPE_VECTOR:
      sourceClass = [MLNVectorTileSource class];
      break;
    case MLN_STYLE_SOURCE_TYPE_GEO_JSON:
      sourceClass = [MLNShapeSource class];
      break;
    case MLN_STYLE_SOURCE_TYPE_RASTER:
      sourceClass = [MLNRasterTileSource class];
      break;
    case MLN_STYLE_SOURCE_TYPE_RASTER_DEM:
      sourceClass = [MLNRasterDEMSource class];
      break;
    case MLN_STYLE_SOURCE_TYPE_IMAGE:
      sourceClass = [MLNImageSource class];
      break;
    default:
      sourceClass = [MLNSource class];
      break;
  }
  MLNSource *source = [[sourceClass alloc] initWithIdentifier:info.identifier style:self];
  [self mgl_registerSource:source];
  return source;
}

- (void)addSource:(MLNSource *)source {
  MLNLogDebug(@"Adding source: %@", source);
  if (!source.mgl_isConcrete) {
    [NSException
         raise:NSInvalidArgumentException
        format:@"The source %@ cannot be added to the style. "
               @"Make sure the source was created as a member of a concrete subclass of MLNSource.",
               source];
  }

  [source addToStylable:self.stylable];
  [self mgl_movePlaceholderLayersToSource:source.identifier];
}

- (void)removeSource:(MLNSource *)source {
  [self removeSource:source error:nil];
}

- (BOOL)removeSource:(MLNSource *)source error:(NSError *__nullable *__nullable)outError {
  MLNLogDebug(@"Removing source: %@", source);

  if (!source.mgl_isConcrete) {
    NSString *errorMessage = [NSString
        stringWithFormat:
            @"The source %@ cannot be removed from the style. "
            @"Make sure the source was created as a member of a concrete subclass of MLNSource."
            @"Automatic re-addition of sources after style changes is not currently supported.",
            source];

    if (outError) {
      *outError = [NSError errorWithDomain:MLNErrorDomain
                                      code:MLNErrorCodeSourceCannotBeRemovedFromStyle
                                  userInfo:@{NSLocalizedDescriptionKey : errorMessage}];
      return NO;
    } else {
      [NSException raise:NSInvalidArgumentException format:@"%@", errorMessage];
    }
  }

  return [source removeFromStylable:self.stylable error:outError];
}

- (nullable NSArray<MLNAttributionInfo *> *)attributionInfosWithFontSize:(CGFloat)fontSize
                                                               linkColor:
                                                                   (nullable MLNColor *)linkColor {
  // It’d be incredibly convenient to use -sources here, but this operation
  // depends on the sources being sorted in ascending order by creation, as
  // with the std::vector used in mbgl.
  NSArray<MLNFFISourceInfo *> *sourceInfos = [self mgl_sourceInfos];
  NSMutableArray *infos = [NSMutableArray arrayWithCapacity:sourceInfos.count];
  for (MLNFFISourceInfo *sourceInfo in sourceInfos) {
    MLNTileSource *source = (MLNTileSource *)[self sourceFromSourceInfo:sourceInfo];
    if (![source isKindOfClass:[MLNTileSource class]]) {
      continue;
    }

    NSArray *tileSetInfos = [source attributionInfosWithFontSize:fontSize linkColor:linkColor];
    [infos growArrayByAddingAttributionInfosFromArray:tileSetInfos];
  }
  return infos;
}

// MARK: Style layers

/// The style's layers from bottom to top, without the SDK's own.
- (NSArray<MLNFFILayerInfo *> *)mgl_layerInfos {
  NSMutableArray *infos = [NSMutableArray array];
  for (MLNFFILayerInfo *info in [self.mgl_map styleLayers]) {
    if (![info.identifier hasPrefix:MLNInternalStyleIdentifierPrefix]) {
      [infos addObject:info];
    }
  }
  return infos;
}

- (NSArray<__kindof MLNStyleLayer *> *)layers {
  NSArray<MLNFFILayerInfo *> *infos = [self mgl_layerInfos];
  NSMutableArray<__kindof MLNStyleLayer *> *styleLayers =
      [NSMutableArray arrayWithCapacity:infos.count];
  for (MLNFFILayerInfo *info in infos) {
    [styleLayers addObject:[self layerFromLayerInfo:info]];
  }
  return styleLayers;
}

- (void)setLayers:(NSArray<__kindof MLNStyleLayer *> *)layers {
  MLNLogDebug(@"Setting: %lu layers", layers.count);
  for (MLNStyleLayer *layer in self.layers) {
    [self removeLayer:layer];
  }
  for (MLNStyleLayer *layer in layers) {
    [self addLayer:layer];
  }
}

- (NSUInteger)countOfLayers {
  return [self mgl_layerInfos].count;
}

- (MLNStyleLayer *)objectInLayersAtIndex:(NSUInteger)index {
  NSArray<MLNFFILayerInfo *> *layers = [self mgl_layerInfos];
  if (index >= layers.count) {
    [NSException raise:NSRangeException
                format:@"No style layer at index %lu.", (unsigned long)index];
    return nil;
  }
  return [self layerFromLayerInfo:layers[index]];
}

- (void)getLayers:(MLNStyleLayer **)buffer range:(NSRange)inRange {
  NSArray<MLNFFILayerInfo *> *layers = [self mgl_layerInfos];
  if (NSMaxRange(inRange) > layers.count) {
    [NSException raise:NSRangeException
                format:@"Style layer range %@ is out of bounds.", NSStringFromRange(inRange)];
  }
  for (NSUInteger i = 0; i < inRange.length; i++) {
    buffer[i] = [self layerFromLayerInfo:layers[inRange.location + i]];
  }
}

- (void)insertObject:(MLNStyleLayer *)styleLayer inLayersAtIndex:(NSUInteger)index {
  if (!styleLayer.mgl_map) {
    [NSException raise:NSInvalidArgumentException
                format:@"The style layer %@ cannot be inserted into the style. "
                       @"Make sure the style layer was created as a member of a concrete subclass "
                       @"of MLNStyleLayer.",
                       styleLayer];
  }
  NSArray<MLNFFILayerInfo *> *layers = [self mgl_layerInfos];
  if (index > layers.count) {
    [NSException
         raise:NSRangeException
        format:@"Cannot insert style layer at out-of-bounds index %lu.", (unsigned long)index];
  } else if (index == 0) {
    MLNStyleLayer *sibling = layers.count ? [self layerFromLayerInfo:layers[0]] : nil;
    [styleLayer addToStyle:self belowLayer:sibling];
  } else {
    // As classic, which indexed layers.at(index): out of range at the top.
    if (index >= layers.count) {
      [NSException raise:MLNRedundantLayerIdentifierException
                  format:@"Cannot insert style layer at index %lu.", (unsigned long)index];
    }
    MLNStyleLayer *sibling = [self layerFromLayerInfo:layers[index]];
    [styleLayer addToStyle:self belowLayer:sibling];
  }
}

- (void)removeObjectFromLayersAtIndex:(NSUInteger)index {
  NSArray<MLNFFILayerInfo *> *layers = [self mgl_layerInfos];
  if (index >= layers.count) {
    [NSException
         raise:NSRangeException
        format:@"Cannot remove style layer at out-of-bounds index %lu.", (unsigned long)index];
  }
  MLNStyleLayer *styleLayer = [self layerFromLayerInfo:layers[index]];
  [styleLayer removeFromStyle:self];
}

- (MLNStyleLayer *)layerFromLayerInfo:(MLNFFILayerInfo *)info {
  NSParameterAssert(info);

  if (MLNStyleLayer *layer = [self mgl_registeredLayerWithIdentifier:info.identifier]) {
    return layer;
  }

  Class layerClass = MLNStyleLayerClassForType(info.type);
  MLNStyleLayer *layer = [[layerClass alloc] initWithIdentifier:info.identifier style:self];
  [self mgl_registerLayer:layer];
  return layer;
}

- (MLNStyleLayer *)layerWithIdentifier:(NSString *)identifier {
  MLNLogDebug(@"Querying layerWithIdentifier: %@", identifier);
  if (!identifier || [identifier hasPrefix:MLNInternalStyleIdentifierPrefix]) {
    return nil;
  }
  MLNFFILayerInfo *info = [self.mgl_map styleLayerWithIdentifier:identifier];
  return info ? [self layerFromLayerInfo:info] : nil;
}

- (void)removeLayer:(MLNStyleLayer *)layer {
  MLNLogDebug(@"Removing layer: %@", layer);
  if (!layer.mgl_map) {
    [NSException raise:NSInvalidArgumentException
                format:@"The style layer %@ cannot be removed from the style. "
                       @"Make sure the style layer was created as a member of a concrete subclass "
                       @"of MLNStyleLayer.",
                       layer];
  }
  [self willChangeValueForKey:@"layers"];
  [layer removeFromStyle:self];
  [self didChangeValueForKey:@"layers"];
}

- (void)addLayer:(MLNStyleLayer *)layer {
  MLNLogDebug(@"Adding layer: %@", layer);
  if (!layer.mgl_map) {
    [NSException raise:NSInvalidArgumentException
                format:@"The style layer %@ cannot be added to the style. "
                       @"Make sure the style layer was created as a member of a concrete subclass "
                       @"of MLNStyleLayer.",
                       layer];
  }
  [self willChangeValueForKey:@"layers"];
  [layer addToStyle:self belowLayer:nil];
  [self didChangeValueForKey:@"layers"];
}

- (void)insertLayer:(MLNStyleLayer *)layer atIndex:(NSUInteger)index {
  [self insertObject:layer inLayersAtIndex:index];
}

- (void)insertLayer:(MLNStyleLayer *)layer belowLayer:(MLNStyleLayer *)sibling {
  MLNLogDebug(@"Inseting layer: %@ belowLayer: %@", layer, sibling);
  if (!layer.mgl_map) {
    [NSException raise:NSInvalidArgumentException
                format:@"The style layer %@ cannot be added to the style. "
                       @"Make sure the style layer was created as a member of a concrete subclass "
                       @"of MLNStyleLayer.",
                       layer];
  }
  if (!sibling.mgl_map) {
    [NSException raise:NSInvalidArgumentException
                format:@"A style layer cannot be placed below %@ in the style. "
                       @"Make sure sibling was obtained using -[MLNStyle layerWithIdentifier:].",
                       sibling];
  }
  [self willChangeValueForKey:@"layers"];
  [layer addToStyle:self belowLayer:sibling];
  [self didChangeValueForKey:@"layers"];
}

- (void)insertLayer:(MLNStyleLayer *)layer aboveLayer:(MLNStyleLayer *)sibling {
  MLNLogDebug(@"Inseting layer: %@ aboveLayer: %@", layer, sibling);
  if (!layer.mgl_map) {
    [NSException raise:NSInvalidArgumentException
                format:@"The style layer %@ cannot be added to the style. "
                       @"Make sure the style layer was created as a member of a concrete subclass "
                       @"of MLNStyleLayer.",
                       layer];
  }
  if (!sibling.mgl_map) {
    [NSException raise:NSInvalidArgumentException
                format:@"A style layer cannot be placed above %@ in the style. "
                       @"Make sure sibling was obtained using -[MLNStyle layerWithIdentifier:].",
                       sibling];
  }

  NSArray<MLNFFILayerInfo *> *layers = [self mgl_layerInfos];
  NSUInteger index = 0;
  for (MLNFFILayerInfo *siblingLayer in layers) {
    if ([siblingLayer.identifier isEqualToString:sibling.identifier]) {
      break;
    }
    index++;
  }

  [self willChangeValueForKey:@"layers"];
  if (index + 1 > layers.count) {
    [NSException raise:NSInvalidArgumentException
                format:@"A style layer cannot be placed above %@ in the style. "
                       @"Make sure sibling was obtained using -[MLNStyle layerWithIdentifier:].",
                       sibling];
  } else if (index + 1 == layers.count) {
    [layer addToStyle:self belowLayer:nil];
  } else {
    MLNStyleLayer *nextSibling = [self layerFromLayerInfo:layers[index + 1]];
    [layer addToStyle:self belowLayer:nextSibling];
  }
  [self didChangeValueForKey:@"layers"];
}

// MARK: Style images

- (void)setImage:(MLNImage *)image forName:(NSString *)name {
  MLNLogDebug(@"Setting image: %@ forName: %@", image, name);
  if (!image) {
    [NSException raise:NSInvalidArgumentException format:@"Cannot assign nil image to “%@”.", name];
  }
  if (!name) {
    [NSException raise:NSInvalidArgumentException
                format:@"Cannot assign image %@ to a nil name.", image];
  }

  [image mgl_addToMap:self.mgl_map withName:name];
}

- (void)removeImageForName:(NSString *)name {
  MLNLogDebug(@"Removing imageForName: %@", name);
  if (!name) {
    [NSException raise:NSInvalidArgumentException format:@"Cannot remove image with nil name."];
  }

  [self.mgl_map removeStyleImage:name message:nil];
}

- (MLNImage *)imageForName:(NSString *)name {
  MLNLogDebug(@"Querying imageForName: %@", name);
  if (!name) {
    [NSException raise:NSInvalidArgumentException format:@"Cannot get image with nil name."];
  }

  MLNFFIStyleImage *styleImage = [self.mgl_map styleImageNamed:name];
  return styleImage ? [[MLNImage alloc] initWithMLNStyleImage:styleImage] : nil;
}

// MARK: Global state

- (NSDictionary<NSString *, id> *)globalState {
  return [[self.mgl_map globalState] copy] ?: @{};
}

- (void)setGlobalStateValue:(id)value forProperty:(NSString *)propertyName {
  MLNLogDebug(@"Setting global state property: %@", propertyName);
  NSString *message;
  if ([self.mgl_map setGlobalStateProperty:propertyName
                                     value:MLNJSONObjectFromFoundationValue(value)
                                   message:&message] != MLN_STATUS_OK) {
    [NSException raise:NSInternalInconsistencyException format:@"%@", message];
  }
}

// MARK: Style transitions

// mbgl::style::TransitionOptions as the C API reports it: unset durations are
// zero, and placement transitions are on unless disabled.
- (void)setTransition:(MLNTransition)transition {
  mln_style_transition_options options = [self.mgl_map styleTransitionOptions];
  options.fields |= MLN_STYLE_TRANSITION_OPTION_DURATION | MLN_STYLE_TRANSITION_OPTION_DELAY;
  options.duration_ms = transition.duration * 1000;
  options.delay_ms = transition.delay * 1000;
  [self.mgl_map setStyleTransitionOptions:options message:nil];
}

- (MLNTransition)transition {
  mln_style_transition_options options = [self.mgl_map styleTransitionOptions];
  MLNTransition transition;
  transition.duration =
      (options.fields & MLN_STYLE_TRANSITION_OPTION_DURATION) ? options.duration_ms / 1000 : 0;
  transition.delay = (options.fields & MLN_STYLE_TRANSITION_OPTION_DELAY) ? options.delay_ms / 1000 : 0;
  return transition;
}

- (void)setPerformsPlacementTransitions:(BOOL)performsPlacementTransitions {
  mln_style_transition_options options = [self.mgl_map styleTransitionOptions];
  options.fields |= MLN_STYLE_TRANSITION_OPTION_ENABLE_PLACEMENT_TRANSITIONS;
  options.enable_placement_transitions = performsPlacementTransitions;
  [self.mgl_map setStyleTransitionOptions:options message:nil];
}

- (BOOL)performsPlacementTransitions {
  mln_style_transition_options options = [self.mgl_map styleTransitionOptions];
  if (!(options.fields & MLN_STYLE_TRANSITION_OPTION_ENABLE_PLACEMENT_TRANSITIONS)) {
    return YES;
  }
  return options.enable_placement_transitions;
}

// MARK: Style light

- (void)setLight:(MLNLight *)light {
  // Classic converted each property when it built the core light and raised
  // for an invalid value; the C API validates the light as a whole.
  NSString *message;
  if ([self.mgl_map setStyleLightJSON:[light mgl_lightJSON] message:&message] != MLN_STATUS_OK) {
    for (NSString *prefix in @[ @"style light: ", @"light property: ", @"light: " ]) {
      if ([message hasPrefix:prefix]) {
        message = [message substringFromIndex:prefix.length];
      }
    }
    [NSException raise:NSInvalidArgumentException format:@"Invalid property value: %@", message];
  }
}

- (MLNLight *)light {
  MLNFFIMap *map = self.mgl_map;
  return [[MLNLight alloc] initWithLightJSONProvider:^id(NSString *name) {
    return [map styleLightProperty:name];
  }];
}

- (NSString *)description {
  return [NSString
      stringWithFormat:@"<%@: %p; name = %@, URL = %@>", NSStringFromClass([self class]),
                       (void *)self,
                       self.name ? [NSString stringWithFormat:@"\"%@\"", self.name] : self.name,
                       self.URL ? [NSString stringWithFormat:@"\"%@\"", self.URL] : self.URL];
}

// MARK: Mapbox Streets source introspection

- (void)localizeLabelsIntoLocale:(nullable NSLocale *)locale {
  NSSet<MLNVectorTileSource *> *streetsSources = [self.sources
      filteredSetUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(
                                                 MLNVectorTileSource *_Nullable source,
                                                 NSDictionary<NSString *, id> *_Nullable bindings) {
        return [source isKindOfClass:[MLNVectorTileSource class]] && [source isMapboxStreets];
      }]];
  NSSet<NSString *> *streetsSourceIdentifiers = [streetsSources valueForKey:@"identifier"];

  for (MLNSymbolStyleLayer *layer in self.layers) {
    if (![layer isKindOfClass:[MLNSymbolStyleLayer class]]) {
      continue;
    }
    if (![streetsSourceIdentifiers containsObject:layer.sourceIdentifier]) {
      continue;
    }

    NSExpression *text = layer.text;
    NSExpression *localizedText = [text mgl_expressionLocalizedIntoLocale:locale];
    if (![localizedText isEqual:text]) {
      layer.text = localizedText;
    }
  }
}

- (NSSet<MLNVectorTileSource *> *)mapboxStreetsSources {
  return [self.sources
      objectsPassingTest:^BOOL(__kindof MLNVectorTileSource *_Nonnull source, BOOL *_Nonnull stop) {
        return [source isKindOfClass:[MLNVectorTileSource class]] && source.mapboxStreets;
      }];
}

- (NSArray<MLNStyleLayer *> *)placeStyleLayers {
  NSSet *streetsSourceIdentifiers = [self.mapboxStreetsSources valueForKey:@"identifier"];

  NSSet *placeSourceLayerIdentifiers =
      [NSSet setWithObjects:@"marine_label", @"country_label", @"state_label", @"place_label",
                            @"water_label", @"poi_label", @"rail_station_label",
                            @"mountain_peak_label", @"natural_label", @"transit_stop_label", nil];
  NSPredicate *isPlacePredicate =
      [NSPredicate predicateWithBlock:^BOOL(MLNVectorStyleLayer *_Nullable layer,
                                            NSDictionary<NSString *, id> *_Nullable bindings) {
        return [layer isKindOfClass:[MLNVectorStyleLayer class]] &&
               [streetsSourceIdentifiers containsObject:layer.sourceIdentifier] &&
               [placeSourceLayerIdentifiers containsObject:layer.sourceLayerIdentifier];
      }];
  return [self.layers filteredArrayUsingPredicate:isPlacePredicate];
}

- (NSArray<MLNStyleLayer *> *)roadStyleLayers {
  NSSet *streetsSourceIdentifiers = [self.mapboxStreetsSources valueForKey:@"identifier"];

  NSSet *roadStyleLayerIdentifiers = [NSSet setWithObjects:@"road_label", @"road", nil];
  NSPredicate *isPlacePredicate =
      [NSPredicate predicateWithBlock:^BOOL(MLNVectorStyleLayer *_Nullable layer,
                                            NSDictionary<NSString *, id> *_Nullable bindings) {
        return [layer isKindOfClass:[MLNVectorStyleLayer class]] &&
               [streetsSourceIdentifiers containsObject:layer.sourceIdentifier] &&
               [roadStyleLayerIdentifiers containsObject:layer.sourceLayerIdentifier];
      }];
  return [self.layers filteredArrayUsingPredicate:isPlacePredicate];
}

@end
