// Based on platform/darwin/src/MLNMapSnapshotter.mm at ios-v7.0.0

#import "MLNMapSnapshotter.h"

#import <MaplibreNativeC/maplibre_native_c.h>

#import "MLNFFI.h"
#import "MLNFFIMap+Style.h"
#import "MLNGeoJSON.h"

#import "MLNAnnotationImage_Private.h"
#import "MLNAttributionInfo_Private.h"
#import "MLNGeometry_Private.h"
#import "MLNLoggingConfiguration_Private.h"
#import "MLNMapSnapshotter_Private.h"
#import "MLNMultiPoint_Private.h"
#import "MLNOfflineStorage_Private.h"
#import "MLNPointCollection.h"
#import "MLNPolygon.h"
#import "MLNPolyline.h"
#import "MLNRendererConfiguration.h"
#import "MLNSettings_Private.h"
#import "MLNShape.h"
#import "MLNShapeCollection.h"
#import "MLNStyle_Private.h"

#if TARGET_OS_IPHONE
#import "UIColor+MLNAdditions.h"
#import "UIImage+MLNAdditions.h"
#else
#import <CoreGraphics/CoreGraphics.h>
#import <CoreImage/CIContext.h>
#import <CoreImage/CIFilter.h>
#import <QuartzCore/QuartzCore.h>
#import "NSColor+MLNAdditions.h"
#import "NSImage+MLNAdditions.h"
#endif

#import "NSBundle+MLNAdditions.h"

#include <vector>

const CGPoint MLNLogoImagePosition = CGPointMake(8, 8);
const CGFloat MLNSnapshotterMinimumPixelSize = 64;
NSString *const MLNSnapshotterAnnotationSpritePrefix = @"org.maplibre.sprites.";

/// Layers, sources and images the snapshotter adds for annotations. The prefix
/// hides them from MLNStyle, as classic's annotation manager kept its own.
static NSString *const MLNSnapshotterAnnotationPrefix = @"org.maplibre.next.snapshot.annotations.";

/**
 The transform of a rendered snapshot, as classic's PointForFn and LatLngForFn
 captured the core's transform state: a C API projection of the view the still
 image was rendered with.
 */
@interface MLNSnapshotProjection : NSObject
- (instancetype)initWithView:(const mln_map_view &)view;
- (CGPoint)pointForCoordinate:(CLLocationCoordinate2D)coordinate;
- (CLLocationCoordinate2D)coordinateForPoint:(CGPoint)point;
@end

@implementation MLNSnapshotProjection {
  mln_map_projection _projection;
}

- (instancetype)initWithView:(const mln_map_view &)view {
  if (self = [super init]) {
    mln_diagnostic diagnostic = {sizeof(mln_diagnostic)};
    if (mln_map_projection_create(&view, &_projection, &diagnostic) != MLN_STATUS_OK) {
      MLNLogError(@"Failed to create the snapshot projection: %s", diagnostic.message);
    }
  }
  return self;
}

- (void)dealloc {
  mln_map_projection_release(_projection);
}

// The C API converts in the world copy nearest the camera center, as classic
// wrapped the coordinate and unwrapped it for the shortest path to the center.
- (CGPoint)pointForCoordinate:(CLLocationCoordinate2D)coordinate {
  mln_screen_point point = {0, 0};
  mln_diagnostic diagnostic = {sizeof(mln_diagnostic)};
  mln_map_projection_pixel_for_lat_lng(_projection, MLNLatLngFromLocationCoordinate2D(coordinate),
                                       &point, &diagnostic);
  return CGPointMake(point.x, point.y);
}

// Transform::screenCoordinateToLatLng wraps the longitude by default.
- (CLLocationCoordinate2D)coordinateForPoint:(CGPoint)point {
  mln_lat_lng latLng = {0, 0};
  mln_diagnostic diagnostic = {sizeof(mln_diagnostic)};
  mln_map_projection_lat_lng_for_pixel(_projection, {point.x, point.y}, &latLng, &diagnostic);
  return MLNLocationCoordinate2DFromLatLng(latLng);
}

@end

MLNImage *MLNAttributedSnapshot(NSArray<NSString *> *attributions, MLNImage *mglImage,
                                MLNMapSnapshotOptions *options, void (^overlayHandler)());
MLNMapSnapshot *MLNSnapshotWithDecoratedImage(MLNImage *mglImage, MLNMapSnapshotOptions *options,
                                              NSArray<NSString *> *attributions,
                                              MLNSnapshotProjection *projection,
                                              MLNMapSnapshotOverlayHandler overlayHandler,
                                              NSError *_Nullable *outError);
NSArray<MLNAttributionInfo *> *MLNAttributionInfosFromAttributions(
    NSArray<NSString *> *attributions);


@interface MLNMapSnapshotOverlay () <MLNMapSnapshotProtocol>
@property (nonatomic, assign) CGFloat scale;
- (instancetype)initWithContext:(CGContextRef)context
                          scale:(CGFloat)scale
                     projection:(MLNSnapshotProjection *)projection;

@end

@implementation MLNMapSnapshotOverlay {
  MLNSnapshotProjection *_projection;
}

- (instancetype)initWithContext:(CGContextRef)context
                          scale:(CGFloat)scale
                     projection:(MLNSnapshotProjection *)projection {
  self = [super init];
  if (self) {
    _context = context;
    _scale = scale;
    _projection = projection;
  }

  return self;
}

#if TARGET_OS_IPHONE

- (CGPoint)pointForCoordinate:(CLLocationCoordinate2D)coordinate {
  return [_projection pointForCoordinate:coordinate];
}

- (CLLocationCoordinate2D)coordinateForPoint:(CGPoint)point {
  return [_projection coordinateForPoint:point];
}

#else

- (NSPoint)pointForCoordinate:(CLLocationCoordinate2D)coordinate {
  CGPoint sc = [_projection pointForCoordinate:coordinate];
  CGFloat height = ((CGFloat)CGBitmapContextGetHeight(self.context)) / self.scale;
  return NSMakePoint(sc.x, height - sc.y);
}

- (CLLocationCoordinate2D)coordinateForPoint:(NSPoint)point {
  CGFloat height = ((CGFloat)CGBitmapContextGetHeight(self.context)) / self.scale;
  return [_projection coordinateForPoint:CGPointMake(point.x, height - point.y)];
}

#endif
@end

@implementation MLNMapSnapshotOptions

- (instancetype _Nonnull)initWithStyleURL:(nullable NSURL *)styleURL
                                   camera:(MLNMapCamera *)camera
                                     size:(CGSize)size {
  MLNLogDebug(@"Initializing withStyleURL: %@ camera: %@ size: %@", styleURL, camera,
              MLNStringFromSize(size));
  self = [super init];
  if (self) {
    if (!styleURL) {
      styleURL = [MLNStyle defaultStyleURL];
    }
    _styleURL = styleURL;
    _size = size;
    _camera = camera;
    _showsLogo = YES;
    _showsAttribution = YES;
#if TARGET_OS_IPHONE
    _scale = [UIScreen mainScreen].scale;
#else
    _scale = [NSScreen mainScreen].backingScaleFactor;
#endif
  }
  return self;
}

- (nonnull id)copyWithZone:(nullable NSZone *)zone {
  __typeof__(self) copy = [[[self class] alloc] initWithStyleURL:_styleURL
                                                          camera:_camera
                                                            size:_size];
  copy.zoomLevel = _zoomLevel;
  copy.coordinateBounds = _coordinateBounds;
  copy.scale = _scale;
  copy.showsLogo = _showsLogo;
  copy.showsAttribution = _showsAttribution;
  return copy;
}

@end

@interface MLNMapSnapshot () <MLNMapSnapshotProtocol>
- (instancetype)initWithImage:(nullable MLNImage *)image
                        scale:(CGFloat)scale
                   projection:(MLNSnapshotProjection *)projection;

@property (nonatomic) CGFloat scale;
@end

@implementation MLNMapSnapshot {
  MLNSnapshotProjection *_projection;
}

- (instancetype)initWithImage:(nullable MLNImage *)image
                        scale:(CGFloat)scale
                   projection:(MLNSnapshotProjection *)projection {
  self = [super init];
  if (self) {
    _projection = projection;
    _scale = scale;
    _image = image;
  }
  return self;
}

#if TARGET_OS_IPHONE

- (CGPoint)pointForCoordinate:(CLLocationCoordinate2D)coordinate {
  return [_projection pointForCoordinate:coordinate];
}

- (CLLocationCoordinate2D)coordinateForPoint:(CGPoint)point {
  return [_projection coordinateForPoint:point];
}

#else

- (NSPoint)pointForCoordinate:(CLLocationCoordinate2D)coordinate {
  CGPoint sc = [_projection pointForCoordinate:coordinate];
  return NSMakePoint(sc.x, self.image.size.height - sc.y);
}

- (CLLocationCoordinate2D)coordinateForPoint:(NSPoint)point {
  return [_projection coordinateForPoint:CGPointMake(point.x, self.image.size.height - point.y)];
}

#endif

@end

@interface MLNMapSnapshotter () <MLNMultiPointDelegate, MLNFFIMapEventObserver, MLNFFIStylable>
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL terminated;
@end

/// Where the snapshot map's style is in loading.
typedef NS_ENUM(NSUInteger, MLNSnapshotStyleState) {
  MLNSnapshotStyleStateLoading,
  MLNSnapshotStyleStateLoaded,
  MLNSnapshotStyleStateFailed,
};

/// One offscreen device for all snapshotters, which the C API allows to share.
static mln_offscreen_device MLNSnapshotterOffscreenDevice(void) {
  static mln_offscreen_device device = MLN_HANDLE_NULL;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    mln_diagnostic diagnostic = {sizeof(mln_diagnostic)};
    if (mln_offscreen_device_create(NULL, &device, &diagnostic) != MLN_STATUS_OK) {
      MLNLogError(@"Failed to create an offscreen device for snapshots: %s", diagnostic.message);
    }
  });
  return device;
}

// Classic wrapped mbgl::MapSnapshotter, a static map with a headless renderer.
// Here each start creates a static C API map with an offscreen session on a
// shared device, as mbgl::MapSnapshotter was created anew for each start, and
// renders it with mln_map_request_still_image().
@implementation MLNMapSnapshotter {
  MLNFFIMap *_map;
  mln_render_session _session;
  MLNStyle *_style;
  MLNSnapshotStyleState _styleState;
  NSString *_styleError;
  /// Runs once the style loads or fails, for a start that waits for it.
  void (^_styleCompletion)(NSString *_Nullable error);
  /// Changes on each start and cancel, so late callbacks of an earlier start
  /// are dropped, as mbgl::MapSnapshotter::cancel() dropped its callback.
  uint64_t _startGeneration;
  NSMutableArray<id<MLNAnnotation>> *_annotationsToInstall;
  NSMutableSet<NSString *> *_installedImages;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self cancel];
}

- (instancetype)init {
  NSAssert(NO, @"Please use -[MLNMapSnapshotter initWithOptions:]");
  [super doesNotRecognizeSelector:_cmd];
  return nil;
}

- (instancetype)initWithOptions:(MLNMapSnapshotOptions *)options {
  MLNLogDebug(@"Initializing withOptions: %@", options);
  self = [super init];
  if (self) {
    self.options = options;
    _installedImages = [NSMutableSet set];
#if TARGET_OS_IPHONE
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillTerminate:)
                                                 name:UIApplicationWillTerminateNotification
                                               object:nil];
#else
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillTerminate:)
                                                 name:NSApplicationWillTerminateNotification
                                               object:nil];
#endif
  }
  return self;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
  [self cancel];
  self.terminated = YES;
}

- (void)addAnnotation:(id<MLNAnnotation>)annotation {
  MLNLogDebug(@"Adding annotation: %@", annotation);
  if (!annotation) return;
  return [self addAnnotations:@[ annotation ]];
}

- (void)addAnnotations:(NSArray<id<MLNAnnotation>> *)annotations {
  MLNLogDebug(@"Adding: %lu annotations", annotations.count);

  if (!_annotationsToInstall) {
    _annotationsToInstall = [NSMutableArray array];
  }

  [_annotationsToInstall addObjectsFromArray:annotations];
}

// Classic added annotations to the core's annotation manager, which the C API
// lacks (C_API_GAPS.md). They are drawn with style layers configured as the
// annotation manager configured its own: a line or fill layer per shape, in
// order, and one symbol layer for the points above them.
- (void)installAnnotations:(NSArray<id<MLNAnnotation>> *)annotations {
  MLNLogDebug(@"install: %lu annotations", annotations.count);
  if (!annotations) return;

  NSMutableArray<NSDictionary *> *points = [NSMutableArray array];
  NSUInteger shapeIndex = 0;
  for (id<MLNAnnotation> annotation in annotations) {
    MLNAssert([annotation conformsToProtocol:@protocol(MLNAnnotation)],
              @"annotation should conform to MLNAnnotation");

    if ([annotation isKindOfClass:[MLNMultiPoint class]]) {
      MLNMultiPoint *multiPoint = (MLNMultiPoint *)annotation;
      if (!multiPoint.pointCount) {
        continue;
      }
      [self installShapeAnnotation:multiPoint index:shapeIndex++];
    } else if (![annotation isKindOfClass:[MLNMultiPolyline class]] &&
               ![annotation isKindOfClass:[MLNMultiPolygon class]] &&
               ![annotation isKindOfClass:[MLNShapeCollection class]] &&
               ![annotation isKindOfClass:[MLNPointCollection class]]) {
      NSString *symbolName;
      MLNAnnotationImage *annotationImage;

      if ([self.delegate respondsToSelector:@selector(mapSnapshotter:imageForAnnotation:)]) {
        annotationImage = [self.delegate mapSnapshotter:self imageForAnnotation:annotation];
      }
      if (!annotationImage) {
        // doesn't support no icon point for snapshotter
        continue;
      }

      symbolName = annotationImage.styleIconIdentifier;
      if (!symbolName) {
        symbolName = [MLNSnapshotterAnnotationSpritePrefix
            stringByAppendingString:annotationImage.reuseIdentifier];
        annotationImage.styleIconIdentifier = symbolName;
      }

      [self installAnnotationImage:annotationImage];

      CLLocationCoordinate2D coordinate = annotation.coordinate;
      MLNLatLngFromLocationCoordinate2D(coordinate);
      [points addObject:@{
        @"type" : @"Feature",
        @"geometry" : @{
          @"type" : @"Point",
          @"coordinates" : @[ @(coordinate.longitude), @(coordinate.latitude) ]
        },
        @"properties" : @{
          @"sprite" : [MLNSnapshotterAnnotationPrefix stringByAppendingString:symbolName]
        }
      }];
    }
  }
  if (points.count) {
    NSString *identifier = [MLNSnapshotterAnnotationPrefix stringByAppendingString:@"points"];
    [_map addStyleSourceJSON:@{
      @"type" : @"geojson",
      @"data" : @{@"type" : @"FeatureCollection", @"features" : points}
    }
                  identifier:identifier
                     message:nil];
    [_map addStyleLayerJSON:@{
      @"id" : identifier,
      @"type" : @"symbol",
      @"source" : identifier,
      @"layout" : @{
        @"icon-image" : @[ @"image", @[ @"to-string", @[ @"get", @"sprite" ] ] ],
        @"icon-allow-overlap" : @YES,
        @"icon-ignore-placement" : @YES,
      }
    }
                 belowLayer:nil
                    message:nil];
  }
}

/// The GeoJSON geometry of a shape annotation.
static NSDictionary *MLNSnapshotterGeometry(MLNShape *shape) {
  NSDictionary *object = MLNGeoJSONObjectFromShape(shape);
  if ([object[@"type"] isEqual:@"Feature"]) {
    return object[@"geometry"];
  }
  return object;
}

- (void)installShapeAnnotation:(MLNMultiPoint *)multiPoint index:(NSUInteger)index {
  NSString *identifier = [MLNSnapshotterAnnotationPrefix
      stringByAppendingFormat:@"shape.%lu", (unsigned long)index];
  NSDictionary *layer;
  double opacity = [self alphaForShapeAnnotation:multiPoint];
  if ([multiPoint isKindOfClass:[MLNPolygon class]]) {
    MLNPolygon *polygon = (MLNPolygon *)multiPoint;
    layer = @{
      @"id" : identifier,
      @"type" : @"fill",
      @"source" : identifier,
      @"paint" : @{
        @"fill-opacity" : @(opacity),
        @"fill-color" : MLNSnapshotterColorJSON([self fillColorForPolygonAnnotation:polygon]),
        @"fill-outline-color" :
            MLNSnapshotterColorJSON([self strokeColorForShapeAnnotation:polygon]),
      }
    };
  } else if ([multiPoint isKindOfClass:[MLNPolyline class]]) {
    MLNPolyline *polyline = (MLNPolyline *)multiPoint;
    layer = @{
      @"id" : identifier,
      @"type" : @"line",
      @"source" : identifier,
      @"layout" : @{@"line-join" : @"round"},
      @"paint" : @{
        @"line-opacity" : @(opacity),
        @"line-width" : @([self lineWidthForPolylineAnnotation:polyline]),
        @"line-color" : MLNSnapshotterColorJSON([self strokeColorForShapeAnnotation:polyline]),
      }
    };
  } else {
    return;
  }
  [_map addStyleSourceJSON:@{@"type" : @"geojson", @"data" : MLNSnapshotterGeometry(multiPoint)}
                identifier:identifier
                   message:nil];
  NSString *message;
  if ([_map addStyleLayerJSON:layer belowLayer:nil message:&message] != MLN_STATUS_OK) {
    MLNLogError(@"Failed to add an annotation to the snapshot: %@", message);
  }
}

/// A color as the style JSON that the core parses into the same mln::Color.
static id MLNSnapshotterColorJSON(MLNColor *color) {
  MLNColorComponents components = color.mgl_color;
  if (components.a == 0) {
    return @[ @"rgba", @0, @0, @0, @0 ];
  }
  return @[
    @"rgba", @(components.r / components.a * 255), @(components.g / components.a * 255),
    @(components.b / components.a * 255), @(components.a)
  ];
}

- (void)installAnnotationImage:(MLNAnnotationImage *)annotationImage {
  NSString *iconIdentifier = annotationImage.styleIconIdentifier;
  if (![_installedImages containsObject:iconIdentifier]) {
    [annotationImage.image
        mgl_addToMap:_map
            withName:[MLNSnapshotterAnnotationPrefix stringByAppendingString:iconIdentifier]];
  }
}

- (void)startWithCompletionHandler:(MLNMapSnapshotCompletionHandler)completion {
  MLNLogDebug(@"Starting withCompletionHandler: %@", completion);
  [self startWithQueue:dispatch_get_main_queue() completionHandler:completion];
}

- (void)startWithQueue:(dispatch_queue_t)queue
     completionHandler:(MLNMapSnapshotCompletionHandler)completionHandler {
  [self startWithQueue:queue overlayHandler:nil completionHandler:completionHandler];
}

- (void)startWithOverlayHandler:(MLNMapSnapshotOverlayHandler)overlayHandler
              completionHandler:(MLNMapSnapshotCompletionHandler)completion {
  [self startWithQueue:dispatch_get_main_queue()
         overlayHandler:overlayHandler
      completionHandler:completion];
}

- (void)startWithQueue:(dispatch_queue_t)queue
        overlayHandler:(MLNMapSnapshotOverlayHandler)overlayHandler
     completionHandler:(MLNMapSnapshotCompletionHandler)completion {
  if (!completion) {
    return;
  }

  // Ensure that offline storage has been initialized on the main thread, as MLNMapView and
  // MLNOfflineStorage do when used directly.
  // https://github.com/mapbox/mapbox-gl-native-ios/issues/227
  if ([NSThread.currentThread isMainThread]) {
    (void)[MLNOfflineStorage sharedOfflineStorage];
  } else {
    [NSException raise:NSInvalidArgumentException
                format:@"-[MLNMapSnapshotter startWithQueue:completionHandler:] must be called "
                       @"from the main thread, not %@.",
                       NSThread.currentThread];
  }

  if (self.loading) {
    // Consider replacing this exception with an error passed to the completion block.
    [NSException raise:NSInternalInconsistencyException
                format:@"Already started this snapshotter."];
  }
  self.loading = YES;

  if (self.terminated) {
    [NSException raise:NSInternalInconsistencyException
                format:@"Starting a snapshotter after application termination is not supported."];
  }

  MLNMapSnapshotOptions *options = [self.options copy];
  [self configureWithOptions:options];
  MLNLogDebug(@"Starting with options: %@", self.options);

  // Temporarily capture the snapshotter until the completion handler finishes executing, to keep
  // standalone local usage of the snapshotter from becoming a no-op. POSTCONDITION: Only refer to
  // this variable in the final result queue. POSTCONDITION: It is important to nil out this
  // variable at some point in the future to avoid a leak. In cases where the completion handler
  // gets called, the variable should be nilled out explicitly. If -cancel is called, the pending
  // callbacks see a newer start generation and release the snapshotter without calling back.
  __block MLNMapSnapshotter *strongSelf = self;
  uint64_t generation = _startGeneration;
  void (^fail)(NSString *) = ^(NSString *description) {
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey : description ?: @""};
    NSError *error = [NSError errorWithDomain:MLNErrorDomain
                                         code:MLNErrorCodeSnapshotFailed
                                     userInfo:userInfo];

    // Dispatch to result queue
    dispatch_async(queue, ^{
      strongSelf.loading = NO;
      completion(nil, error);
      strongSelf = nil;
    });
  };

  // mbgl rendered the still image once the style and everything the view
  // needed had loaded; annotations are style layers here, so they are added
  // once the style has loaded.
  [self whenStyleLoaded:^(NSString *styleError) {
    if (strongSelf->_startGeneration != generation) {
      strongSelf = nil;
      return;
    }
    if (styleError) {
      fail(styleError);
      return;
    }
    if (strongSelf->_annotationsToInstall) {
      [strongSelf installAnnotations:strongSelf->_annotationsToInstall];
    }
    [strongSelf renderStillImageWithOptions:options
                                 completion:^(MLNImage *mglImage, NSArray<NSString *> *attributions,
                                              MLNSnapshotProjection *projection,
                                              NSString *renderError) {
                                   if (strongSelf->_startGeneration != generation) {
                                     strongSelf = nil;
                                     return;
                                   }
                                   if (!mglImage) {
                                     fail(renderError);
                                     return;
                                   }
                                   // Process image watermark in a work queue
                                   dispatch_queue_t workQueue = dispatch_get_global_queue(
                                       DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

                                   dispatch_async(workQueue, ^{
                                     // Call a function that cannot accidentally capture self.
                                     NSError *error;
                                     MLNMapSnapshot *snapshot = MLNSnapshotWithDecoratedImage(
                                         mglImage, options, attributions, projection,
                                         overlayHandler, &error);

                                     // Dispatch result to result queue
                                     dispatch_async(queue, ^{
                                       strongSelf.loading = NO;
                                       completion(snapshot, error);
                                       strongSelf = nil;
                                     });
                                   });
                                 }];
  }];
}

/// Calls `block` on the main queue once the snapshot style has loaded, with
/// the load error if it failed.
- (void)whenStyleLoaded:(void (^)(NSString *_Nullable error))block {
  switch (_styleState) {
    case MLNSnapshotStyleStateLoaded:
      block(nil);
      break;
    case MLNSnapshotStyleStateFailed:
      block(_styleError ?: @"The style failed to load.");
      break;
    case MLNSnapshotStyleStateLoading:
      _styleCompletion = [block copy];
      break;
  }
}

/// Renders a still image of the snapshot map and reads it back.
- (void)renderStillImageWithOptions:(MLNMapSnapshotOptions *)options
                         completion:(void (^)(MLNImage *_Nullable image,
                                              NSArray<NSString *> *attributions,
                                              MLNSnapshotProjection *_Nullable projection,
                                              NSString *_Nullable error))completion {
  MLNFFIMap *map = _map;
  mln_map handle = map.handle;
  mln_render_session session = _session;
  [map callAsync:^(const mln_completion *callCompletion, mln_diagnostic *diagnostic) {
    return mln_map_request_still_image(handle, callCompletion, diagnostic);
  }
      consume:nil
      completion:^(mln_status status, NSString *message) {
        if (status != MLN_STATUS_OK) {
          completion(nil, @[], nil, message.length ? message : MLNFFIStatusDescription(status));
          return;
        }

        // The view the image was rendered with, from its frame result, as
        // classic captured the transform state after rendering.
        mln_map_view view = [map snapshot].view;
        mln_render_frame_batch batch = MLN_HANDLE_NULL;
        mln_render_frame_batch_view results = {sizeof(mln_render_frame_batch_view)};
        mln_diagnostic diagnostic = {sizeof(mln_diagnostic)};
        if (mln_render_session_drain_frame_results(session, &batch, &results, &diagnostic) ==
            MLN_STATUS_OK) {
          for (size_t i = 0; i < results.result_count; i++) {
            const mln_render_frame_result *result = MLN_STRIDED_AT(
                mln_render_frame_result, results.results, results.result_size, i);
            if (result->token == MLN_FRAME_DEMAND_TOKEN_STILL_IMAGE &&
                result->disposition == MLN_RENDER_RESULT_RENDERED) {
              view = result->view;
            }
          }
          mln_render_frame_batch_release(batch);
        }
        MLNSnapshotProjection *projection = [[MLNSnapshotProjection alloc] initWithView:view];

        // Collect all source attributions
        NSMutableArray<NSString *> *attributions = [NSMutableArray array];
        for (MLNFFISourceInfo *source in [map styleSources]) {
          if (source.attribution.length) {
            [attributions addObject:source.attribution];
          }
        }

        __block NSMutableData *pixels;
        __block uint32_t width = 0;
        __block uint32_t height = 0;
        [map callAsync:^(const mln_completion *callCompletion, mln_diagnostic *diagnostic) {
          return mln_render_session_read_texture(session, callCompletion, diagnostic);
        }
            consume:^(const mln_completion_result *result) {
              if (!result->value) {
                return;
              }
              const mln_texture_readback_result *readback =
                  (const mln_texture_readback_result *)result->value;
              width = readback->info.width;
              height = readback->info.height;
              // Tightly packed premultiplied RGBA8, as mln::PremultipliedImage.
              pixels = [NSMutableData dataWithLength:(NSUInteger)width * height * 4];
              const uint8_t *source = (const uint8_t *)readback->data.data;
              for (uint32_t row = 0; row < height; row++) {
                memcpy((uint8_t *)pixels.mutableBytes + (size_t)row * width * 4,
                       source + (size_t)row * readback->info.stride, (size_t)width * 4);
              }
            }
            completion:^(mln_status readStatus, NSString *readMessage) {
              if (readStatus != MLN_STATUS_OK || !pixels) {
                completion(nil, attributions, nil,
                           readMessage.length ? readMessage : MLNFFIStatusDescription(readStatus));
                return;
              }
#if TARGET_OS_IPHONE
              MLNImage *mglImage = [[MLNImage alloc] initWithMLNPremultipliedImage:pixels
                                                                             width:width
                                                                            height:height
                                                                             scale:options.scale];
#else
              MLNImage *mglImage = [[MLNImage alloc] initWithMLNPremultipliedImage:pixels
                                                                             width:width
                                                                            height:height];
              mglImage.size = NSMakeSize(mglImage.size.width / options.scale,
                                         mglImage.size.height / options.scale);
#endif
              completion(mglImage, attributions, projection, nil);
            }];
      }];
}

MLNImage *MLNAttributedSnapshot(NSArray<NSString *> *attributions, MLNImage *mglImage,
                                MLNMapSnapshotOptions *options, void (^overlayHandler)()) {
  NSArray<MLNAttributionInfo *> *attributionInfo =
      MLNAttributionInfosFromAttributions(attributions);

#if TARGET_OS_IPHONE
  MLNAttributionInfoStyle attributionInfoStyle = MLNAttributionInfoStyleLong;
  for (NSUInteger styleValue = MLNAttributionInfoStyleLong;
       styleValue >= MLNAttributionInfoStyleShort; styleValue--) {
    attributionInfoStyle = (MLNAttributionInfoStyle)styleValue;
    CGSize attributionSize = [MLNMapSnapshotter attributionSizeWithLogoStyle:attributionInfoStyle
                                                      sourceAttributionStyle:attributionInfoStyle
                                                             attributionInfo:attributionInfo];
    if (attributionSize.width <= mglImage.size.width) {
      break;
    }
  }

  UIImage *logoImage = [MLNMapSnapshotter logoImageWithStyle:attributionInfoStyle];
  CGSize attributionBackgroundSize =
      [MLNMapSnapshotter attributionTextSizeWithStyle:attributionInfoStyle
                                      attributionInfo:attributionInfo];

  CGRect logoImageRect =
      CGRectMake(MLNLogoImagePosition.x,
                 mglImage.size.height - (MLNLogoImagePosition.y + logoImage.size.height),
                 logoImage.size.width, logoImage.size.height);
  CGPoint attributionOrigin =
      CGPointMake(mglImage.size.width - 10 - attributionBackgroundSize.width,
                  logoImageRect.origin.y + (logoImageRect.size.height / 2) -
                      (attributionBackgroundSize.height / 2) + 1);
  if (!logoImage) {
    CGSize defaultLogoSize = [MLNMapSnapshotter maplibreLongStyleLogo].size;
    logoImageRect =
        CGRectMake(0, mglImage.size.height - (MLNLogoImagePosition.y + defaultLogoSize.height), 0,
                   defaultLogoSize.height);
    attributionOrigin = CGPointMake(10, logoImageRect.origin.y + (logoImageRect.size.height / 2) -
                                            (attributionBackgroundSize.height / 2) + 1);
  }

  CGRect attributionBackgroundFrame =
      CGRectMake(attributionOrigin.x, attributionOrigin.y, attributionBackgroundSize.width,
                 attributionBackgroundSize.height);
  CGPoint attributionTextPosition = CGPointMake(attributionBackgroundFrame.origin.x + 10,
                                                attributionBackgroundFrame.origin.y - 1);

  CGRect cropRect = CGRectMake(attributionBackgroundFrame.origin.x * mglImage.scale,
                               attributionBackgroundFrame.origin.y * mglImage.scale,
                               attributionBackgroundSize.width * mglImage.scale,
                               attributionBackgroundSize.height * mglImage.scale);

  UIGraphicsBeginImageContextWithOptions(mglImage.size, NO, options.scale);

  [mglImage drawInRect:CGRectMake(0, 0, mglImage.size.width, mglImage.size.height)];

  overlayHandler();
  CGContextRef currentContext = UIGraphicsGetCurrentContext();

  if (!currentContext) {
    // If the current context has been corrupted by the user,
    // return nil so we can generate an error later.
    return nil;
  }

  if (options.showsLogo && logoImage) {
    [logoImage drawInRect:logoImageRect];
  }

  if (options.showsAttribution) {
    UIImage *currentImage = UIGraphicsGetImageFromCurrentImageContext();
    CGImageRef attributionImageRef = CGImageCreateWithImageInRect([currentImage CGImage], cropRect);
    UIImage *attributionImage = [UIImage imageWithCGImage:attributionImageRef];
    CGImageRelease(attributionImageRef);

    CIImage *ciAttributionImage = [[CIImage alloc] initWithCGImage:attributionImage.CGImage];

    UIImage *blurredAttributionBackground =
        [MLNMapSnapshotter blurredAttributionBackground:ciAttributionImage];

    [blurredAttributionBackground drawInRect:attributionBackgroundFrame];

    [MLNMapSnapshotter drawAttributionTextWithStyle:attributionInfoStyle
                                             origin:attributionTextPosition
                                    attributionInfo:attributionInfo];
  }

  UIImage *compositedImage = UIGraphicsGetImageFromCurrentImageContext();

  UIGraphicsEndImageContext();

  return compositedImage;

#else
  NSRect targetFrame = {.origin = NSZeroPoint, .size = options.size};

  MLNAttributionInfoStyle attributionInfoStyle = MLNAttributionInfoStyleLong;
  for (NSUInteger styleValue = MLNAttributionInfoStyleLong;
       styleValue >= MLNAttributionInfoStyleShort; styleValue--) {
    attributionInfoStyle = (MLNAttributionInfoStyle)styleValue;
    CGSize attributionSize = [MLNMapSnapshotter attributionSizeWithLogoStyle:attributionInfoStyle
                                                      sourceAttributionStyle:attributionInfoStyle
                                                             attributionInfo:attributionInfo];
    if (attributionSize.width <= mglImage.size.width) {
      break;
    }
  }

  NSImage *logoImage = [MLNMapSnapshotter logoImageWithStyle:attributionInfoStyle];
  CGSize attributionBackgroundSize =
      [MLNMapSnapshotter attributionTextSizeWithStyle:attributionInfoStyle
                                      attributionInfo:attributionInfo];
  NSImage *sourceImage = mglImage;

  CGRect logoImageRect = CGRectMake(MLNLogoImagePosition.x, MLNLogoImagePosition.y,
                                    logoImage.size.width, logoImage.size.height);
  CGPoint attributionOrigin = CGPointMake(
      targetFrame.size.width - 10 - attributionBackgroundSize.width, MLNLogoImagePosition.y + 1);
  if (!logoImage) {
    CGSize defaultLogoSize = [MLNMapSnapshotter maplibreLongStyleLogo].size;
    logoImageRect = CGRectMake(0, MLNLogoImagePosition.y, 0, defaultLogoSize.height);
    attributionOrigin = CGPointMake(10, attributionOrigin.y);
  }

  CGRect attributionBackgroundFrame =
      CGRectMake(attributionOrigin.x, attributionOrigin.y, attributionBackgroundSize.width,
                 attributionBackgroundSize.height);
  CGPoint attributionTextPosition =
      CGPointMake(attributionBackgroundFrame.origin.x + 10,
                  logoImageRect.origin.y + (logoImageRect.size.height / 2) -
                      (attributionBackgroundSize.height / 2));

  NSImage *compositedImage = nil;
  NSImageRep *sourceImageRep = [sourceImage bestRepresentationForRect:targetFrame
                                                              context:nil
                                                                hints:nil];
  compositedImage = [[NSImage alloc] initWithSize:targetFrame.size];

  [compositedImage lockFocus];

  [sourceImageRep drawInRect:targetFrame];

  overlayHandler();

  NSGraphicsContext *currentContext = [NSGraphicsContext currentContext];
  if (!currentContext) {
    // If the current context has been corrupted by the user,
    // return nil so we can generate an error later.
    return nil;
  }

  if (options.showsLogo) {
    [logoImage drawInRect:logoImageRect];
  }

  if (options.showsAttribution) {
    NSBitmapImageRep *attributionBackground =
        [[NSBitmapImageRep alloc] initWithFocusedViewRect:attributionBackgroundFrame];

    CIImage *attributionBackgroundImage =
        [[CIImage alloc] initWithCGImage:[attributionBackground CGImage]];

    NSImage *blurredAttributionBackground =
        [MLNMapSnapshotter blurredAttributionBackground:attributionBackgroundImage];

    [blurredAttributionBackground drawInRect:attributionBackgroundFrame];

    [MLNMapSnapshotter drawAttributionTextWithStyle:attributionInfoStyle
                                             origin:attributionTextPosition
                                    attributionInfo:attributionInfo];
  }

  [compositedImage unlockFocus];

  return compositedImage;
#endif
}

MLNMapSnapshot *MLNSnapshotWithDecoratedImage(MLNImage *mglImage, MLNMapSnapshotOptions *options,
                                              NSArray<NSString *> *attributions,
                                              MLNSnapshotProjection *projection,
                                              MLNMapSnapshotOverlayHandler overlayHandler,
                                              NSError *_Nullable *outError) {
  MLNImage *compositedImage = MLNAttributedSnapshot(attributions, mglImage, options, ^{
    if (!overlayHandler) {
      return;
    }
#if TARGET_OS_IPHONE
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) {
      return;
    }
    MLNMapSnapshotOverlay *snapshotOverlay =
        [[MLNMapSnapshotOverlay alloc] initWithContext:context
                                                 scale:options.scale
                                            projection:projection];
    CGContextSaveGState(context);
    overlayHandler(snapshotOverlay);
    CGContextRestoreGState(context);
#else
        NSGraphicsContext *context = [NSGraphicsContext currentContext];
        if (!context) {
            return;
        }
        MLNMapSnapshotOverlay *snapshotOverlay = [[MLNMapSnapshotOverlay alloc] initWithContext:context.CGContext
                                                                                          scale:options.scale
                                                                                     projection:projection];
        [context saveGraphicsState];
        overlayHandler(snapshotOverlay);
        [context restoreGraphicsState];
#endif
  });

  if (compositedImage) {
    return [[MLNMapSnapshot alloc] initWithImage:compositedImage
                                           scale:options.scale
                                      projection:projection];
  } else {
    if (outError) {
      NSDictionary *userInfo =
          @{NSLocalizedDescriptionKey : @"Failed to generate composited snapshot."};
      *outError = [NSError errorWithDomain:MLNErrorDomain
                                      code:MLNErrorCodeSnapshotFailed
                                  userInfo:userInfo];
    }
    return nil;
  }
}

NSArray<MLNAttributionInfo *> *MLNAttributionInfosFromAttributions(
    NSArray<NSString *> *attributions) {
  NSMutableArray *infos = [NSMutableArray array];

#if TARGET_OS_IPHONE
  CGFloat fontSize = [UIFont smallSystemFontSize];
  UIColor *attributeFontColor = [UIColor blackColor];
#else
  CGFloat fontSize = [NSFont systemFontSizeForControlSize:NSControlSizeMini];
  NSColor *attributeFontColor = [NSColor blackColor];
#endif
  for (NSString *attributionHTMLString in attributions) {
    NSArray *tileSetInfos = [MLNAttributionInfo attributionInfosFromHTMLString:attributionHTMLString
                                                                      fontSize:fontSize
                                                                     linkColor:attributeFontColor];
    [infos growArrayByAddingAttributionInfosFromArray:tileSetInfos];
  }
  return infos;
}

+ (void)drawAttributionTextWithStyle:(MLNAttributionInfoStyle)attributionInfoStyle
                              origin:(CGPoint)origin
                     attributionInfo:(NSArray<MLNAttributionInfo *> *)attributionInfo {
  for (MLNAttributionInfo *info in attributionInfo) {
    if (info.isFeedbackLink) {
      continue;
    }
    NSAttributedString *attribution = [info titleWithStyle:attributionInfoStyle];
    [attribution drawAtPoint:origin];

    origin.x += [attribution size].width + 10;
  }
}

+ (MLNImage *)blurredAttributionBackground:(CIImage *)backgroundImage {
  CGAffineTransform transform = CGAffineTransformIdentity;
  CIFilter *clamp = [CIFilter filterWithName:@"CIAffineClamp"];
  [clamp setValue:backgroundImage forKey:kCIInputImageKey];
  [clamp setValue:[NSValue valueWithBytes:&transform objCType:@encode(CGAffineTransform)]
           forKey:@"inputTransform"];

  CIFilter *attributionBlurFilter = [CIFilter filterWithName:@"CIGaussianBlur"];
  [attributionBlurFilter setValue:[clamp outputImage] forKey:kCIInputImageKey];
  [attributionBlurFilter setValue:@10 forKey:kCIInputRadiusKey];

  CIFilter *attributionColorFilter = [CIFilter filterWithName:@"CIColorControls"];
  [attributionColorFilter setValue:[attributionBlurFilter outputImage] forKey:kCIInputImageKey];
  [attributionColorFilter setValue:@(0.1) forKey:kCIInputBrightnessKey];

  CIImage *blurredImage = attributionColorFilter.outputImage;

  CIContext *ctx = [CIContext contextWithOptions:nil];
  CGImageRef cgimg = [ctx createCGImage:blurredImage fromRect:[backgroundImage extent]];
  MLNImage *image;

#if TARGET_OS_IPHONE
  image = [UIImage imageWithCGImage:cgimg];
#else
  image = [[NSImage alloc] initWithCGImage:cgimg size:[backgroundImage extent].size];
#endif

  CGImageRelease(cgimg);
  return image;
}

+ (MLNImage *)logoImageWithStyle:(MLNAttributionInfoStyle)style {
  MLNImage *logoImage;
  switch (style) {
    case MLNAttributionInfoStyleLong:
      logoImage = [MLNMapSnapshotter maplibreLongStyleLogo];
      break;
    case MLNAttributionInfoStyleMedium:
#if TARGET_OS_IPHONE
      logoImage = [UIImage imageNamed:@"maplibre-logo-icon"
                               inBundle:[NSBundle mgl_frameworkBundle]
          compatibleWithTraitCollection:nil];
#else
      logoImage = [[NSImage alloc]
          initWithContentsOfFile:[[NSBundle mgl_frameworkBundle] pathForResource:@"mapbox_helmet"
                                                                          ofType:@"pdf"]];
#endif
      break;
    case MLNAttributionInfoStyleShort:
      logoImage = nil;
      break;
  }
  return logoImage;
}

+ (MLNImage *)maplibreLongStyleLogo {
  MLNImage *logoImage;
#if TARGET_OS_IPHONE
  logoImage = [UIImage imageNamed:@"maplibre-logo-stroke-gray"
                           inBundle:[NSBundle mgl_frameworkBundle]
      compatibleWithTraitCollection:nil];
#else
  logoImage = [[NSImage alloc]
      initWithContentsOfFile:[[NSBundle mgl_frameworkBundle] pathForResource:@"mapbox"
                                                                      ofType:@"pdf"]];
#endif
  return logoImage;
}

+ (CGSize)attributionSizeWithLogoStyle:(MLNAttributionInfoStyle)logoStyle
                sourceAttributionStyle:(MLNAttributionInfoStyle)attributionStyle
                       attributionInfo:(NSArray<MLNAttributionInfo *> *)attributionInfo {
  MLNImage *logoImage = [self logoImageWithStyle:logoStyle];

  CGSize attributionBackgroundSize =
      [MLNMapSnapshotter attributionTextSizeWithStyle:attributionStyle
                                      attributionInfo:attributionInfo];

  CGSize attributionSize = CGSizeZero;

  if (logoImage) {
    attributionSize.width = MLNLogoImagePosition.x + logoImage.size.width + 10;
  }
  attributionSize.width = attributionSize.width + 10 + attributionBackgroundSize.width + 10;
  attributionSize.height = MAX(logoImage.size.height, attributionBackgroundSize.height);

  return attributionSize;
}

+ (CGSize)attributionTextSizeWithStyle:(MLNAttributionInfoStyle)attributionStyle
                       attributionInfo:(NSArray<MLNAttributionInfo *> *)attributionInfo {
  CGSize attributionBackgroundSize = CGSizeMake(10, 0);
  for (MLNAttributionInfo *info in attributionInfo) {
    if (info.isFeedbackLink) {
      continue;
    }
    CGSize attributionSize = [info titleWithStyle:attributionStyle].size;
    attributionBackgroundSize.width += attributionSize.width + 10;
    attributionBackgroundSize.height =
        MAX(attributionSize.height, attributionBackgroundSize.height);
  }

  return attributionBackgroundSize;
}

- (void)cancel {
  MLNLogInfo(@"Cancelling snapshotter.");

  _startGeneration++;
  _styleCompletion = nil;
  [self releaseMap];
}

- (void)releaseMap {
  [_style mgl_invalidate];
  _style = nil;
  if (_session != MLN_HANDLE_NULL) {
    mln_diagnostic diagnostic = {sizeof(mln_diagnostic)};
    mln_render_session_dispose(_session, NULL, &diagnostic);
    _session = MLN_HANDLE_NULL;
  }
  [_map invalidate];
  _map = nil;
}

- (void)configureWithOptions:(MLNMapSnapshotOptions *)options {
  _startGeneration++;
  [self releaseMap];
  _installedImages = [NSMutableSet set];
  _styleState = MLNSnapshotStyleStateLoading;
  _styleError = nil;
  _styleCompletion = nil;

  // Size; taking into account the minimum texture size for OpenGL ES
  // For non retina screens the ratio is 1:1 MLNSnapshotterMinimumPixelSize
  CGSize size = CGSizeMake(MAX(options.size.width, MLNSnapshotterMinimumPixelSize),
                           MAX(options.size.height, MLNSnapshotterMinimumPixelSize));

  float pixelRatio = MAX(options.scale, 1);

  // Classic passed the tile server options, API key and local font family
  // here. The C API's runtime takes none of them (C_API_GAPS.md).
  _map = [[MLNFFIMap alloc] initWithSize:size scaleFactor:pixelRatio mode:MLN_MAP_MODE_STATIC];
  if (!_map) {
    return;
  }
  _map.eventObserver = self;
  _style = [[MLNStyle alloc] initWithMap:_map stylable:self];

  mln_offscreen_descriptor descriptor = {sizeof(mln_offscreen_descriptor)};
  descriptor.logical_size = {(uint32_t)size.width, (uint32_t)size.height};
  mln_render_session_attach_options attachOptions = {sizeof(mln_render_session_attach_options)};
  attachOptions.driver = MLN_RENDER_DRIVER_CORE_WORKER;
  mln_map handle = _map.handle;
  mln_offscreen_device device = MLNSnapshotterOffscreenDevice();
  __block mln_render_session session = MLN_HANDLE_NULL;
  __block mln_render_session *outSession = &session;
  NSString *message;
  if ([_map call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
        return mln_map_attach_offscreen(handle, &descriptor, &attachOptions, device, outSession,
                                        completion, diagnostic);
      }
          consume:nil
          message:&message] != MLN_STATUS_OK) {
    MLNLogError(@"Failed to attach the snapshot render target: %@", message);
  }
  _session = session;

  // Camera options
  mln_camera_update update = {sizeof(mln_camera_update)};
  update.mode = MLN_CAMERA_UPDATE_MODE_JUMP;
  update.camera.size = sizeof(mln_camera_options);
  if (CLLocationCoordinate2DIsValid(options.camera.centerCoordinate)) {
    update.camera.fields |= MLN_CAMERA_OPTION_CENTER;
    update.camera.center = MLNLatLngFromLocationCoordinate2D(options.camera.centerCoordinate);
  }
  if (options.camera.heading >= 0) {
    update.camera.fields |= MLN_CAMERA_OPTION_BEARING;
    update.camera.bearing = MAX(0, options.camera.heading);
  }
  if (options.zoomLevel >= 0) {
    update.camera.fields |= MLN_CAMERA_OPTION_ZOOM;
    update.camera.zoom = MAX(0, options.zoomLevel);
  }
  if (options.camera.pitch >= 0) {
    update.camera.fields |= MLN_CAMERA_OPTION_PITCH;
    update.camera.pitch = MAX(0, options.camera.pitch);
  }
  if (options.camera.roll != 0) {
    update.camera.fields |= MLN_CAMERA_OPTION_ROLL;
    update.camera.roll = options.camera.roll;
  }
  if (update.camera.fields) {
    // MapSnapshotter::setCameraOptions applied the region padding, zero here.
    update.camera.fields |= MLN_CAMERA_OPTION_PADDING;
    [_map perform:@"set the snapshot camera"
           submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
             return mln_map_update_camera(handle, &update, completion, diagnostic);
           }];
  }

  // Region: MapSnapshotter::setRegion jumped to cameraForLatLngs of its corners.
  if (!MLNCoordinateBoundsIsEmpty(options.coordinateBounds)) {
    std::vector<mln_lat_lng> corners = {
        MLNLatLngFromLocationCoordinate2D(options.coordinateBounds.sw),
        MLNLatLngFromLocationCoordinate2D(options.coordinateBounds.ne)};
    mln_camera_fit_options fitOptions = {sizeof(mln_camera_fit_options)};
    fitOptions.fields = MLN_CAMERA_FIT_OPTION_PADDING;
    __block mln_camera_options camera = {sizeof(mln_camera_options)};
    __block BOOL hasCamera = NO;
    [_map call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
      return mln_map_camera_for_lat_lngs(handle, corners.data(), corners.size(), &fitOptions,
                                         completion, diagnostic);
    }
        consume:^(const mln_completion_result *result) {
          if (result->value) {
            camera = *(const mln_camera_options *)result->value;
            hasCamera = YES;
          }
        }
        message:nil];
    if (hasCamera) {
      mln_camera_update regionUpdate = {sizeof(mln_camera_update)};
      regionUpdate.mode = MLN_CAMERA_UPDATE_MODE_JUMP;
      regionUpdate.camera = camera;
      regionUpdate.camera.size = sizeof(mln_camera_options);
      [_map perform:@"set the snapshot region"
             submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
               return mln_map_update_camera(handle, &regionUpdate, completion, diagnostic);
             }];
    }
  }

  // Classic's snapshotter loaded the style asynchronously, so the camera above
  // was set first and the style's default camera did not apply. The C API can
  // load a local style within the call, so the style comes last.
  [_map loadStyleURL:options.styleURL.absoluteString message:nil];
}

- (MLNStyle *)style {
  return _style;
}

// MARK: - MLNFFIStylable

- (uint64_t)mgl_renderSession {
  return _session;
}

- (void)mgl_setNeedsRerender {
  // A static map renders only when a still image is requested.
}

// MARK: - MLNFFIMapEventObserver

- (void)ffiMap:(MLNFFIMap *)map didReceiveEvent:(MLNFFIEvent *)event {
  if (map != _map) {
    return;
  }
  switch (event.type) {
    case MLN_RUNTIME_EVENT_MAP_STYLE_LOADED: {
      _styleState = MLNSnapshotStyleStateLoaded;
      if ([self.delegate respondsToSelector:@selector(mapSnapshotter:didFinishLoadingStyle:)]) {
        [self.delegate mapSnapshotter:self didFinishLoadingStyle:self.style];
      }
      void (^styleCompletion)(NSString *) = _styleCompletion;
      _styleCompletion = nil;
      if (styleCompletion) {
        styleCompletion(nil);
      }
      break;
    }
    case MLN_RUNTIME_EVENT_MAP_LOADING_FAILED: {
      if (_styleState == MLNSnapshotStyleStateLoaded) {
        break;
      }
      _styleState = MLNSnapshotStyleStateFailed;
      _styleError = event.message;
      if ([self.delegate respondsToSelector:@selector(mapSnapshotterDidFail:withError:)]) {
        NSDictionary *userInfo = @{
          NSLocalizedDescriptionKey : NSLocalizedStringWithDefaultValue(
              @"SNAPSHOT_LOAD_STYLE_FAILED_DESC", nil, nil,
              @"The snapshot failed because the style can’t be loaded.",
              @"User-friendly error description"),
          NSLocalizedFailureReasonErrorKey : event.message,
        };
        NSError *error = [NSError errorWithDomain:MLNErrorDomain
                                             code:MLNErrorCodeLoadStyleFailed
                                         userInfo:userInfo];
        [self.delegate mapSnapshotterDidFail:self withError:error];
      }
      void (^styleCompletion)(NSString *) = _styleCompletion;
      _styleCompletion = nil;
      if (styleCompletion) {
        styleCompletion(event.message);
      }
      break;
    }
    case MLN_RUNTIME_EVENT_MAP_STYLE_IMAGE_MISSING:
      // The C API reports the missing image's ID as the event message.
      if ([self.delegate respondsToSelector:@selector(mapSnapshotter:didFailLoadingImageNamed:)]) {
        [self.delegate mapSnapshotter:self didFailLoadingImageNamed:event.message];
      }
      break;
    default:
      break;
  }
}

- (double)alphaForShapeAnnotation:(MLNShape *)annotation {
  if ([self.delegate respondsToSelector:@selector(mapSnapshotter:alphaForShapeAnnotation:)]) {
    return [self.delegate mapSnapshotter:self alphaForShapeAnnotation:annotation];
  }
  return 1.0;
}

- (MLNColor *)strokeColorForShapeAnnotation:(MLNShape *)annotation {
  if ([self.delegate respondsToSelector:@selector(mapSnapshotter:strokeColorForShapeAnnotation:)]) {
    MLNColor *color = [self.delegate mapSnapshotter:self strokeColorForShapeAnnotation:annotation];
    return color;
  }

  return [MLNColor whiteColor];
}

- (MLNColor *)fillColorForPolygonAnnotation:(MLNPolygon *)annotation {
  if ([self.delegate respondsToSelector:@selector(mapSnapshotter:fillColorForPolygonAnnotation:)]) {
    MLNColor *color = [self.delegate mapSnapshotter:self fillColorForPolygonAnnotation:annotation];
    return color;
  }
  return [MLNColor whiteColor];
}

- (CGFloat)lineWidthForPolylineAnnotation:(MLNPolyline *)annotation {
  if ([self.delegate respondsToSelector:@selector(mapSnapshotter:
                                            lineWidthForPolylineAnnotation:)]) {
    return [self.delegate mapSnapshotter:self lineWidthForPolylineAnnotation:annotation];
  }

  return 3.0;
}

@end
