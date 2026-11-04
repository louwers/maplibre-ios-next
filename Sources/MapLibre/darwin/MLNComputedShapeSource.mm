// Based on platform/darwin/src/MLNComputedShapeSource.mm at ios-v7.0.0

#import "MLNComputedShapeSource_Private.h"

#import "MLNFFI.h"
#import "MLNGeoJSON.h"
#import "MLNGeometry_Private.h"
#import "MLNLoggingConfiguration_Private.h"
#import "MLNShapeCollection.h"
#import "MLNSource_Private.h"

#include <atomic>
#include <cmath>

const MLNExceptionName MLNInvalidDatasourceException = @"MLNInvalidDatasourceException";

const MLNShapeSourceOption MLNShapeSourceOptionWrapsCoordinates =
    @"MLNShapeSourceOptionWrapsCoordinates";
const MLNShapeSourceOption MLNShapeSourceOptionClipsCoordinates =
    @"MLNShapeSourceOptionClipsCoordinates";

mln_custom_geometry_source_options MLNCustomGeometrySourceOptionsFromDictionary(
    NSDictionary<MLNShapeSourceOption, id> *options) {
  mln_custom_geometry_source_options sourceOptions = {sizeof(mln_custom_geometry_source_options)};

  if (NSNumber *value = options[MLNShapeSourceOptionMinimumZoomLevel]) {
    if (![value isKindOfClass:[NSNumber class]]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"MLNShapeSourceOptionMinimumZoomLevel must be an NSNumber."];
    }
    sourceOptions.fields |= MLN_CUSTOM_GEOMETRY_SOURCE_OPTION_MIN_ZOOM;
    sourceOptions.min_zoom = (uint8_t)value.integerValue;
  }

  if (NSNumber *value = options[MLNShapeSourceOptionMaximumZoomLevel]) {
    if (![value isKindOfClass:[NSNumber class]]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"MLNShapeSourceOptionMaximumZoomLevel must be an NSNumber."];
    }
    sourceOptions.fields |= MLN_CUSTOM_GEOMETRY_SOURCE_OPTION_MAX_ZOOM;
    sourceOptions.max_zoom = (uint8_t)value.integerValue;
  }

  if (NSNumber *value = options[MLNShapeSourceOptionBuffer]) {
    if (![value isKindOfClass:[NSNumber class]]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"MLNShapeSourceOptionBuffer must be an NSNumber."];
    }
    sourceOptions.fields |= MLN_CUSTOM_GEOMETRY_SOURCE_OPTION_BUFFER;
    sourceOptions.buffer = (uint16_t)value.integerValue;
  }

  if (NSNumber *value = options[MLNShapeSourceOptionSimplificationTolerance]) {
    if (![value isKindOfClass:[NSNumber class]]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"MLNShapeSourceOptionSimplificationTolerance must be an NSNumber."];
    }
    sourceOptions.fields |= MLN_CUSTOM_GEOMETRY_SOURCE_OPTION_TOLERANCE;
    sourceOptions.tolerance = value.doubleValue;
  }

  if (NSNumber *value = options[MLNShapeSourceOptionWrapsCoordinates]) {
    if (![value isKindOfClass:[NSNumber class]]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"MLNShapeSourceOptionWrapsCoordinates must be an NSNumber."];
    }
    sourceOptions.fields |= MLN_CUSTOM_GEOMETRY_SOURCE_OPTION_WRAP;
    sourceOptions.wrap = value.boolValue;
  }

  if (NSNumber *value = options[MLNShapeSourceOptionClipsCoordinates]) {
    if (![value isKindOfClass:[NSNumber class]]) {
      [NSException raise:NSInvalidArgumentException
                  format:@"MLNShapeSourceOptionClipsCoordinates must be an NSNumber."];
    }
    sourceOptions.fields |= MLN_CUSTOM_GEOMETRY_SOURCE_OPTION_CLIP;
    sourceOptions.clip = value.boolValue;
  }

  return sourceOptions;
}

/// The GeoJSON text of a feature collection with the given features, as the
/// mln::FeatureCollection classic passed to setTileData.
static NSString *MLNFeatureCollectionJSON(NSArray<MLNShape<MLNFeature> *> *features) {
  NSMutableArray *geoJSONFeatures = [NSMutableArray arrayWithCapacity:features.count];
  for (MLNShape<MLNFeature> *feature in features) {
    if ([feature isMemberOfClass:[MLNShapeCollection class]]) {
      static dispatch_once_t onceToken;
      dispatch_once(&onceToken, ^{
        NSLog(@"MLNShapeCollection initialized with MLNFeatures will not retain attributes."
              @"Use MLNShapeCollectionFeature to retain attributes instead."
              @"This will be logged only once.");
      });
    }
    [geoJSONFeatures addObject:MLNGeoJSONObjectFromShape(feature)];
  }
  return MLNFFIJSONStringFromObject(@{@"type" : @"FeatureCollection", @"features" : geoJSONFeatures});
}

/// mln::LatLngBounds(const CanonicalTileID &)
static MLNCoordinateBounds MLNCoordinateBoundsForTile(uint8_t z, uint32_t x, uint32_t y) {
  auto latitude = [](double z2, uint32_t row) {
    const double n = M_PI - 2.0 * M_PI * row / z2;
    return 180.0 / M_PI * std::atan(0.5 * (std::exp(n) - std::exp(-n)));
  };
  auto longitude = [](double z2, uint32_t column) { return column / z2 * 360.0 - 180.0; };
  const double z2 = std::pow(2.0, z);
  CLLocationCoordinate2D sw = CLLocationCoordinate2DMake(latitude(z2, y + 1), longitude(z2, x));
  CLLocationCoordinate2D ne = CLLocationCoordinate2DMake(latitude(z2, y), longitude(z2, x + 1));
  return MLNCoordinateBoundsMake(sw, ne);
}

@class MLNComputedShapeSource;

/// The state the C API's fetch and cancel callbacks use, which run on native
/// worker threads. Classic captured the source in the core's fetch functions.
@interface MLNComputedShapeSourceCallbacks : NSObject {
 @public
  std::atomic<uint64_t> map;
}
@property (nonatomic, weak) MLNComputedShapeSource *source;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic) NSOperationQueue *requestQueue;
@end

@implementation MLNComputedShapeSourceCallbacks
@end

@interface MLNComputedShapeSource () {
  mln_custom_geometry_source_options _sourceOptions;
  MLNComputedShapeSourceCallbacks *_callbacks;
}

@property (nonatomic, readwrite) NSDictionary *options;
@property (nonatomic, assign) BOOL dataSourceImplementsFeaturesForTile;
@property (nonatomic, assign) BOOL dataSourceImplementsFeaturesForBounds;

@end

@interface MLNComputedShapeSourceFetchOperation : NSOperation

@property (nonatomic, readonly) uint8_t z;
@property (nonatomic, readonly) uint32_t x;
@property (nonatomic, readonly) uint32_t y;
@property (nonatomic, assign) BOOL dataSourceImplementsFeaturesForTile;
@property (nonatomic, assign) BOOL dataSourceImplementsFeaturesForBounds;
@property (nonatomic, weak, nullable) id<MLNComputedShapeSourceDataSource> dataSource;
@property (nonatomic, copy) NSString *sourceIdentifier;
/// The map to send the tile to; cleared when the operation is cancelled.
@property (atomic) uint64_t map;

- (instancetype)initForSource:(MLNComputedShapeSource *)source
                         tile:(mln_canonical_tile_id)tileID
                          map:(mln_map)map;

@end

@implementation MLNComputedShapeSourceFetchOperation

- (instancetype)initForSource:(MLNComputedShapeSource *)source
                         tile:(mln_canonical_tile_id)tileID
                          map:(mln_map)map {
  self = [super init];
  _z = (uint8_t)tileID.z;
  _x = tileID.x;
  _y = tileID.y;
  _dataSourceImplementsFeaturesForTile = source.dataSourceImplementsFeaturesForTile;
  _dataSourceImplementsFeaturesForBounds = source.dataSourceImplementsFeaturesForBounds;
  _dataSource = source.dataSource;
  _sourceIdentifier = [source.identifier copy];
  _map = map;
  return self;
}

- (void)main {
  if ([self isCancelled]) {
    return;
  }

  NSArray<MLNShape<MLNFeature> *> *data;
  if (!self.dataSource) {
    data = nil;
  } else if (self.dataSourceImplementsFeaturesForTile) {
    data = [self.dataSource featuresInTileAtX:self.x y:self.y zoomLevel:self.z];
  } else {
    data = [self.dataSource featuresInCoordinateBounds:MLNCoordinateBoundsForTile(self.z, self.x,
                                                                                 self.y)
                                             zoomLevel:self.z];
  }

  if (![self isCancelled]) {
    NSString *geojson = MLNFeatureCollectionJSON(data);

    // Note: potential race condition with `cancel`
    if (![self isCancelled]) {
      if (mln_map map = self.map) {
        // A command from a worker thread: submit it without waiting.
        mln_diagnostic diagnostic = {sizeof(mln_diagnostic)};
        mln_map_set_custom_geometry_source_tile_data(
            map, MLNFFIBufferView(self.sourceIdentifier), {self.z, self.x, self.y},
            MLNFFIBufferView(geojson), NULL, &diagnostic);
      }
    }
  }
}

- (void)cancel {
  [super cancel];
  self.map = MLN_HANDLE_NULL;
}

@end

static void MLNComputedShapeSourceFetchTile(void *userData, mln_canonical_tile_id tileID) {
  MLNComputedShapeSourceCallbacks *callbacks = (__bridge MLNComputedShapeSourceCallbacks *)userData;
  MLNComputedShapeSource *source = callbacks.source;
  if (!source) {
    return;
  }
  NSOperation *operation =
      [[MLNComputedShapeSourceFetchOperation alloc] initForSource:source
                                                             tile:tileID
                                                              map:callbacks->map.load()];
  [callbacks.requestQueue addOperation:operation];
}

static void MLNComputedShapeSourceCancelTile(void *userData, mln_canonical_tile_id tileID) {
  MLNComputedShapeSourceCallbacks *callbacks = (__bridge MLNComputedShapeSourceCallbacks *)userData;
  for (MLNComputedShapeSourceFetchOperation *operation in callbacks.requestQueue.operations) {
    if (operation.x == tileID.x && operation.y == tileID.y && operation.z == tileID.z) {
      [operation cancel];
    }
  }
}

static void MLNComputedShapeSourceReleaseCallbacks(void *userData) { CFBridgingRelease(userData); }

@implementation MLNComputedShapeSource

- (instancetype)initWithIdentifier:(NSString *)identifier
                           options:(NSDictionary<MLNShapeSourceOption, id> *)options {
  NSOperationQueue *requestQueue = [[NSOperationQueue alloc] init];
  requestQueue.name = [NSString stringWithFormat:@"mgl.MLNComputedShapeSource.%@", identifier];
  requestQueue.qualityOfService = NSQualityOfServiceUtility;
  requestQueue.maxConcurrentOperationCount = 4;

  mln_custom_geometry_source_options sourceOptions =
      MLNCustomGeometrySourceOptionsFromDictionary(options);

  if (self = [super initWithPendingIdentifier:identifier]) {
    _requestQueue = requestQueue;
    _sourceOptions = sourceOptions;
  }
  return self;
}

- (mln_status)mgl_addToMap:(MLNFFIMap *)map message:(NSString **)message {
  MLNComputedShapeSourceCallbacks *callbacks = [[MLNComputedShapeSourceCallbacks alloc] init];
  callbacks.source = self;
  callbacks.identifier = self.identifier;
  callbacks.requestQueue = self.requestQueue;
  callbacks->map = map.handle;

  mln_custom_geometry_source_options options = _sourceOptions;
  options.fetch_tile = MLNComputedShapeSourceFetchTile;
  options.cancel_tile = MLNComputedShapeSourceCancelTile;
  options.user_data = (void *)CFBridgingRetain(callbacks);
  options.release_user_data = MLNComputedShapeSourceReleaseCallbacks;

  mln_map handle = map.handle;
  NSString *identifier = self.identifier;
  __block BOOL accepted = NO;
  mln_status status = [map call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    mln_status submitted = mln_map_add_custom_geometry_source(
        handle, MLNFFIBufferView(identifier), &options, completion, diagnostic);
    accepted = submitted == MLN_STATUS_OK;
    return submitted;
  }
                        consume:nil
                        message:message];
  if (!accepted) {
    // A refused submission leaves user_data with the caller.
    CFBridgingRelease(options.user_data);
  }
  if (status == MLN_STATUS_OK) {
    _callbacks = callbacks;
  }
  return status;
}

- (void)mgl_didAttachToMap:(MLNFFIMap *)map {
  if (!map && _callbacks) {
    // Detached: tiles fetched for the old map go nowhere.
    _callbacks->map = MLN_HANDLE_NULL;
    _callbacks.source = nil;
    _callbacks = nil;
    [self.requestQueue cancelAllOperations];
  }
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                        dataSource:(id<MLNComputedShapeSourceDataSource>)dataSource
                           options:(NSDictionary<MLNShapeSourceOption, id> *)options {
  if (self = [self initWithIdentifier:identifier options:options]) {
    [self setDataSource:dataSource];
  }
  return self;
}

- (void)dealloc {
  [self.requestQueue cancelAllOperations];
}

- (void)setFeatures:(NSArray<MLNShape<MLNFeature> *> *)features
          inTileAtX:(NSUInteger)x
                  y:(NSUInteger)y
          zoomLevel:(NSUInteger)zoomLevel {
  MLNAssertStyleSourceIsValid();
  MLNFFIMap *map = self.mgl_map;
  if (!map) {
    // Classic stored the data in the pending core source, where nothing used it.
    return;
  }
  mln_canonical_tile_id tileID = {(uint8_t)zoomLevel, (uint32_t)x, (uint32_t)y};
  NSString *geojson = MLNFeatureCollectionJSON(features);
  mln_map handle = map.handle;
  NSString *identifier = self.identifier;
  [map perform:@"set the features of a computed shape source tile"
        submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
          return mln_map_set_custom_geometry_source_tile_data(
              handle, MLNFFIBufferView(identifier), tileID, MLNFFIBufferView(geojson), completion,
              diagnostic);
        }];
}

- (void)setDataSource:(id<MLNComputedShapeSourceDataSource>)dataSource {
  [self.requestQueue cancelAllOperations];
  // Check which method the datasource implements, to avoid having to check for each tile
  self.dataSourceImplementsFeaturesForTile =
      [dataSource respondsToSelector:@selector(featuresInTileAtX:y:zoomLevel:)];
  self.dataSourceImplementsFeaturesForBounds =
      [dataSource respondsToSelector:@selector(featuresInCoordinateBounds:zoomLevel:)];

  if (!self.dataSourceImplementsFeaturesForBounds && !self.dataSourceImplementsFeaturesForTile) {
    [NSException
         raise:MLNInvalidDatasourceException
        format:@"Datasource does not implement any MLNComputedShapeSourceDataSource methods"];
  } else if (self.dataSourceImplementsFeaturesForBounds &&
             self.dataSourceImplementsFeaturesForTile) {
    [NSException raise:MLNInvalidDatasourceException
                format:@"Datasource implements multiple MLNComputedShapeSourceDataSource methods"];
  }

  _dataSource = dataSource;
}

- (void)invalidateBounds:(MLNCoordinateBounds)bounds {
  MLNAssertStyleSourceIsValid();
  MLNFFIMap *map = self.mgl_map;
  if (!map) {
    return;
  }
  mln_lat_lng_bounds latLngBounds = MLNLatLngBoundsFromCoordinateBounds(bounds);
  mln_map handle = map.handle;
  NSString *identifier = self.identifier;
  [map perform:@"invalidate a computed shape source region"
        submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
          return mln_map_invalidate_custom_geometry_source_region(
              handle, MLNFFIBufferView(identifier), latLngBounds, completion, diagnostic);
        }];
}

- (void)invalidateTileAtX:(NSUInteger)x y:(NSUInteger)y zoomLevel:(NSUInteger)z {
  MLNAssertStyleSourceIsValid();
  MLNFFIMap *map = self.mgl_map;
  if (!map) {
    return;
  }
  mln_canonical_tile_id tileID = {(uint32_t)z, (uint32_t)x, (uint32_t)y};
  mln_map handle = map.handle;
  NSString *identifier = self.identifier;
  [map perform:@"invalidate a computed shape source tile"
        submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
          return mln_map_invalidate_custom_geometry_source_tile(handle, MLNFFIBufferView(identifier),
                                                                tileID, completion, diagnostic);
        }];
}

@end
