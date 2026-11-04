// Based on platform/darwin/src/MLNShapeSource.mm at ios-v7.0.0

#import "MLNShapeSource_Private.h"

#import "MLNCluster.h"
#import "MLNFFISourceQueries.h"
#import "MLNGeoJSON.h"
#import "MLNLoggingConfiguration_Private.h"
#import "MLNMapView.h"
#import "MLNShapeCollection.h"
#import "MLNSource_Private.h"
#import "MLNStyleValue_Private.h"
#import "MLNStyle_Private.h"

#import "NSExpression+MLNPrivateAdditions.h"
#import "NSURL+MLNAdditions.h"

const MLNShapeSourceOption MLNShapeSourceOptionBuffer = @"MLNShapeSourceOptionBuffer";
const MLNShapeSourceOption MLNShapeSourceOptionClusterRadius = @"MLNShapeSourceOptionClusterRadius";
const MLNShapeSourceOption MLNShapeSourceOptionClusterMinPoints =
    @"MLNShapeSourceOptionClusterMinPoints";
const MLNShapeSourceOption MLNShapeSourceOptionClustered = @"MLNShapeSourceOptionClustered";
const MLNShapeSourceOption MLNShapeSourceOptionClusterProperties =
    @"MLNShapeSourceOptionClusterProperties";
const MLNShapeSourceOption MLNShapeSourceOptionMaximumZoomLevel =
    @"MLNShapeSourceOptionMaximumZoomLevel";
const MLNShapeSourceOption MLNShapeSourceOptionMaximumZoomLevelForClustering =
    @"MLNShapeSourceOptionMaximumZoomLevelForClustering";
const MLNShapeSourceOption MLNShapeSourceOptionMinimumZoomLevel =
    @"MLNShapeSourceOptionMinimumZoomLevel";
const MLNShapeSourceOption MLNShapeSourceOptionSimplificationTolerance =
    @"MLNShapeSourceOptionSimplificationTolerance";
const MLNShapeSourceOption MLNShapeSourceOptionLineDistanceMetrics =
    @"MLNShapeSourceOptionLineDistanceMetrics";
const MLNShapeSourceOption MLNShapeSourceOptionSynchronousUpdate =
    @"MLNShapeSourceOptionSynchronousUpdate";

@interface MLNGeoJSONSourceOptions ()
- (mln_geo_json_source_options *)mutableOptions;
- (void)setClusterProperties:(NSString *)clusterProperties;
@end

@implementation MLNGeoJSONSourceOptions {
  mln_geo_json_source_options _options;
  // Owns the bytes that _options.cluster_properties borrows.
  NSString *_clusterProperties;
}

- (instancetype)init {
  if (self = [super init]) {
    _options = (mln_geo_json_source_options){sizeof(mln_geo_json_source_options)};
  }
  return self;
}

- (mln_geo_json_source_options)options {
  return _options;
}

- (mln_geo_json_source_options *)mutableOptions {
  return &_options;
}

- (BOOL)clusters {
  return (_options.fields & MLN_GEO_JSON_SOURCE_OPTION_CLUSTER) && _options.cluster;
}

- (void)setClusterProperties:(NSString *)clusterProperties {
  _clusterProperties = [clusterProperties copy];
  _options.cluster_properties = MLNFFIBufferView(_clusterProperties);
}

@end

MLNGeoJSONSourceOptions *MLNGeoJSONOptionsFromDictionary(
    NSDictionary<MLNShapeSourceOption, id> *options) {
  MLNGeoJSONSourceOptions *wrapper = [[MLNGeoJSONSourceOptions alloc] init];
  mln_geo_json_source_options *geoJSONOptions = [wrapper mutableOptions];

  if (NSNumber *value = options[MLNShapeSourceOptionMinimumZoomLevel]) {
    if (![value isKindOfClass:[NSNumber class]]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"MLNShapeSourceOptionMaximumZoomLevel must be an NSNumber."];
    }
    geoJSONOptions->fields |= MLN_GEO_JSON_SOURCE_OPTION_MIN_ZOOM;
    geoJSONOptions->min_zoom = (uint8_t)value.integerValue;
  }

  if (NSNumber *value = options[MLNShapeSourceOptionMaximumZoomLevel]) {
    if (![value isKindOfClass:[NSNumber class]]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"MLNShapeSourceOptionMaximumZoomLevel must be an NSNumber."];
    }
    geoJSONOptions->fields |= MLN_GEO_JSON_SOURCE_OPTION_MAX_ZOOM;
    geoJSONOptions->max_zoom = (uint8_t)value.integerValue;
  }

  if (NSNumber *value = options[MLNShapeSourceOptionBuffer]) {
    if (![value isKindOfClass:[NSNumber class]]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"MLNShapeSourceOptionBuffer must be an NSNumber."];
    }
    geoJSONOptions->fields |= MLN_GEO_JSON_SOURCE_OPTION_BUFFER;
    geoJSONOptions->buffer = (uint16_t)value.integerValue;
  }

  if (NSNumber *value = options[MLNShapeSourceOptionSimplificationTolerance]) {
    if (![value isKindOfClass:[NSNumber class]]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"MLNShapeSourceOptionSimplificationTolerance must be an NSNumber."];
    }
    geoJSONOptions->fields |= MLN_GEO_JSON_SOURCE_OPTION_TOLERANCE;
    geoJSONOptions->tolerance = value.doubleValue;
  }

  if (NSNumber *value = options[MLNShapeSourceOptionClusterRadius]) {
    if (![value isKindOfClass:[NSNumber class]]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"MLNShapeSourceOptionClusterRadius must be an NSNumber."];
    }
    geoJSONOptions->fields |= MLN_GEO_JSON_SOURCE_OPTION_CLUSTER_RADIUS;
    geoJSONOptions->cluster_radius = (uint16_t)value.integerValue;
  }

  if (NSNumber *value = options[MLNShapeSourceOptionClusterMinPoints]) {
    if (![value isKindOfClass:[NSNumber class]]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"MLNShapeSourceOptionClusterMinPoints must be an NSNumber."];
    }
    geoJSONOptions->fields |= MLN_GEO_JSON_SOURCE_OPTION_CLUSTER_MIN_POINTS;
    geoJSONOptions->cluster_min_points = (uint32_t)value.integerValue;
  }

  if (NSNumber *value = options[MLNShapeSourceOptionMaximumZoomLevelForClustering]) {
    if (![value isKindOfClass:[NSNumber class]]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"MLNShapeSourceOptionMaximumZoomLevelForClustering must be an NSNumber."];
    }
    geoJSONOptions->fields |= MLN_GEO_JSON_SOURCE_OPTION_CLUSTER_MAX_ZOOM;
    geoJSONOptions->cluster_max_zoom = (uint8_t)value.integerValue;
  }

  if (NSNumber *value = options[MLNShapeSourceOptionClustered]) {
    if (![value isKindOfClass:[NSNumber class]]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"MLNShapeSourceOptionClustered must be an NSNumber."];
    }
    geoJSONOptions->fields |= MLN_GEO_JSON_SOURCE_OPTION_CLUSTER;
    geoJSONOptions->cluster = value.boolValue;
  }

  if (NSDictionary *value = options[MLNShapeSourceOptionClusterProperties]) {
    if (![value isKindOfClass:[NSDictionary<NSString *, NSArray *> class]]) {
      [NSException
           raise:NSInvalidArgumentException
          format:@"MLNShapeSourceOptionClusterProperties must be an NSDictionary with an NSString "
                 @"as a key and an array containing two NSExpression objects as a value."];
    }

    NSEnumerator *stringEnumerator = [value keyEnumerator];
    NSString *key;
    // The style-spec clusterProperties object: {name: [reduce, map]}.
    NSMutableDictionary *clusterProperties = [NSMutableDictionary dictionary];

    while (key = [stringEnumerator nextObject]) {
      NSArray *expressionsArray = value[key];
      if (![expressionsArray isKindOfClass:[NSArray class]]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"MLNShapeSourceOptionClusterProperties dictionary member value must be "
                           @"an array containing two objects."];
      }
      // Check that the array has 2 values. One should be a the reduce expression and one should be
      // the map expression.
      if ([expressionsArray count] != 2) {
        [NSException raise:NSInvalidArgumentException
                    format:@"MLNShapeSourceOptionClusterProperties member value requires array of "
                           @"two objects."];
      }

      // reduceExpression should be a valid NSExpression
      NSExpression *reduceExpression = expressionsArray[0];
      if (![reduceExpression isKindOfClass:[NSExpression class]]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"MLNShapeSourceOptionClusterProperties array value requires two "
                           @"expression objects."];
      }
      id reduce = reduceExpression.mgl_jsonExpressionObject;
      if (!reduce) {
        [NSException
             raise:NSInvalidArgumentException
            format:@"Failed to convert MLNShapeSourceOptionClusterProperties reduce expression."];
      }

      // mapExpression should be a valid NSExpression
      NSExpression *mapExpression = expressionsArray[1];
      if (![mapExpression isKindOfClass:[NSExpression class]]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"MLNShapeSourceOptionClusterProperties member value must contain a "
                           @"valid NSExpression."];
      }
      id map = mapExpression.mgl_jsonExpressionObject;
      if (!map) {
        [NSException
             raise:NSInvalidArgumentException
            format:@"Failed to convert MLNShapeSourceOptionClusterProperties map expression."];
      }

      clusterProperties[key] = @[ reduce, map ];
    }
    [wrapper setClusterProperties:MLNFFIJSONStringFromObject(clusterProperties)];
  }

  if (NSNumber *value = options[MLNShapeSourceOptionLineDistanceMetrics]) {
    if (![value isKindOfClass:[NSNumber class]]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"MLNShapeSourceOptionLineDistanceMetrics must be an NSNumber."];
    }
    geoJSONOptions->fields |= MLN_GEO_JSON_SOURCE_OPTION_LINE_METRICS;
    geoJSONOptions->line_metrics = value.boolValue;
  }

  if (NSNumber *value = options[MLNShapeSourceOptionSynchronousUpdate]) {
    if (![value isKindOfClass:[NSNumber class]]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"MLNShapeSourceOptionSynchronousUpdate must be an NSNumber."];
    }
    geoJSONOptions->fields |= MLN_GEO_JSON_SOURCE_OPTION_SYNCHRONOUS_TILING;
    geoJSONOptions->synchronous_tiling = value.boolValue;
  }

  return wrapper;
}

@interface MLNShapeSource ()

@property (nonatomic, readwrite) NSDictionary *options;

@end

@implementation MLNShapeSource {
  // The options the source was created with; nil for a source of a loaded
  // style, whose options the C API does not report.
  MLNGeoJSONSourceOptions *_geoJSONOptions;
  // The URL of a pending source.
  NSString *_pendingURL;
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                               URL:(NSURL *)url
                           options:(NSDictionary<NSString *, id> *)options {
  MLNGeoJSONSourceOptions *geoJSONOptions = MLNGeoJSONOptionsFromDictionary(options);
  if (self = [super initWithPendingIdentifier:identifier]) {
    _geoJSONOptions = geoJSONOptions;
    self.URL = url;
  }
  return self;
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                             shape:(nullable MLNShape *)shape
                           options:(NSDictionary<MLNShapeSourceOption, id> *)options {
  MLNGeoJSONSourceOptions *geoJSONOptions = MLNGeoJSONOptionsFromDictionary(options);
  if (self = [super initWithPendingIdentifier:identifier]) {
    _geoJSONOptions = geoJSONOptions;
    if ([shape isMemberOfClass:[MLNShapeCollection class]]) {
      static dispatch_once_t onceToken;
      dispatch_once(&onceToken, ^{
        NSLog(@"MLNShapeCollection initialized with MLNFeatures will not retain attributes."
              @"Use MLNShapeCollectionFeature to retain attributes instead."
              @"This will be logged only once.");
      });
    }
    self.shape = shape;
  }
  return self;
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                          features:(NSArray<MLNShape<MLNFeature> *> *)features
                           options:(nullable NSDictionary<MLNShapeSourceOption, id> *)options {
  for (id<MLNFeature> feature in features) {
    if (![feature conformsToProtocol:@protocol(MLNFeature)]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"The object %@ included in the features argument does not conform to the "
                         @"MLNFeature protocol.",
                         feature];
    }
  }
  MLNShapeCollectionFeature *shapeCollectionFeature =
      [MLNShapeCollectionFeature shapeCollectionWithShapes:features];
  return [self initWithIdentifier:identifier shape:shapeCollectionFeature options:options];
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                            shapes:(NSArray<MLNShape *> *)shapes
                           options:(nullable NSDictionary<MLNShapeSourceOption, id> *)options {
  MLNShapeCollection *shapeCollection = [MLNShapeCollection shapeCollectionWithShapes:shapes];
  return [self initWithIdentifier:identifier shape:shapeCollection options:options];
}

/// Prepares GeoJSON data for the C API with the source's options, as
/// GeoJSONData::create did for setGeoJSON. Returns MLN_HANDLE_NULL on failure.
- (mln_geo_json_source_data)mgl_preparedDataForShape:(MLNShape *)shape {
  MLNGeoJSONSourceOptions *geoJSONOptions = _geoJSONOptions;
  id geoJSON = shape ? MLNGeoJSONObjectFromShape(shape)
                     : @{@"type" : @"FeatureCollection", @"features" : @[]};
  // The C API takes only feature collections for clustered data; the core
  // took any GeoJSON and clustered its features.
  if (geoJSONOptions.clusters && ![geoJSON[@"type"] isEqual:@"FeatureCollection"]) {
    NSDictionary *feature = [geoJSON[@"type"] isEqual:@"Feature"]
                                ? geoJSON
                                : @{@"type" : @"Feature", @"geometry" : geoJSON, @"properties" : @{}};
    geoJSON = @{@"type" : @"FeatureCollection", @"features" : @[ feature ]};
  }
  NSString *json = MLNFFIJSONStringFromObject(geoJSON);
  mln_geo_json_source_options options = geoJSONOptions.options;
  mln_geo_json_source_data data = MLN_HANDLE_NULL;
  mln_diagnostic diagnostic = {sizeof(mln_diagnostic)};
  diagnostic.message[0] = '\0';
  if (mln_geo_json_source_data_create(MLNFFIBufferView(json), geoJSONOptions ? &options : NULL,
                                      &data, &diagnostic) != MLN_STATUS_OK) {
    MLNLogError(@"Failed to prepare the GeoJSON of source %@: %s", self.identifier,
                diagnostic.message);
    return MLN_HANDLE_NULL;
  }
  return data;
}

- (mln_status)mgl_addToMap:(MLNFFIMap *)map message:(NSString **)message {
  mln_map handle = map.handle;
  NSString *identifier = self.identifier;
  if (_pendingURL) {
    NSString *url = _pendingURL;
    MLNGeoJSONSourceOptions *geoJSONOptions = _geoJSONOptions;
    mln_geo_json_source_options options = geoJSONOptions.options;
    return [map call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
      return mln_map_add_geo_json_source_url(handle, MLNFFIBufferView(identifier),
                                             MLNFFIBufferView(url), geoJSONOptions ? &options : NULL,
                                             completion, diagnostic);
    }
             consume:nil
             message:message];
  }
  mln_geo_json_source_data data = [self mgl_preparedDataForShape:_shape];
  if (data == MLN_HANDLE_NULL) {
    if (message) {
      *message = @"The source’s GeoJSON could not be prepared.";
    }
    return MLN_STATUS_INVALID_ARGUMENT;
  }
  mln_status status = [map call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_add_geo_json_source_data(handle, MLNFFIBufferView(identifier), data, completion,
                                            diagnostic);
  }
                        consume:nil
                        message:message];
  mln_geo_json_source_data_release(data);
  return status;
}

- (void)mgl_willDetachFromMap:(MLNFFIMap *)map {
  // Keep a URL the source loads from so it can be added again. Inline data of
  // a source of a loaded style cannot be read back (C_API_GAPS.md).
  if (!_shape && !_pendingURL) {
    NSString *url = [map styleSourceWithIdentifier:self.identifier].URL;
    _pendingURL = url.length ? url : nil;
  }
}

- (NSURL *)URL {
  MLNAssertStyleSourceIsValid();
  NSString *url;
  if (self.mgl_style) {
    url = [self.mgl_map styleSourceWithIdentifier:self.identifier].URL;
  } else {
    url = _pendingURL;
  }
  return url.length ? [NSURL URLWithString:url] : nil;
}

- (void)setURL:(NSURL *)url {
  MLNAssertStyleSourceIsValid();
  if (url) {
    NSString *urlString = url.mgl_URLByStandardizingScheme.absoluteString;
    if (MLNFFIMap *map = self.mgl_map) {
      mln_map handle = map.handle;
      NSString *identifier = self.identifier;
      [map perform:@"set the URL of a GeoJSON source"
            submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
              return mln_map_set_geo_json_source_url(handle, MLNFFIBufferView(identifier),
                                                     MLNFFIBufferView(urlString), completion,
                                                     diagnostic);
            }];
    } else {
      _pendingURL = urlString;
    }
    _shape = nil;
  } else {
    self.shape = nil;
  }
}

- (void)setShape:(MLNShape *)shape {
  MLNAssertStyleSourceIsValid();
  if (MLNFFIMap *map = self.mgl_map) {
    mln_geo_json_source_data data = [self mgl_preparedDataForShape:shape];
    if (data != MLN_HANDLE_NULL) {
      mln_map handle = map.handle;
      NSString *identifier = self.identifier;
      [map perform:@"set the shape of a GeoJSON source"
            submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
              return mln_map_set_geo_json_source_data(handle, MLNFFIBufferView(identifier), data,
                                                      completion, diagnostic);
            }];
      mln_geo_json_source_data_release(data);
    }
  } else {
    _pendingURL = nil;
  }
  _shape = shape;
}

- (NSString *)description {
  if (self.mgl_isValid) {
    return [NSString stringWithFormat:@"<%@: %p; identifier = %@; URL = %@; shape = %@>",
                                      NSStringFromClass([self class]), (void *)self,
                                      self.identifier, self.URL, self.shape];
  } else {
    return [NSString stringWithFormat:@"<%@: %p; identifier = %@; URL = <unknown>; shape = %@>",
                                      NSStringFromClass([self class]), (void *)self,
                                      self.identifier, self.shape];
  }
}

- (NSArray<id<MLNFeature>> *)featuresMatchingPredicate:(nullable NSPredicate *)predicate {
  MLNAssertStyleSourceIsValid();
  if (![self.stylable isKindOfClass:[MLNMapView class]]) {
    return @[];
  }
  return MLNFFIQuerySourceFeatures(self, nil, predicate);
}

// MARK: - Managing Feature State

- (BOOL)setFeatureStateForFeatureID:(NSString *)featureID
                              state:(NSDictionary<NSString *, id> *)state {
  return [self mgl_setFeatureStateForSourceLayerID:nil featureID:featureID state:state];
}

- (nullable NSDictionary<NSString *, id> *)featureStateForFeatureID:(NSString *)featureID {
  return [self mgl_featureStateForSourceLayerID:nil featureID:featureID];
}

- (BOOL)removeFeatureStateForFeatureID:(nullable NSString *)featureID
                              stateKey:(nullable NSString *)stateKey {
  return [self mgl_removeFeatureStateForSourceLayerID:nil featureID:featureID stateKey:stateKey];
}

- (BOOL)removeFeatureStateForFeatureID:(NSString *)featureID {
  return [self mgl_removeFeatureStateForSourceLayerID:nil featureID:featureID stateKey:nil];
}

- (BOOL)resetFeatureStates {
  return [self mgl_removeFeatureStateForSourceLayerID:nil featureID:nil stateKey:nil];
}

// MARK: - MLNCluster management

/// The result of a supercluster query for the cluster, as
/// Renderer::queryFeatureExtensions returned it, or nil.
- (id)featureExtensionValueOfCluster:(MLNShape<MLNCluster> *)cluster
                           extension:(NSString *)extension
                             options:(NSDictionary *)options {
  MLNAssertStyleSourceIsValid();

  // Check parameters
  if (!self.mgl_map || !self.stylable || !cluster) {
    return nil;
  }

  NSDictionary *geoJSON = MLNGeoJSONObjectFromShape(cluster);

  if (![geoJSON[@"type"] isEqual:@"Feature"]) {
    MLNAssert(0, @"cluster geoJSON object is not a feature.");
    return nil;
  }

  if (![self.stylable isKindOfClass:[MLNMapView class]]) {
    return nil;
  }
  return MLNFFIQueryFeatureExtension(self, geoJSON, @"supercluster", extension, options);
}

/// The features of a feature extension result, which is a feature collection.
static NSArray<id<MLNFeature>> *MLNFeaturesFromFeatureExtensionValue(id value) {
  NSArray *features;
  if ([value isKindOfClass:[NSDictionary class]] && [value[@"features"] isKindOfClass:[NSArray class]]) {
    features = value[@"features"];
  } else if ([value isKindOfClass:[NSArray class]]) {
    features = value;
  } else {
    return @[];
  }
  NSMutableArray *dictionaries = [NSMutableArray arrayWithCapacity:features.count];
  for (id feature in features) {
    if ([feature isKindOfClass:[NSDictionary class]]) {
      [dictionaries addObject:feature];
    }
  }
  return MLNFeaturesFromGeoJSONFeatures(dictionaries);
}

- (NSArray<id<MLNFeature>> *)leavesOfCluster:(MLNPointFeatureCluster *)cluster
                                      offset:(NSUInteger)offset
                                       limit:(NSUInteger)limit {
  NSDictionary *options = @{@"limit" : @(limit), @"offset" : @(offset)};

  id featureExtension = [self featureExtensionValueOfCluster:cluster
                                                   extension:@"leaves"
                                                     options:options];

  if (!featureExtension) {
    return @[];
  }

  return MLNFeaturesFromFeatureExtensionValue(featureExtension);
}

- (NSArray<id<MLNFeature>> *)childrenOfCluster:(MLNPointFeatureCluster *)cluster {
  id featureExtension = [self featureExtensionValueOfCluster:cluster
                                                   extension:@"children"
                                                     options:@{}];

  if (!featureExtension) {
    return @[];
  }

  return MLNFeaturesFromFeatureExtensionValue(featureExtension);
}

- (double)zoomLevelForExpandingCluster:(MLNPointFeatureCluster *)cluster {
  id featureExtension = [self featureExtensionValueOfCluster:cluster
                                                   extension:@"expansion-zoom"
                                                     options:@{}];

  if (![featureExtension isKindOfClass:[NSNumber class]]) {
    return -1.0;
  }

  return [featureExtension doubleValue];
}

- (void)debugRecursiveLogForFeature:(id<MLNFeature>)feature indent:(NSUInteger)indent {
  NSString *description = feature.description;

  // Want our recursive log on a single line
  NSString *log =
      [description stringByReplacingOccurrencesOfString:@"\\s+"
                                             withString:@" "
                                                options:NSRegularExpressionSearch
                                                  range:NSMakeRange(0, description.length)];

  printf("%*s%s\n", (int)indent, "", log.UTF8String);

  MLNPointFeatureCluster *cluster =
      [(id)feature isKindOfClass:[MLNPointFeatureCluster class]] ? (MLNPointFeatureCluster *)feature
                                                                 : nil;

  if (cluster) {
    for (id<MLNFeature> child in [self childrenOfCluster:cluster]) {
      [self debugRecursiveLogForFeature:child indent:indent + 4];
    }
  }
}

@end
