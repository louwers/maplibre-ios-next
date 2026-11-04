// Based on platform/darwin/src/MLNStyleLayer.mm at ios-v7.0.0

#import "MLNStyleLayer_Private.h"

#import "MLNBackgroundStyleLayer.h"
#import "MLNCircleStyleLayer.h"
#import "MLNColorReliefStyleLayer.h"
#import "MLNFillExtrusionStyleLayer.h"
#import "MLNFillStyleLayer.h"
#import "MLNHeatmapStyleLayer.h"
#import "MLNHillshadeStyleLayer.h"
#import "MLNLineStyleLayer.h"
#import "MLNLoggingConfiguration_Private.h"
#import "MLNRasterStyleLayer.h"
#import "MLNStyle_Private.h"
#import "MLNSymbolStyleLayer.h"
#import "NSExpression+MLNPrivateAdditions.h"
#import "NSPredicate+MLNAdditions.h"
#import "MLNStyleSpec.h"

#include <atomic>

const MLNExceptionName MLNInvalidStyleLayerException = @"MLNInvalidStyleLayerException";

Class MLNStyleLayerClassForType(NSString *type) {
  static NSDictionary<NSString *, Class> *classes;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    classes = @{
      @"background" : [MLNBackgroundStyleLayer class],
      @"circle" : [MLNCircleStyleLayer class],
      @"color-relief" : [MLNColorReliefStyleLayer class],
      @"fill" : [MLNFillStyleLayer class],
      @"fill-extrusion" : [MLNFillExtrusionStyleLayer class],
      @"heatmap" : [MLNHeatmapStyleLayer class],
      @"hillshade" : [MLNHillshadeStyleLayer class],
      @"line" : [MLNLineStyleLayer class],
      @"raster" : [MLNRasterStyleLayer class],
      @"symbol" : [MLNSymbolStyleLayer class],
    };
  });
  // Layer types without a darwin peer (location-indicator, plugins) are
  // represented by the abstract class, as LayerManagerDarwin did.
  return classes[type] ?: [MLNStyleLayer class];
}

/// The source type a pending layer's placeholder source needs in the scratch
/// map, which, unlike classic's core, refuses layers whose source is missing.
static NSDictionary *MLNPlaceholderSourceForLayerType(NSString *type) {
  if ([type isEqualToString:@"raster"]) {
    return @{@"type" : @"raster", @"tiles" : @[]};
  }
  if ([type isEqualToString:@"hillshade"] || [type isEqualToString:@"color-relief"]) {
    return @{@"type" : @"raster-dem", @"tiles" : @[]};
  }
  return @{@"type" : @"geojson", @"data" : @{@"type" : @"FeatureCollection", @"features" : @[]}};
}

/// The core serializes constant formatted text and image values in a form
/// that it does not parse back ({"sections": …}, {"name": …}). Rewrites them
/// as values it parses to the same constants, so a layer's JSON can be added
/// to another map.
static id MLNReparsableStyleValue(id value) {
  if (![value isKindOfClass:[NSDictionary class]]) {
    return value;
  }
  NSDictionary *dictionary = value;
  if ([dictionary[@"sections"] isKindOfClass:[NSArray class]]) {
    NSMutableArray *format = [NSMutableArray arrayWithObject:@"format"];
    for (NSDictionary *section in dictionary[@"sections"]) {
      id image = section[@"image"];
      if (image && image != [NSNull null]) {
        id name = [image isKindOfClass:[NSDictionary class]] ? image[@"name"] : image;
        [format addObject:@[ @"image", name ?: @"" ]];
        [format addObject:@{}];
        continue;
      }
      [format addObject:section[@"text"] ?: @""];
      NSMutableDictionary *options = [NSMutableDictionary dictionary];
      if ([section[@"scale"] isKindOfClass:[NSNumber class]]) {
        options[@"font-scale"] = section[@"scale"];
      }
      if ([section[@"fontStack"] isKindOfClass:[NSString class]]) {
        options[@"text-font"] =
            @[ @"literal", [section[@"fontStack"] componentsSeparatedByString:@","] ];
      }
      id textColor = section[@"textColor"];
      if (textColor && textColor != [NSNull null]) {
        options[@"text-color"] = textColor;
      }
      [format addObject:options];
    }
    return format;
  }
  if ([dictionary[@"name"] isKindOfClass:[NSString class]] && dictionary[@"available"]) {
    NSString *name = dictionary[@"name"];
    // A plain string would be read as a token string if it has braces.
    return [name containsString:@"{"] ? @[ @"image", name ] : name;
  }
  return value;
}

NSDictionary *MLNReparsableLayerJSON(NSDictionary *layer) {
  NSMutableDictionary *json = [layer mutableCopy];
  for (NSString *section in @[ @"layout", @"paint" ]) {
    NSDictionary *properties = layer[section];
    if (![properties isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSMutableDictionary *rewritten = [NSMutableDictionary dictionaryWithCapacity:properties.count];
    [properties enumerateKeysAndObjectsUsingBlock:^(NSString *name, id value, BOOL *stop) {
      rewritten[name] = MLNReparsableStyleValue(value);
    }];
    json[section] = rewritten;
  }
  return json;
}

/// The core's message in a C API diagnostic, which prefixes it with the kind
/// of value that failed to convert.
static NSString *MLNCoreErrorMessage(NSString *diagnostic) {
  for (NSString *prefix in @[ @"layer property: ", @"light property: ", @"style layer: " ]) {
    if ([diagnostic hasPrefix:prefix]) {
      return [diagnostic substringFromIndex:prefix.length];
    }
  }
  return diagnostic;
}

static NSString *MLNNextPendingIdentifier(void) {
  static std::atomic<uint64_t> counter{0};
  return [NSString stringWithFormat:@"org.maplibre.next.pending.%llu", ++counter];
}

@interface MLNStyleLayer ()
@property (nonatomic, readwrite, copy) NSString *identifier;
@end

@implementation MLNStyleLayer {
  // While pending: the layer in the scratch map, its placeholder source, and
  // the source the layer refers to in public.
  NSString *_pendingLayerIdentifier;
  NSString *_pendingPlaceholderSourceIdentifier;
  NSString *_pendingSourceIdentifier;
  NSString *_layerType;
  // While added: the style.
  __weak MLNStyle *_style;
  BOOL _invalidated;
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                         layerType:(NSString *)layerType
                  sourceIdentifier:(NSString *)sourceIdentifier {
  if (self = [super init]) {
    _identifier = [identifier copy];
    _layerType = [layerType copy];
    [self mgl_becomePendingWithJSON:@{@"type" : layerType} sourceIdentifier:sourceIdentifier];
  }
  return self;
}

- (instancetype)initWithIdentifier:(NSString *)identifier style:(MLNStyle *)style {
  if (self = [super init]) {
    _identifier = [identifier copy];
    _style = style;
  }
  return self;
}

- (void)dealloc {
  [self mgl_removePendingLayer];
}

/// Recreates the layer in the scratch map from its JSON.
- (void)mgl_becomePendingWithJSON:(NSDictionary *)json sourceIdentifier:(NSString *)sourceIdentifier {
  MLNFFIMap *scratch = [MLNFFIMap scratchMap];
  NSString *pendingIdentifier = MLNNextPendingIdentifier();
  NSMutableDictionary *layer = [MLNReparsableLayerJSON(json) mutableCopy];
  layer[@"id"] = pendingIdentifier;
  _layerType = json[@"type"] ?: _layerType;
  if (sourceIdentifier.length) {
    NSString *placeholder = [pendingIdentifier stringByAppendingString:@".source"];
    [scratch addStyleSourceJSON:MLNPlaceholderSourceForLayerType(_layerType)
                     identifier:placeholder
                        message:nil];
    layer[@"source"] = placeholder;
    _pendingPlaceholderSourceIdentifier = placeholder;
  } else {
    [layer removeObjectForKey:@"source"];
    _pendingPlaceholderSourceIdentifier = nil;
  }
  NSString *message;
  if ([scratch addStyleLayerJSON:layer belowLayer:nil message:&message] != MLN_STATUS_OK) {
    MLNLogError(@"Failed to create layer %@: %@", self.identifier, message);
  }
  _pendingLayerIdentifier = pendingIdentifier;
  _pendingSourceIdentifier = [sourceIdentifier copy];
}

- (void)mgl_removePendingLayer {
  if (!_pendingLayerIdentifier) {
    return;
  }
  MLNFFIMap *scratch = [MLNFFIMap scratchMap];
  [scratch removeStyleLayer:_pendingLayerIdentifier message:nil];
  if (_pendingPlaceholderSourceIdentifier) {
    [scratch removeStyleSource:_pendingPlaceholderSourceIdentifier message:nil];
  }
  _pendingLayerIdentifier = nil;
  _pendingPlaceholderSourceIdentifier = nil;
}

- (BOOL)mgl_isPending {
  return _pendingLayerIdentifier != nil;
}

- (MLNStyle *)mgl_style {
  return _pendingLayerIdentifier ? nil : _style;
}

- (MLNFFIMap *)mgl_map {
  if (_invalidated) {
    return nil;
  }
  if (_pendingLayerIdentifier) {
    return [MLNFFIMap scratchMap];
  }
  return _style.mgl_map;
}

- (NSString *)mgl_mapLayerIdentifier {
  return _pendingLayerIdentifier ?: self.identifier;
}

- (void)mgl_invalidate {
  _invalidated = YES;
  _style = nil;
}

- (void)addToStyle:(MLNStyle *)style belowLayer:(MLNStyleLayer *)otherLayer {
  if (!_pendingLayerIdentifier) {
    [NSException raise:MLNRedundantLayerException
                format:@"This instance %@ was already added to %@. Adding the same layer instance "
                        "to the style more than once is invalid.",
                       self, style];
  }

  NSMutableDictionary *json =
      [MLNReparsableLayerJSON([[MLNFFIMap scratchMap] styleLayerJSON:_pendingLayerIdentifier] ?: @{})
          mutableCopy];
  json[@"id"] = self.identifier;
  if (_pendingSourceIdentifier.length) {
    json[@"source"] = _pendingSourceIdentifier;
  }
  NSString *before = otherLayer.identifier;
  // Classic's core put a layer on top when the layer to insert it below was
  // not in the style; the C API refuses that.
  if (before && ![style.mgl_map styleLayerWithIdentifier:before]) {
    before = nil;
  }
  NSString *message;
  mln_status status = [style.mgl_map addStyleLayerJSON:json belowLayer:before message:&message];
  if (status == MLN_STATUS_NOT_FOUND && _pendingSourceIdentifier.length &&
      ![style.mgl_map styleSourceWithIdentifier:_pendingSourceIdentifier]) {
    // Classic's core accepted a layer before its source. The C API refuses
    // it, so the style stands in a hidden placeholder source until the real
    // one is added (C_API_GAPS.md).
    NSString *placeholder = [style mgl_placeholderSourceForSource:_pendingSourceIdentifier
                                                        layerType:_layerType];
    if (placeholder) {
      json[@"source"] = placeholder;
      status = [style.mgl_map addStyleLayerJSON:json belowLayer:before message:&message];
    }
  }
  if (status != MLN_STATUS_OK) {
    [NSException raise:MLNRedundantLayerIdentifierException format:@"%@", message];
  }
  [self mgl_didAttachToStyle:style];
}

- (void)mgl_didAttachToStyle:(MLNStyle *)style {
  [self mgl_removePendingLayer];
  _style = style;
  [style mgl_registerLayer:self];
}

- (void)removeFromStyle:(MLNStyle *)style {
  if (_pendingLayerIdentifier || _style != style || [style mgl_registeredLayerWithIdentifier:self.identifier] != self) {
    return;
  }
  NSDictionary *json = [style.mgl_map styleLayerJSON:self.identifier];
  if (!json) {
    return;
  }
  MLNFFILayerInfo *info = [style.mgl_map styleLayerWithIdentifier:self.identifier];
  NSString *message;
  if ([style.mgl_map removeStyleLayer:self.identifier message:&message] != MLN_STATUS_OK) {
    MLNLogError(@"Failed to remove layer %@: %@", self.identifier, message);
    return;
  }
  [style mgl_unregisterLayer:self];
  _style = nil;
  [self mgl_becomePendingWithJSON:json
                 sourceIdentifier:[style mgl_sourceIdentifierForMapSource:info.sourceIdentifier]];
}

// MARK: - Properties

- (void)mgl_setJSON:(id)json forProperty:(NSString *)name errorFormat:(NSString *)errorFormat {
  NSString *message;
  mln_status status = [self.mgl_map setStyleLayerProperty:name
                                                    layer:self.mgl_mapLayerIdentifier
                                                    value:json
                                                  message:&message];
  if (status != MLN_STATUS_OK) {
    [NSException raise:NSInvalidArgumentException format:errorFormat, MLNCoreErrorMessage(message)];
  }
}

- (id)mgl_JSONForProperty:(NSString *)name {
  return [self.mgl_map styleLayerProperty:name layer:self.mgl_mapLayerIdentifier status:nil];
}

- (MLNFFILayerInfo *)mgl_layerInfo {
  return [self.mgl_map styleLayerWithIdentifier:self.mgl_mapLayerIdentifier];
}

- (void)mgl_setExpression:(NSExpression *)expression
              forProperty:(const MLNStylePropertyDescriptor *)descriptor {
  id json = MLNStyleJSONFromExpression(expression, descriptor);
  [self mgl_setJSON:json forProperty:@(descriptor->name) errorFormat:@"Invalid property value: %@"];
}

- (NSExpression *)mgl_expressionForProperty:(const MLNStylePropertyDescriptor *)descriptor {
  id json = [self mgl_JSONForProperty:@(descriptor->name)];
  if (!json) {
    json = MLNStyleDefaultValueJSON(_layerType ?: self.mgl_layerInfo.type, descriptor);
  }
  return MLNExpressionFromStyleJSON(json, descriptor);
}

- (void)mgl_setTransition:(MLNTransition)transition
              forProperty:(const MLNStylePropertyDescriptor *)descriptor {
  NSString *name = [@(descriptor->name) stringByAppendingString:@"-transition"];
  [self mgl_setJSON:MLNStyleJSONFromTransition(transition)
        forProperty:name
        errorFormat:@"Invalid transition: %@"];
}

- (MLNTransition)mgl_transitionForProperty:(const MLNStylePropertyDescriptor *)descriptor {
  NSString *name = [@(descriptor->name) stringByAppendingString:@"-transition"];
  return MLNTransitionFromStyleJSON([self mgl_JSONForProperty:name]);
}

- (NSString *)mgl_sourceIdentifier {
  if (_pendingLayerIdentifier) {
    return _pendingSourceIdentifier ?: @"";
  }
  return [self.mgl_style mgl_sourceIdentifierForMapSource:self.mgl_layerInfo.sourceIdentifier ?: @""];
}

- (NSString *)mgl_sourceLayerIdentifier {
  NSString *sourceLayer = self.mgl_layerInfo.sourceLayerIdentifier;
  return sourceLayer.length ? sourceLayer : nil;
}

- (void)setMgl_sourceLayerIdentifier:(NSString *)sourceLayerIdentifier {
  [self mgl_setJSON:sourceLayerIdentifier ?: @""
        forProperty:@"source-layer"
        errorFormat:@"Invalid source layer: %@"];
}

- (NSPredicate *)mgl_predicate {
  id json = [self mgl_JSONForProperty:@"filter"];
  return json ? [NSPredicate predicateWithMLNJSONObject:json] : nil;
}

- (void)setMgl_predicate:(NSPredicate *)predicate {
  [self mgl_setJSON:predicate ? predicate.mgl_jsonExpressionObject : [NSNull null]
        forProperty:@"filter"
        errorFormat:@"Invalid filter value: %@"];
}

// MARK: - Public

- (void)setVisible:(BOOL)visible {
  MLNAssertStyleLayerIsValid();

  [self mgl_setJSON:visible ? @"visible" : @"none"
        forProperty:@"visibility"
        errorFormat:@"Invalid visibility: %@"];
}

- (BOOL)isVisible {
  MLNAssertStyleLayerIsValid();

  return self.mgl_layerInfo.visible;
}

- (void)setVisibilityExpression:(NSExpression *)expression {
  MLNAssertStyleLayerIsValid();

  if (!expression) {
    [self mgl_setJSON:@"visible" forProperty:@"visibility" errorFormat:@"%@"];
    return;
  }
  [self mgl_setJSON:expression.mgl_jsonExpressionObject
        forProperty:@"visibility"
        errorFormat:@"Invalid visibility expression: %@"];
}

- (NSExpression *)visibilityExpression {
  MLNAssertStyleLayerIsValid();

  id visibility = [self.mgl_map styleLayerJSON:self.mgl_mapLayerIdentifier][@"layout"][@"visibility"];
  if (![visibility isKindOfClass:[NSArray class]]) {
    return nil;
  }
  return [NSExpression expressionWithMLNJSONObject:visibility];
}

- (void)setMaximumZoomLevel:(float)maximumZoomLevel {
  MLNAssertStyleLayerIsValid();

  [self mgl_setJSON:@(maximumZoomLevel) forProperty:@"maxzoom" errorFormat:@"%@"];
}

- (float)maximumZoomLevel {
  MLNAssertStyleLayerIsValid();

  return self.mgl_layerInfo.maximumZoom;
}

- (void)setMinimumZoomLevel:(float)minimumZoomLevel {
  MLNAssertStyleLayerIsValid();

  [self mgl_setJSON:@(minimumZoomLevel) forProperty:@"minzoom" errorFormat:@"%@"];
}

- (float)minimumZoomLevel {
  MLNAssertStyleLayerIsValid();

  return self.mgl_layerInfo.minimumZoom;
}

- (NSString *)description {
  if (self.mgl_map) {
    return [NSString stringWithFormat:@"<%@: %p; identifier = %@; visible = %@>",
                                      NSStringFromClass([self class]), (void *)self,
                                      self.identifier, self.visible ? @"YES" : @"NO"];
  } else {
    return
        [NSString stringWithFormat:@"<%@: %p; identifier = %@; visible = NO>",
                                   NSStringFromClass([self class]), (void *)self, self.identifier];
  }
}

@end
