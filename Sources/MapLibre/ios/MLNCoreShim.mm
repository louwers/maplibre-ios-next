#import "MLNCoreShim.h"

#import "MLNFFIMap+Style.h"
#import "MLNGeoJSON.h"
#import "MLNLoggingConfiguration_Private.h"
#import "MLNStyle_Private.h"
#import "MLNStyleValue_Private.h"
#import "UIImage+MLNAdditions.h"

namespace mln {

namespace {

// The core annotation manager's source and layer identifiers.
NSString *const AnnotationSourceID = @"org.maplibre.annotations";
NSString *const PointLayerID = @"org.maplibre.annotations.points";
NSString *const ShapeLayerPrefix = @"org.maplibre.annotations.shape.";

mln_lat_lng toC(const LatLng &latLng) { return {latLng.latitude(), latLng.longitude()}; }

mln_edge_insets toC(const EdgeInsets &insets) {
  return {insets.top(), insets.left(), insets.bottom(), insets.right()};
}

EdgeInsets fromC(const mln_edge_insets &insets) {
  return {insets.top, insets.left, insets.bottom, insets.right};
}

// The core accepts camera centers outside [-90, 90] only after clamping; an
// invalid one throws, as LatLng's constructor does.
LatLng latLngFromC(const mln_lat_lng &latLng) { return {latLng.latitude, latLng.longitude}; }

CameraOptions cameraFromC(const mln_camera &camera) {
  CameraOptions options;
  options.center = latLngFromC(camera.center);
  options.padding = fromC(camera.padding);
  options.zoom = camera.zoom;
  options.bearing = camera.bearing;
  options.pitch = camera.pitch;
  options.roll = camera.roll;
  options.fov = camera.field_of_view;
  return options;
}

// The camera_for_* queries answer with camera options, whose fields say
// which members are set.
CameraOptions cameraFromC(const mln_camera_options &camera) {
  CameraOptions options;
  if (camera.fields & MLN_CAMERA_OPTION_CENTER) options.center = latLngFromC(camera.center);
  if (camera.fields & MLN_CAMERA_OPTION_PADDING) options.padding = fromC(camera.padding);
  if (camera.fields & MLN_CAMERA_OPTION_ANCHOR) {
    options.anchor = ScreenCoordinate(camera.anchor.x, camera.anchor.y);
  }
  if (camera.fields & MLN_CAMERA_OPTION_ZOOM) options.zoom = camera.zoom;
  if (camera.fields & MLN_CAMERA_OPTION_BEARING) options.bearing = camera.bearing;
  if (camera.fields & MLN_CAMERA_OPTION_PITCH) options.pitch = camera.pitch;
  if (camera.fields & MLN_CAMERA_OPTION_ROLL) options.roll = camera.roll;
  if (camera.fields & MLN_CAMERA_OPTION_FOV) options.fov = camera.field_of_view;
  return options;
}

mln_camera_options cameraToC(const CameraOptions &camera) {
  mln_camera_options options = {sizeof(mln_camera_options)};
  if (camera.center) {
    options.fields |= MLN_CAMERA_OPTION_CENTER;
    options.center = toC(*camera.center);
  }
  if (camera.padding) {
    options.fields |= MLN_CAMERA_OPTION_PADDING;
    options.padding = toC(*camera.padding);
  }
  if (camera.anchor) {
    options.fields |= MLN_CAMERA_OPTION_ANCHOR;
    options.anchor = {camera.anchor->x, camera.anchor->y};
  }
  if (camera.zoom) {
    options.fields |= MLN_CAMERA_OPTION_ZOOM;
    options.zoom = *camera.zoom;
  }
  if (camera.bearing) {
    options.fields |= MLN_CAMERA_OPTION_BEARING;
    options.bearing = *camera.bearing;
  }
  if (camera.pitch) {
    options.fields |= MLN_CAMERA_OPTION_PITCH;
    options.pitch = *camera.pitch;
  }
  if (camera.roll) {
    options.fields |= MLN_CAMERA_OPTION_ROLL;
    options.roll = *camera.roll;
  }
  if (camera.fov) {
    options.fields |= MLN_CAMERA_OPTION_FOV;
    options.field_of_view = *camera.fov;
  }
  return options;
}

// Runs the transition's finish function on the main thread when the C API
// reports the transition's end, whatever the outcome.
struct TransitionEnd {
  std::function<void()> finish;
};

void transitionEndCallback(void *userData, const mln_camera_transition_end *) {
  auto *end = static_cast<TransitionEnd *>(userData);
  std::function<void()> finish = end->finish;
  dispatch_async(dispatch_get_main_queue(), ^{
    finish();
  });
}

void transitionEndRelease(void *userData) { delete static_cast<TransitionEnd *>(userData); }

mln_animation_options animationToC(const AnimationOptions &animation) {
  mln_animation_options options = {};
  if (animation.duration) {
    options.fields |= MLN_ANIMATION_OPTION_DURATION;
    options.duration_ms =
        std::chrono::duration<double, std::milli>(*animation.duration).count();
  }
  if (animation.velocity) {
    options.fields |= MLN_ANIMATION_OPTION_VELOCITY;
    options.velocity = *animation.velocity;
  }
  if (animation.minZoom) {
    options.fields |= MLN_ANIMATION_OPTION_MIN_ZOOM;
    options.min_zoom = *animation.minZoom;
  }
  if (animation.easing) {
    options.fields |= MLN_ANIMATION_OPTION_EASING;
    options.easing = {animation.easing->x1, animation.easing->y1, animation.easing->x2,
                      animation.easing->y2};
  }
  if (animation.transitionFinishFn) {
    options.end_handler.callback = transitionEndCallback;
    options.end_handler.user_data = new TransitionEnd{animation.transitionFinishFn};
    options.end_handler.release_user_data = transitionEndRelease;
  }
  return options;
}

mln_camera_fit_options fitOptions(const EdgeInsets &padding, const std::optional<double> &bearing,
                                  const std::optional<double> &pitch) {
  mln_camera_fit_options options = {sizeof(mln_camera_fit_options)};
  options.fields = MLN_CAMERA_FIT_OPTION_PADDING;
  options.padding = toC(padding);
  if (bearing) {
    options.fields |= MLN_CAMERA_FIT_OPTION_BEARING;
    options.bearing = *bearing;
  }
  if (pitch) {
    options.fields |= MLN_CAMERA_FIT_OPTION_PITCH;
    options.pitch = *pitch;
  }
  return options;
}

}  // namespace

Map::Map(MLNFFIMap *map_) : map(map_), annotationImages([NSMutableDictionary dictionary]) {}

Map::~Map() = default;

mln_map Map::handle() const { return map.handle; }

mln_map_snapshot Map::snapshot() const { return [map snapshot]; }

// MARK: Style

std::string Map::getStyleURL() const { return std::string([map styleURL].UTF8String ?: ""); }

std::string Map::getStyleJSON() const { return std::string([map loadedStyleJSON].UTF8String ?: ""); }

void Map::loadStyleURL(const std::string &url) {
  NSString *message;
  if ([map loadStyleURL:@(url.c_str()) message:&message] != MLN_STATUS_OK) {
    MLNLogError(@"Failed to load style %s: %@", url.c_str(), message);
  }
}

void Map::loadStyleJSON(const std::string &json) {
  NSString *message;
  if ([map loadStyleJSON:@(json.c_str()) message:&message] != MLN_STATUS_OK) {
    MLNLogError(@"Failed to load style JSON: %@", message);
  }
}

CameraOptions Map::getStyleDefaultCamera() const {
  CameraOptions camera;
  NSData *data = [[map loadedStyleJSON] dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *style = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  if (![style isKindOfClass:[NSDictionary class]]) {
    return camera;
  }
  NSArray *center = style[@"center"];
  if ([center isKindOfClass:[NSArray class]] && center.count == 2) {
    camera.center = LatLng([center[1] doubleValue], [center[0] doubleValue]);
  }
  if ([style[@"zoom"] isKindOfClass:[NSNumber class]]) {
    camera.zoom = [style[@"zoom"] doubleValue];
  }
  if ([style[@"bearing"] isKindOfClass:[NSNumber class]]) {
    camera.bearing = [style[@"bearing"] doubleValue];
  }
  if ([style[@"pitch"] isKindOfClass:[NSNumber class]]) {
    camera.pitch = [style[@"pitch"] doubleValue];
  }
  return camera;
}

// MARK: Camera

CameraOptions Map::getCameraOptions(const std::optional<EdgeInsets> &padding) const {
  mln_map_snapshot state = snapshot();
  CameraOptions camera = cameraFromC(state.view.camera);
  if (padding && *padding != fromC(state.view.camera.padding)) {
    // TransformState::getCameraOptions(padding): the center is the coordinate
    // at the center of the given padding.
    double width = state.view.extent.width;
    double height = state.view.extent.height;
    ScreenCoordinate center((padding->left() + width - padding->right()) / 2,
                            (padding->top() + height - padding->bottom()) / 2);
    camera.center = latLngForPixel(center);
    camera.padding = padding;
  }
  return camera;
}

mln_gesture_phase Map::nextGesturePhase() {
  if (!gestureInProgress) {
    return MLN_GESTURE_PHASE_NONE;
  }
  if (!gestureBegun) {
    gestureBegun = true;
    return MLN_GESTURE_PHASE_BEGIN;
  }
  return MLN_GESTURE_PHASE_UPDATE;
}

void Map::updateCamera(mln_camera_update_mode mode, const CameraOptions &camera,
                       const AnimationOptions &animation) {
  mln_map h = handle();
  // The core stopped running transitions when a new one began; the C API
  // animates fields independently unless they are cancelled first.
  mln_camera_update update = {sizeof(mln_camera_update)};
  update.mode = mode;
  update.camera = cameraToC(camera);
  update.animation = animationToC(animation);
  update.gesture_phase = nextGesturePhase();
  [map perform:@"cancel camera transitions"
        submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
          return mln_map_cancel_transitions(h, completion, diagnostic);
        }];
  [map perform:@"update the camera"
        submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
          return mln_map_update_camera(h, &update, completion, diagnostic);
        }];
}

void Map::jumpTo(const CameraOptions &camera) {
  updateCamera(MLN_CAMERA_UPDATE_MODE_JUMP, camera, {});
}

void Map::easeTo(const CameraOptions &camera, const AnimationOptions &animation) {
  updateCamera(MLN_CAMERA_UPDATE_MODE_EASE, camera, animation);
}

void Map::flyTo(const CameraOptions &camera, const AnimationOptions &animation) {
  updateCamera(MLN_CAMERA_UPDATE_MODE_FLY, camera, animation);
}

void Map::moveBy(const ScreenCoordinate &offset, const AnimationOptions &animation) {
  mln_map h = handle();
  mln_camera_delta delta = {sizeof(mln_camera_delta)};
  delta.fields = MLN_CAMERA_DELTA_OFFSET;
  delta.offset = {offset.x, offset.y};
  delta.animation = animationToC(animation);
  delta.gesture_phase = nextGesturePhase();
  [map perform:@"cancel camera transitions"
        submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
          return mln_map_cancel_transitions(h, completion, diagnostic);
        }];
  [map perform:@"move the camera"
        submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
          return mln_map_apply_camera_delta(h, &delta, completion, diagnostic);
        }];
}

void Map::cancelTransitions() {
  mln_map h = handle();
  [map perform:@"cancel camera transitions"
        submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
          return mln_map_cancel_transitions(h, completion, diagnostic);
        }];
}

// The C API has no gesture flag of its own: gesture phases ride along with
// camera commands. Ending a gesture sends an empty delta with the end phase.
void Map::setGestureInProgress(bool inProgress) {
  if (inProgress == gestureInProgress) {
    return;
  }
  gestureInProgress = inProgress;
  if (inProgress) {
    gestureBegun = false;
    return;
  }
  if (!gestureBegun) {
    return;
  }
  gestureBegun = false;
  mln_map h = handle();
  mln_camera_delta delta = {sizeof(mln_camera_delta)};
  delta.gesture_phase = MLN_GESTURE_PHASE_END;
  [map perform:@"end the gesture"
        submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
          return mln_map_apply_camera_delta(h, &delta, completion, diagnostic);
        }];
}

bool Map::isGestureInProgress() const { return gestureInProgress || snapshot().gesture_in_progress; }

CameraOptions Map::cameraForLatLngBounds(const LatLngBounds &bounds, const EdgeInsets &padding,
                                         const std::optional<double> &bearing,
                                         const std::optional<double> &pitch) const {
  mln_map h = handle();
  mln_camera_fit_options fit = fitOptions(padding, bearing, pitch);
  mln_lat_lng_bounds b = {toC(bounds.southwest()), toC(bounds.northeast())};
  __block mln_camera_options camera = {sizeof(mln_camera_options)};
  [map call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_camera_for_lat_lng_bounds(h, b, &fit, completion, diagnostic);
  }
      consume:^(const mln_completion_result *result) {
        if (result->value) {
          camera = *(const mln_camera_options *)result->value;
        }
      }
      message:nil];
  return cameraFromC(camera);
}

CameraOptions Map::cameraForLatLngs(const std::vector<LatLng> &latLngs, const EdgeInsets &padding,
                                    const std::optional<double> &bearing,
                                    const std::optional<double> &pitch) const {
  mln_map h = handle();
  mln_camera_fit_options fit = fitOptions(padding, bearing, pitch);
  std::vector<mln_lat_lng> coordinates;
  for (const LatLng &latLng : latLngs) {
    coordinates.push_back(toC(latLng));
  }
  const mln_lat_lng *data = coordinates.data();
  size_t count = coordinates.size();
  __block mln_camera_options camera = {sizeof(mln_camera_options)};
  [map call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_camera_for_lat_lngs(h, data, count, &fit, completion, diagnostic);
  }
      consume:^(const mln_completion_result *result) {
        if (result->value) {
          camera = *(const mln_camera_options *)result->value;
        }
      }
      message:nil];
  return cameraFromC(camera);
}

CameraOptions Map::cameraForGeometry(id geometry, const EdgeInsets &padding,
                                     const std::optional<double> &bearing,
                                     const std::optional<double> &pitch) const {
  mln_map h = handle();
  mln_camera_fit_options fit = fitOptions(padding, bearing, pitch);
  NSString *json = MLNFFIJSONStringFromObject(geometry);
  __block mln_camera_options camera = {sizeof(mln_camera_options)};
  [map call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_camera_for_geometry(h, MLNFFIBufferView(json), &fit, completion, diagnostic);
  }
      consume:^(const mln_completion_result *result) {
        if (result->value) {
          camera = *(const mln_camera_options *)result->value;
        }
      }
      message:nil];
  return cameraFromC(camera);
}

LatLngBounds Map::latLngBoundsForCamera(const CameraOptions &camera) const {
  mln_map h = handle();
  mln_camera_options options = cameraToC(camera);
  __block mln_lat_lng_bounds bounds = {};
  [map call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_lat_lng_bounds_for_camera(h, &options, completion, diagnostic);
  }
      consume:^(const mln_completion_result *result) {
        if (result->value) {
          bounds = *(const mln_lat_lng_bounds *)result->value;
        }
      }
      message:nil];
  return LatLngBounds::hull(latLngFromC(bounds.southwest), latLngFromC(bounds.northeast));
}

void Map::setBounds(const BoundOptions &bounds) {
  mln_map h = handle();
  mln_bound_options options = {sizeof(mln_bound_options)};
  if (bounds.bounds) {
    options.fields |= MLN_BOUND_OPTION_BOUNDS;
    options.bounds = {toC(bounds.bounds->southwest()), toC(bounds.bounds->northeast())};
  }
  if (bounds.minZoom) {
    options.fields |= MLN_BOUND_OPTION_MIN_ZOOM;
    options.min_zoom = *bounds.minZoom;
  }
  if (bounds.maxZoom) {
    options.fields |= MLN_BOUND_OPTION_MAX_ZOOM;
    options.max_zoom = *bounds.maxZoom;
  }
  if (bounds.minPitch) {
    options.fields |= MLN_BOUND_OPTION_MIN_PITCH;
    options.min_pitch = *bounds.minPitch;
  }
  if (bounds.maxPitch) {
    options.fields |= MLN_BOUND_OPTION_MAX_PITCH;
    options.max_pitch = *bounds.maxPitch;
  }
  [map perform:@"set the camera bounds"
        submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
          return mln_map_set_bounds(h, &options, completion, diagnostic);
        }];
}

BoundOptions Map::getBounds() const {
  mln_bound_options bounds = snapshot().bounds;
  BoundOptions options;
  if (bounds.fields & MLN_BOUND_OPTION_UNBOUNDED || !(bounds.fields & MLN_BOUND_OPTION_BOUNDS)) {
    options.bounds = LatLngBounds::world();
  } else {
    options.bounds =
        LatLngBounds::hull(latLngFromC(bounds.bounds.southwest), latLngFromC(bounds.bounds.northeast));
  }
  options.minZoom = bounds.min_zoom;
  options.maxZoom = bounds.max_zoom;
  options.minPitch = bounds.min_pitch;
  options.maxPitch = bounds.max_pitch;
  return options;
}

ScreenCoordinate Map::pixelForLatLng(const LatLng &latLng) const {
  mln_map_snapshot state = snapshot();
  mln_map_projection projection = MLN_HANDLE_NULL;
  mln_screen_point point = {};
  if (mln_map_projection_create(&state.view, &projection, nullptr) == MLN_STATUS_OK) {
    mln_map_projection_pixel_for_lat_lng(projection, toC(latLng), &point, nullptr);
    mln_map_projection_release(projection);
  }
  return {point.x, point.y};
}

LatLng Map::latLngForPixel(const ScreenCoordinate &pixel) const {
  mln_map_snapshot state = snapshot();
  mln_map_projection projection = MLN_HANDLE_NULL;
  mln_lat_lng latLng = {};
  if (mln_map_projection_create(&state.view, &projection, nullptr) == MLN_STATUS_OK) {
    mln_map_projection_lat_lng_for_pixel(projection, {pixel.x, pixel.y}, &latLng, nullptr);
    mln_map_projection_release(projection);
  }
  return latLngFromC(latLng);
}

// MARK: Size and options

void Map::setSize(Size size) {
  mln_logical_extent extent = {size.width, size.height, map.scaleFactor};
  mln_map h = handle();
  mln_render_session session = renderSession;
  if (session != MLN_HANDLE_NULL) {
    [map perform:@"resize the render session"
          submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
            return mln_render_session_resize(session, extent, completion, diagnostic);
          }];
  } else {
    [map perform:@"resize the map"
          submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
            return mln_map_resize(h, extent, completion, diagnostic);
          }];
  }
}

void Map::setConstrainMode(ConstrainMode mode) {
  options.withConstrainMode(mode);
  mln_map h = handle();
  mln_map_viewport_options viewport = {sizeof(mln_map_viewport_options)};
  viewport.fields = MLN_MAP_VIEWPORT_OPTION_CONSTRAIN_MODE;
  viewport.constrain_mode = (mln_constrain_mode)mode;
  [map perform:@"set the constrain mode"
        submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
          return mln_map_set_viewport_options(h, &viewport, completion, diagnostic);
        }];
}

void Map::setViewportMode(ViewportMode mode) {
  mln_map h = handle();
  mln_map_viewport_options viewport = {sizeof(mln_map_viewport_options)};
  viewport.fields = MLN_MAP_VIEWPORT_OPTION_VIEWPORT_MODE;
  viewport.viewport_mode = (mln_viewport_mode)mode;
  [map perform:@"set the viewport mode"
        submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
          return mln_map_set_viewport_options(h, &viewport, completion, diagnostic);
        }];
}

void Map::setFrustumOffset(const EdgeInsets &offset) {
  mln_map h = handle();
  mln_map_viewport_options viewport = {sizeof(mln_map_viewport_options)};
  viewport.fields = MLN_MAP_VIEWPORT_OPTION_FRUSTUM_OFFSET;
  viewport.frustum_offset = toC(offset);
  [map perform:@"set the frustum offset"
        submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
          return mln_map_set_viewport_options(h, &viewport, completion, diagnostic);
        }];
}

EdgeInsets Map::getFrustumOffset() const { return fromC(snapshot().view.viewport.frustum_offset); }

// MARK: Debug and tiles

void Map::setDebug(MapDebugOptions debug) {
  mln_map h = handle();
  [map perform:@"set debug options"
        submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
          return mln_map_set_debug_options(h, (mln_map_debug_flags)debug, completion, diagnostic);
        }];
}

MapDebugOptions Map::getDebug() const { return MapDebugOptions(snapshot().debug_options); }

void Map::setTileOptions(mln_map_tile_options tile) {
  mln_map h = handle();
  tile.size = sizeof(mln_map_tile_options);
  [map perform:@"set tile options"
        submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
          return mln_map_set_tile_options(h, &tile, completion, diagnostic);
        }];
}

void Map::setPrefetchZoomDelta(uint8_t delta) {
  mln_map_tile_options tile = {};
  tile.fields = MLN_MAP_TILE_OPTION_PREFETCH_ZOOM_DELTA;
  tile.prefetch_zoom_delta = delta;
  setTileOptions(tile);
}

uint8_t Map::getPrefetchZoomDelta() const { return snapshot().tile.prefetch_zoom_delta; }

void Map::setTileLodMinRadius(double radius) {
  mln_map_tile_options tile = {};
  tile.fields = MLN_MAP_TILE_OPTION_LOD_MIN_RADIUS;
  tile.lod_min_radius = radius;
  setTileOptions(tile);
}

double Map::getTileLodMinRadius() const { return snapshot().tile.lod_min_radius; }

void Map::setTileLodScale(double scale) {
  mln_map_tile_options tile = {};
  tile.fields = MLN_MAP_TILE_OPTION_LOD_SCALE;
  tile.lod_scale = scale;
  setTileOptions(tile);
}

double Map::getTileLodScale() const { return snapshot().tile.lod_scale; }

void Map::setTileLodPitchThreshold(double threshold) {
  mln_map_tile_options tile = {};
  tile.fields = MLN_MAP_TILE_OPTION_LOD_PITCH_THRESHOLD;
  tile.lod_pitch_threshold = threshold;
  setTileOptions(tile);
}

double Map::getTileLodPitchThreshold() const { return snapshot().tile.lod_pitch_threshold; }

void Map::setTileLodZoomShift(double shift) {
  mln_map_tile_options tile = {};
  tile.fields = MLN_MAP_TILE_OPTION_LOD_ZOOM_SHIFT;
  tile.lod_zoom_shift = shift;
  setTileOptions(tile);
}

double Map::getTileLodZoomShift() const { return snapshot().tile.lod_zoom_shift; }

void Map::enableRenderingStatsView(bool enabled) {
  mln_map h = handle();
  [map perform:@"toggle the rendering stats view"
        submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
          return mln_map_set_rendering_stats_view_enabled(h, enabled, completion, diagnostic);
        }];
}

bool Map::isRenderingStatsViewEnabled() const { return snapshot().rendering_stats_view_enabled; }

void Map::triggerRepaint() {
  mln_map h = handle();
  [map post:@"request a repaint"
      submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
        return mln_map_request_repaint(h, completion, diagnostic);
      }];
}

bool Map::isFullyLoaded() const { return snapshot().fully_loaded; }

// MARK: Annotations
//
// The core's AnnotationManager (src/mln/annotation at ios-v7.0.0) kept an
// annotation source and a point symbol layer in every style, and one line or
// fill layer per shape annotation below the point layer, styled with the
// annotation's constant values. The C API has no annotation source type, so
// the source is a GeoJSON source holding every annotation as a feature whose
// ID is its tag; the layers take their features by filter (a GeoJSON source
// has no source layers; the classic source-layer names are kept anyway).

AnnotationID Map::addAnnotation(const Annotation &annotation) {
  AnnotationID id = nextAnnotationID++;
  annotations[id] = annotation;
  annotationsDirty = true;
  flushAnnotations();
  return id;
}

void Map::updateAnnotation(AnnotationID id, const Annotation &annotation) {
  if (!annotations.count(id)) {
    return;
  }
  annotations[id] = annotation;
  annotationsDirty = true;
  flushAnnotations();
}

void Map::removeAnnotation(AnnotationID id) {
  if (annotations.erase(id)) {
    annotationsDirty = true;
    flushAnnotations();
  }
}

// AnnotationManager::addImage stored images under the source's prefix.
void Map::addAnnotationImage(NSString *name, UIImage *image) {
  NSString *styleName = [AnnotationSourceID stringByAppendingFormat:@".%@", name];
  annotationImages[styleName] = image;
  [image mgl_addToMap:map withName:styleName];
}

void Map::removeAnnotationImage(NSString *name) {
  NSString *styleName = [AnnotationSourceID stringByAppendingFormat:@".%@", name];
  [annotationImages removeObjectForKey:styleName];
  [map removeStyleImage:styleName message:nil];
}

void Map::restoreAnnotationsAfterStyleLoad() {
  for (NSString *name in annotationImages) {
    [annotationImages[name] mgl_addToMap:map withName:name];
  }
  annotationsDirty = true;
  flushAnnotations();
}

NSString *ShapeLayerID(AnnotationID id) {
  return [ShapeLayerPrefix stringByAppendingFormat:@"%llu", (unsigned long long)id];
}

// Writes the annotations into the style, as AnnotationManager::updateStyle()
// and updateData() did.
void Map::flushAnnotations() {
  if (!annotationsDirty) {
    return;
  }
  NSArray<MLNFFILayerInfo *> *layers = [map styleLayers];
  if (!layers) {
    // No style yet; restoreAnnotationsAfterStyleLoad() adds them later.
    return;
  }
  annotationsDirty = false;

  NSMutableArray *features = [NSMutableArray array];
  for (const auto &[id, annotation] : annotations) {
    if (const auto *symbol = std::get_if<SymbolAnnotation>(&annotation)) {
      [features addObject:@{
        @"type" : @"Feature",
        @"id" : @(id),
        @"geometry" : @{@"type" : @"Point", @"coordinates" : @[ @(symbol->geometry.x), @(symbol->geometry.y) ]},
        @"properties" : @{@"sprite" : @(symbol->icon.c_str())},
      }];
    } else if (const auto *line = std::get_if<LineAnnotation>(&annotation)) {
      [features addObject:@{@"type" : @"Feature", @"id" : @(id), @"geometry" : line->geometry ?: @{}, @"properties" : @{}}];
    } else if (const auto *fill = std::get_if<FillAnnotation>(&annotation)) {
      [features addObject:@{@"type" : @"Feature", @"id" : @(id), @"geometry" : fill->geometry ?: @{}, @"properties" : @{}}];
    }
  }

  mln_map h = handle();
  NSString *json = MLNFFIJSONStringFromObject(@{@"type" : @"FeatureCollection", @"features" : features});
  mln_geo_json_source_data data = MLN_HANDLE_NULL;
  mln_geo_json_source_options sourceOptions = {sizeof(mln_geo_json_source_options)};
  if (mln_geo_json_source_data_create(MLNFFIBufferView(json), &sourceOptions, &data, nullptr) !=
      MLN_STATUS_OK) {
    MLNLogError(@"Failed to prepare the annotations");
    return;
  }
  NSMutableSet<NSString *> *existingLayers = [NSMutableSet set];
  for (MLNFFILayerInfo *info in layers) {
    [existingLayers addObject:info.identifier];
  }
  if (![map styleSourceWithIdentifier:AnnotationSourceID]) {
    [map perform:@"add the annotation source"
          submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
            return mln_map_add_geo_json_source_data(h, MLNFFIBufferView(AnnotationSourceID), data,
                                                    completion, diagnostic);
          }];
  } else {
    [map perform:@"update the annotations"
          submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
            return mln_map_set_geo_json_source_data(h, MLNFFIBufferView(AnnotationSourceID), data,
                                                    completion, diagnostic);
          }];
  }
  mln_geo_json_source_data_release(data);

  NSString *message;
  if (![existingLayers containsObject:PointLayerID]) {
    NSDictionary *pointLayer = @{
      @"id" : PointLayerID,
      @"type" : @"symbol",
      @"source" : AnnotationSourceID,
      @"source-layer" : PointLayerID,
      @"filter" : @[ @"==", @[ @"geometry-type" ], @"Point" ],
      @"layout" : @{
        @"icon-image" : @[ @"image", @[ @"concat", [AnnotationSourceID stringByAppendingString:@"."],
                                         @[ @"to-string", @[ @"get", @"sprite" ] ] ] ],
        @"icon-allow-overlap" : @YES,
        @"icon-ignore-placement" : @YES,
      },
    };
    if ([map addStyleLayerJSON:pointLayer belowLayer:nil message:&message] != MLN_STATUS_OK) {
      MLNLogError(@"Failed to add the annotation point layer: %@", message);
    }
  }

  // One layer per shape annotation, below the point layer (Line/Fill
  // AnnotationImpl::updateStyle()); removed annotations lose theirs.
  for (MLNFFILayerInfo *info in layers) {
    if (![info.identifier hasPrefix:ShapeLayerPrefix]) {
      continue;
    }
    AnnotationID id = strtoull([info.identifier substringFromIndex:ShapeLayerPrefix.length].UTF8String, nullptr, 10);
    if (!annotations.count(id) || std::holds_alternative<SymbolAnnotation>(annotations[id])) {
      [map removeStyleLayer:info.identifier message:nil];
    }
  }
  for (const auto &[id, annotation] : annotations) {
    NSString *layerID = ShapeLayerID(id);
    NSDictionary *paint;
    NSString *type;
    NSDictionary *layout = @{};
    if (const auto *line = std::get_if<LineAnnotation>(&annotation)) {
      type = @"line";
      layout = @{@"line-join" : @"round"};
      paint = @{
        @"line-opacity" : @(line->opacity),
        @"line-width" : @(line->width),
        @"line-color" : MLNStyleJSONFromColor(line->color ?: UIColor.blackColor),
      };
    } else if (const auto *fill = std::get_if<FillAnnotation>(&annotation)) {
      type = @"fill";
      paint = @{
        @"fill-opacity" : @(fill->opacity),
        @"fill-color" : MLNStyleJSONFromColor(fill->color ?: UIColor.blackColor),
        @"fill-outline-color" : MLNStyleJSONFromColor(fill->outlineColor ?: UIColor.blackColor),
      };
    } else {
      continue;
    }
    if (![existingLayers containsObject:layerID]) {
      NSDictionary *layer = @{
        @"id" : layerID,
        @"type" : type,
        @"source" : AnnotationSourceID,
        @"source-layer" : layerID,
        @"filter" : @[ @"==", @[ @"id" ], @(id) ],
        @"layout" : layout,
        @"paint" : paint,
      };
      if ([map addStyleLayerJSON:layer belowLayer:PointLayerID message:&message] != MLN_STATUS_OK) {
        MLNLogError(@"Failed to add annotation layer %@: %@", layerID, message);
      }
    } else {
      for (NSString *property in paint) {
        [map setStyleLayerProperty:property layer:layerID value:paint[property] message:nil];
      }
    }
  }
}

std::vector<AnnotationID> Map::queryPointAnnotations(const ScreenBox &box) const {
  mln_screen_point points[2] = {{box.min.x, box.min.y}, {box.max.x, box.max.y}};
  NSArray<NSDictionary *> *features = queryRenderedFeatures(
      points, 2, MLN_RENDERED_QUERY_GEOMETRY_TYPE_BOX, [NSSet setWithObject:PointLayerID], nil);
  std::vector<AnnotationID> ids;
  for (NSDictionary *feature in features) {
    NSNumber *tag = feature[@"id"];
    if ([tag isKindOfClass:[NSNumber class]] &&
        std::find(ids.begin(), ids.end(), tag.unsignedLongLongValue) == ids.end()) {
      ids.push_back(tag.unsignedLongLongValue);
    }
  }
  return ids;
}

std::vector<AnnotationID> Map::queryShapeAnnotations(const ScreenBox &box) const {
  NSMutableSet<NSString *> *shapeLayers = [NSMutableSet set];
  for (const auto &[id, annotation] : annotations) {
    if (!std::holds_alternative<SymbolAnnotation>(annotation)) {
      [shapeLayers addObject:ShapeLayerID(id)];
    }
  }
  if (!shapeLayers.count) {
    return {};
  }
  mln_screen_point points[2] = {{box.min.x, box.min.y}, {box.max.x, box.max.y}};
  NSArray<NSDictionary *> *features =
      queryRenderedFeatures(points, 2, MLN_RENDERED_QUERY_GEOMETRY_TYPE_BOX, shapeLayers, nil);
  std::vector<AnnotationID> ids;
  for (NSDictionary *feature in features) {
    NSNumber *tag = feature[@"id"];
    if ([tag isKindOfClass:[NSNumber class]] &&
        std::find(ids.begin(), ids.end(), tag.unsignedLongLongValue) == ids.end()) {
      ids.push_back(tag.unsignedLongLongValue);
    }
  }
  return ids;
}

// MARK: Queries

NSArray<NSDictionary *> *Map::queryRenderedFeatures(const ScreenCoordinate &point,
                                                    NSSet<NSString *> *layerIDs, id filter) const {
  mln_screen_point points[1] = {{point.x, point.y}};
  return queryRenderedFeatures(points, 1, MLN_RENDERED_QUERY_GEOMETRY_TYPE_POINT, layerIDs, filter);
}

NSArray<NSDictionary *> *Map::queryRenderedFeatures(const ScreenBox &box, NSSet<NSString *> *layerIDs,
                                                    id filter) const {
  mln_screen_point points[2] = {{box.min.x, box.min.y}, {box.max.x, box.max.y}};
  return queryRenderedFeatures(points, 2, MLN_RENDERED_QUERY_GEOMETRY_TYPE_BOX, layerIDs, filter);
}

NSArray<NSDictionary *> *Map::queryRenderedFeatures(mln_screen_point *points, size_t count,
                                                    uint32_t geometryType, NSSet<NSString *> *layerIDs,
                                                    id filter) const {
  mln_render_session session = renderSession;
  if (session == MLN_HANDLE_NULL) {
    return @[];
  }
  mln_rendered_query_geometry geometry = {sizeof(mln_rendered_query_geometry)};
  geometry.type = (mln_rendered_query_geometry_type)geometryType;
  if (geometryType == MLN_RENDERED_QUERY_GEOMETRY_TYPE_POINT) {
    geometry.data.point = points[0];
  } else {
    geometry.data.box = {points[0], points[1]};
  }
  NSArray<NSString *> *layers = layerIDs.allObjects;
  std::vector<mln_buffer_view> layerViews;
  for (NSString *layer in layers) {
    layerViews.push_back(MLNFFIBufferView(layer));
  }
  NSString *filterJSON = filter ? MLNFFIJSONStringFromObject(filter) : nil;
  mln_rendered_feature_query_options options = {sizeof(mln_rendered_feature_query_options)};
  if (layerIDs) {
    options.fields = MLN_RENDERED_FEATURE_QUERY_OPTION_LAYER_IDS;
    options.layer_ids = layerViews.data();
    options.layer_id_count = layerViews.size();
  }
  options.filter = MLNFFIBufferView(filterJSON);
  __block NSMutableArray *features = [NSMutableArray array];
  [map call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_render_session_query_rendered_features(session, &geometry, &options, completion,
                                                      diagnostic);
  }
      consume:^(const mln_completion_result *result) {
        for (size_t i = 0; i < result->value_count; i++) {
          const mln_rendered_feature *feature =
              MLN_STRIDED_AT(mln_rendered_feature, result->value, result->value_size, i);
          id json = MLNFFIJSONObjectFromBufferView(feature->feature);
          if ([json isKindOfClass:[NSDictionary class]]) {
            [features addObject:json];
          }
        }
      }
      message:nil];
  return features;
}

}  // namespace mln
