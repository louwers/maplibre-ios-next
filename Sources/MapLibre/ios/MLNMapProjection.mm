// Based on platform/ios/src/MLNMapProjection.mm at ios-v7.0.0
//
// mln::MapProjection copied the map's transform; the C API's map projection
// handle is the same idea, built from the map's latest view.

#import "MLNFFI.h"
#import "MLNGeometry_Private.h"
#import "MLNMapProjection.h"
#import "MLNMapView_Private.h"

#import "MLNCoreShim.h"

@interface MLNMapProjection ()

@property (nonatomic) CGSize mapFrameSize;

@end

@implementation MLNMapProjection {
  mln_map_projection _projection;
  MLNFFIMap *_map;
}

- (instancetype)initWithMapView:(MLNMapView *)mapView {
  if (self = [super init]) {
    _map = [mapView ffiMap];
    mln_map_snapshot snapshot = [_map snapshot];
    mln_map_projection_create(&snapshot.view, &_projection, NULL);
    self.mapFrameSize = mapView.frame.size;
  }
  return self;
}

- (void)dealloc {
  if (_projection != MLN_HANDLE_NULL) {
    mln_map_projection_release(_projection);
  }
}

- (mln_camera_options)mgl_camera {
  mln_map_projection_camera_result result = {sizeof(mln_map_projection_camera_result)};
  mln_map_projection_get_camera(_projection, &result, NULL);
  mln_camera_options camera = {sizeof(mln_camera_options)};
  camera.fields = MLN_CAMERA_OPTION_CENTER | MLN_CAMERA_OPTION_CENTER_ALTITUDE |
                  MLN_CAMERA_OPTION_PADDING | MLN_CAMERA_OPTION_ZOOM | MLN_CAMERA_OPTION_BEARING |
                  MLN_CAMERA_OPTION_PITCH | MLN_CAMERA_OPTION_ROLL | MLN_CAMERA_OPTION_FOV;
  camera.center = result.camera.center;
  camera.center_altitude = result.camera.center_altitude;
  camera.padding = result.camera.padding;
  camera.zoom = result.camera.zoom;
  camera.bearing = result.camera.bearing;
  camera.pitch = result.camera.pitch;
  camera.roll = result.camera.roll;
  camera.field_of_view = result.camera.field_of_view;
  return camera;
}

- (MLNMapCamera *)camera {
  mln_camera_options cameraOptions = [self mgl_camera];
  CLLocationCoordinate2D centerCoordinate = MLNLocationCoordinate2DFromLatLng(cameraOptions.center);
  double zoomLevel = cameraOptions.zoom;
  CLLocationDirection direction = mln::util::wrap(cameraOptions.bearing, 0., 360.);
  CGFloat pitch = cameraOptions.pitch;
  CLLocationDistance altitude =
      MLNAltitudeForZoomLevel(zoomLevel, pitch, centerCoordinate.latitude, self.mapFrameSize);
  return [MLNMapCamera cameraLookingAtCenterCoordinate:centerCoordinate
                                              altitude:altitude
                                                 pitch:pitch
                                               heading:direction];
}

- (void)setCamera:(MLNMapCamera *_Nonnull)camera withEdgeInsets:(UIEdgeInsets)insets {
  mln_camera_options cameraOptions = {sizeof(mln_camera_options)};
  if (CLLocationCoordinate2DIsValid(camera.centerCoordinate)) {
    cameraOptions.fields |= MLN_CAMERA_OPTION_CENTER;
    cameraOptions.center = MLNLatLngFromLocationCoordinate2D(camera.centerCoordinate);
  }
  cameraOptions.fields |= MLN_CAMERA_OPTION_PADDING | MLN_CAMERA_OPTION_ZOOM | MLN_CAMERA_OPTION_ROLL;
  cameraOptions.padding = MLNEdgeInsetsFromNSEdgeInsets(insets);
  cameraOptions.zoom = MLNZoomLevelForAltitude(camera.altitude, camera.pitch,
                                               camera.centerCoordinate.latitude, self.mapFrameSize);
  if (camera.heading >= 0) {
    cameraOptions.fields |= MLN_CAMERA_OPTION_BEARING;
    cameraOptions.bearing = camera.heading;
  }
  if (camera.pitch >= 0) {
    cameraOptions.fields |= MLN_CAMERA_OPTION_PITCH;
    cameraOptions.pitch = camera.pitch;
  }
  cameraOptions.roll = camera.roll;
  mln_map_projection_set_camera(_projection, &cameraOptions, NULL);
}

// mln::MapProjection fitted the coordinates with its own transform. The C API
// projection cannot fit, so this asks the map for the fitting camera with the
// projection's bearing and pitch (C_API_GAPS.md).
- (void)setVisibleCoordinateBounds:(MLNCoordinateBounds)bounds edgePadding:(UIEdgeInsets)insets {
  CLLocationCoordinate2D coordinates[] = {
      {bounds.ne.latitude, bounds.sw.longitude},
      bounds.sw,
      {bounds.sw.latitude, bounds.ne.longitude},
      bounds.ne,
  };
  std::vector<mln_lat_lng> coordinateList;
  for (NSUInteger i = 0; i < 4; i++) {
    coordinateList.push_back({coordinates[i].latitude, coordinates[i].longitude});
  }
  const mln_lat_lng *latLngs = coordinateList.data();
  mln_camera_options current = [self mgl_camera];
  mln_camera_fit_options fit = {sizeof(mln_camera_fit_options)};
  fit.fields = MLN_CAMERA_FIT_OPTION_PADDING | MLN_CAMERA_FIT_OPTION_BEARING | MLN_CAMERA_FIT_OPTION_PITCH;
  fit.padding = MLNEdgeInsetsFromNSEdgeInsets(insets);
  fit.bearing = current.bearing;
  fit.pitch = current.pitch;
  mln_map handle = _map.handle;
  __block mln_camera_options camera = {sizeof(mln_camera_options)};
  __block BOOL found = NO;
  [_map call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_camera_for_lat_lngs(handle, latLngs, 4, &fit, completion, diagnostic);
  }
      consume:^(const mln_completion_result *result) {
        if (result->value) {
          camera = *(const mln_camera_options *)result->value;
          found = YES;
        }
      }
      message:nil];
  if (!found) {
    return;
  }
  mln_camera_options options = {sizeof(mln_camera_options)};
  options.fields = MLN_CAMERA_OPTION_CENTER | MLN_CAMERA_OPTION_ZOOM | MLN_CAMERA_OPTION_BEARING |
                   MLN_CAMERA_OPTION_PITCH | MLN_CAMERA_OPTION_PADDING;
  options.center = camera.center;
  options.zoom = camera.zoom;
  options.bearing = camera.bearing;
  options.pitch = camera.pitch;
  options.padding = MLNEdgeInsetsFromNSEdgeInsets(insets);
  mln_map_projection_set_camera(_projection, &options, NULL);
}

- (CLLocationCoordinate2D)convertPoint:(CGPoint)point {
  mln_lat_lng latLng = {};
  mln_map_projection_lat_lng_for_pixel(_projection, {point.x, point.y}, &latLng, NULL);
  return MLNLocationCoordinate2DFromLatLng(mln::LatLng(latLng).wrapped());
}

- (CGPoint)convertCoordinate:(CLLocationCoordinate2D)coordinate {
  if (!CLLocationCoordinate2DIsValid(coordinate)) {
    return CGPointMake(NAN, NAN);
  }
  mln_lat_lng latLng = MLNLatLngFromLocationCoordinate2D(coordinate);
  mln_screen_point pixel = {};
  mln_map_projection_pixel_for_lat_lng(_projection, latLng, &pixel, NULL);
  return CGPointMake(pixel.x, pixel.y);
}

- (CLLocationDistance)metersPerPoint {
  mln_camera_options cameraOptions = [self mgl_camera];
  return mln::Projection::getMetersPerPixelAtLatitude(cameraOptions.center.latitude,
                                                      cameraOptions.zoom);
}

@end
