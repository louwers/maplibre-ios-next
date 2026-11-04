// Small pieces of the core's geometry utilities (include/mln/util/constants.hpp,
// geo.hpp, projection.hpp, math.hpp at ios-v7.0.0) that classic MapLibre iOS
// called directly. The C API exposes the projection only through a map's
// projection handle, so pure math that needs no map is ported here.

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#include <math.h>

NS_ASSUME_NONNULL_BEGIN

static const double MLNCoreTileSize = 512;
static const double MLNCoreEarthRadiusMeters = 6378137;
static const double MLNCoreLatitudeMax = 85.051128779806604;
static const double MLNCoreLongitudeMax = 180;
static const double MLNCoreDegreesMax = 360;
static const double MLNCoreMinZoom = 0.0;
static const double MLNCoreMaxZoom = 25.5;
static const double MLNCoreDefaultMaxZoom = 22;
static const double MLNCoreDefaultPitchMax = M_PI / 3;
static const double MLNCorePitchMax = M_PI;

NS_INLINE double MLNCoreClamp(double value, double min, double max) {
  return value < min ? min : (value > max ? max : value);
}

/// util::wrap: wraps value into [min, max).
NS_INLINE double MLNCoreWrap(double value, double min, double max) {
  if (value >= min && value < max) {
    return value;
  } else if (value == max) {
    return min;
  }
  const double delta = max - min;
  const double wrapped = min + fmod(value - min, delta);
  return value < min ? wrapped + delta : wrapped;
}

/// The message mln::LatLng throws for an invalid coordinate, or nil.
NS_INLINE NSString *_Nullable MLNCoreLatLngError(double latitude, double longitude) {
  if (isnan(latitude)) {
    return @"latitude must not be NaN";
  }
  if (isnan(longitude)) {
    return @"longitude must not be NaN";
  }
  if (fabs(latitude) > 90.0) {
    return @"latitude must be between -90 and 90";
  }
  if (!isfinite(longitude)) {
    return @"longitude must not be infinite";
  }
  return nil;
}

/// Projection::getMetersPerPixelAtLatitude
NS_INLINE double MLNCoreMetersPerPixelAtLatitude(double latitude, double zoom) {
  const double constrainedZoom = MLNCoreClamp(zoom, MLNCoreMinZoom, MLNCoreMaxZoom);
  const double constrainedScale = pow(2.0, constrainedZoom);
  const double constrainedLatitude = MLNCoreClamp(latitude, -MLNCoreLatitudeMax, MLNCoreLatitudeMax);
  return cos(constrainedLatitude * M_PI / 180.0) * M_PI * 2 * MLNCoreEarthRadiusMeters /
         (constrainedScale * MLNCoreTileSize);
}

/// Projection::project, in pixels at the given scale.
NS_INLINE CGPoint MLNCoreProject(CLLocationCoordinate2D coordinate, double scale) {
  const double worldSize = scale * MLNCoreTileSize;
  const double latitude = MLNCoreClamp(coordinate.latitude, -MLNCoreLatitudeMax, MLNCoreLatitudeMax);
  const double x = MLNCoreLongitudeMax + coordinate.longitude;
  const double y = MLNCoreLongitudeMax - (log(tan(M_PI / 4 + latitude * M_PI / MLNCoreDegreesMax)) *
                                          180.0 / M_PI);
  return CGPointMake(x * worldSize / MLNCoreDegreesMax, y * worldSize / MLNCoreDegreesMax);
}

NS_ASSUME_NONNULL_END
