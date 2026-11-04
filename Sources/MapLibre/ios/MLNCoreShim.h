// The part of the C++ core's interface that MLNMapView.mm used, implemented on
// the C API, so the view's code (platform/ios/src/MLNMapView.mm at ios-v7.0.0)
// carries over with few changes.
//
// The value types (LatLng, EdgeInsets, CameraOptions, ...) mirror
// include/mln/util/geo.hpp, include/mln/map/camera.hpp and
// include/mln/map/bound_options.hpp at ios-v7.0.0. `mln::Map` forwards to an
// MLNFFIMap, and emulates the core's annotation manager, which the C API
// lacks, with GeoJSON sources and style layers (see C_API_GAPS.md).
//
// Only Objective-C++ files of this SDK include this header; the FFI framework
// exports no C++ symbols, so the names cannot collide with the core's.

#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "MLNCoreGeometry.h"
#import "MLNFFI.h"

#include <chrono>
#include <cmath>
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <variant>
#include <vector>

@class MLNFFIMap;
@class MLNStyle;

namespace mln {

using Duration = std::chrono::steady_clock::duration;

namespace util {

using ::MLNCoreWrap;

template <typename T>
T wrap(T value, T min, T max) {
  return MLNCoreWrap(value, min, max);
}

template <typename T>
T clamp(T value, T min_, T max_) {
  return std::max(min_, std::min(max_, value));
}

constexpr double LONGITUDE_MAX = 180;
constexpr double DEGREES_MAX = 360;
constexpr double PITCH_MAX = M_PI;
constexpr uint8_t DEFAULT_PREFETCH_ZOOM_DELTA = 4;

inline double rad2deg(double rad) { return rad * 180.0 / M_PI; }
inline double deg2rad(double deg) { return deg * M_PI / 180.0; }

struct UnitBezier {
  constexpr UnitBezier(double p1x, double p1y, double p2x, double p2y)
      : x1(p1x), y1(p1y), x2(p2x), y2(p2y) {}
  double x1, y1, x2, y2;
};

}  // namespace util

template <typename T>
struct Point {
  T x = 0;
  T y = 0;
  constexpr Point() = default;
  constexpr Point(T x_, T y_) : x(x_), y(y_) {}
  friend bool operator==(const Point &a, const Point &b) { return a.x == b.x && a.y == b.y; }
  friend bool operator!=(const Point &a, const Point &b) { return !(a == b); }
};

using ScreenCoordinate = Point<double>;

struct ScreenBox {
  ScreenCoordinate min;
  ScreenCoordinate max;
};

struct Size {
  uint32_t width = 0;
  uint32_t height = 0;
};

class LatLng {
 public:
  enum WrapMode : bool { Unwrapped, Wrapped };

  LatLng(double lat_ = 0, double lon_ = 0, WrapMode mode = Unwrapped) : lat(lat_), lon(lon_) {
    if (NSString *error = MLNCoreLatLngError(lat, lon)) {
      throw std::domain_error(error.UTF8String);
    }
    if (mode == Wrapped) {
      wrap();
    }
  }

  // Conversions to and from the C API, which MLNGeometry_Private.h uses.
  LatLng(const mln_lat_lng &latLng) : LatLng(latLng.latitude, latLng.longitude) {}
  operator mln_lat_lng() const { return {lat, lon}; }

  double latitude() const noexcept { return lat; }
  double longitude() const noexcept { return lon; }

  LatLng wrapped() const noexcept { return {lat, lon, Wrapped}; }

  void wrap() noexcept { lon = util::wrap(lon, -util::LONGITUDE_MAX, util::LONGITUDE_MAX); }

  void unwrapForShortestPath(const LatLng &end) noexcept {
    const double delta = std::abs(end.lon - lon);
    if (delta <= util::LONGITUDE_MAX || delta >= util::DEGREES_MAX) return;
    if (lon > 0 && end.lon < 0)
      lon -= util::DEGREES_MAX;
    else if (lon < 0 && end.lon > 0)
      lon += util::DEGREES_MAX;
  }

  friend bool operator==(const LatLng &a, const LatLng &b) { return a.lat == b.lat && a.lon == b.lon; }
  friend bool operator!=(const LatLng &a, const LatLng &b) { return !(a == b); }

 private:
  double lat;
  double lon;
};

class LatLngBounds {
 public:
  /// The whole world, as the core's default bounds.
  LatLngBounds() : sw(-90, -180), ne(90, 180) {}
  LatLngBounds(const mln_lat_lng_bounds &bounds)
      : sw(bounds.southwest.latitude, bounds.southwest.longitude),
        ne(bounds.northeast.latitude, bounds.northeast.longitude) {}
  operator mln_lat_lng_bounds() const { return {sw, ne}; }

  static LatLngBounds world() { return LatLngBounds(); }
  static LatLngBounds empty() {
    LatLngBounds bounds = world();
    std::swap(bounds.sw, bounds.ne);
    return bounds;
  }
  static LatLngBounds hull(const LatLng &a, const LatLng &b) {
    LatLngBounds bounds(a, a);
    bounds.extend(b);
    return bounds;
  }

  LatLng southwest() const { return sw; }
  LatLng northeast() const { return ne; }
  LatLng southeast() const { return LatLng(south(), east()); }
  LatLng northwest() const { return LatLng(north(), west()); }
  double south() const { return sw.latitude(); }
  double west() const { return sw.longitude(); }
  double north() const { return ne.latitude(); }
  double east() const { return ne.longitude(); }

  bool valid() const { return sw.latitude() <= ne.latitude() && sw.longitude() <= ne.longitude(); }

  void extend(const LatLngBounds &bounds) {
    extend(bounds.sw);
    extend(bounds.ne);
  }

  void extend(const LatLng &point) {
    sw = LatLng(std::min(point.latitude(), sw.latitude()), std::min(point.longitude(), sw.longitude()));
    ne = LatLng(std::max(point.latitude(), ne.latitude()), std::max(point.longitude(), ne.longitude()));
  }

  friend bool operator==(const LatLngBounds &a, const LatLngBounds &b) {
    return a.sw == b.sw && a.ne == b.ne;
  }
  friend bool operator!=(const LatLngBounds &a, const LatLngBounds &b) { return !(a == b); }

 private:
  LatLngBounds(LatLng sw_, LatLng ne_) : sw(sw_), ne(ne_) {}
  LatLng sw;
  LatLng ne;
};

class EdgeInsets {
 public:
  EdgeInsets() = default;
  EdgeInsets(double t_, double l_, double b_, double r_) : _top(t_), _left(l_), _bottom(b_), _right(r_) {}
  EdgeInsets(const mln_edge_insets &insets)
      : _top(insets.top), _left(insets.left), _bottom(insets.bottom), _right(insets.right) {}
  operator mln_edge_insets() const { return {_top, _left, _bottom, _right}; }

  double top() const { return _top; }
  double left() const { return _left; }
  double bottom() const { return _bottom; }
  double right() const { return _right; }

  bool isFlush() const { return _top == 0 && _left == 0 && _bottom == 0 && _right == 0; }

  void operator+=(const EdgeInsets &o) {
    _top += o._top;
    _left += o._left;
    _bottom += o._bottom;
    _right += o._right;
  }

  friend bool operator==(const EdgeInsets &a, const EdgeInsets &b) {
    return a._top == b._top && a._left == b._left && a._bottom == b._bottom && a._right == b._right;
  }
  friend bool operator!=(const EdgeInsets &a, const EdgeInsets &b) { return !(a == b); }

 private:
  double _top = 0;
  double _left = 0;
  double _bottom = 0;
  double _right = 0;
};

struct CameraOptions {
  CameraOptions &withCenter(const std::optional<LatLng> &o) { center = o; return *this; }
  CameraOptions &withPadding(const std::optional<EdgeInsets> &p) { padding = p; return *this; }
  CameraOptions &withAnchor(const std::optional<ScreenCoordinate> &o) { anchor = o; return *this; }
  CameraOptions &withZoom(const std::optional<double> &o) { zoom = o; return *this; }
  CameraOptions &withBearing(const std::optional<double> &o) { bearing = o; return *this; }
  CameraOptions &withPitch(const std::optional<double> &o) { pitch = o; return *this; }
  CameraOptions &withRoll(const std::optional<double> &o) { roll = o; return *this; }
  CameraOptions &withFov(const std::optional<double> &o) { fov = o; return *this; }

  std::optional<LatLng> center;
  std::optional<EdgeInsets> padding;
  std::optional<ScreenCoordinate> anchor;
  std::optional<double> zoom;
  std::optional<double> bearing;
  std::optional<double> pitch;
  std::optional<double> roll;
  std::optional<double> fov;
};

struct AnimationOptions {
  std::optional<Duration> duration;
  std::optional<double> velocity;
  std::optional<double> minZoom;
  std::optional<util::UnitBezier> easing;
  /// The C API reports no per-frame transition callback; never called.
  std::function<void(double)> transitionFrameFn;
  /// Called on the main thread when the transition completes, is cancelled or
  /// is replaced, as the core's transitionFinishFn was.
  std::function<void()> transitionFinishFn;

  AnimationOptions() = default;
  AnimationOptions(Duration d) : duration(d) {}
};

struct BoundOptions {
  BoundOptions &withLatLngBounds(LatLngBounds b) { bounds = b; return *this; }
  BoundOptions &withMinZoom(double z) { minZoom = z; return *this; }
  BoundOptions &withMaxZoom(double z) { maxZoom = z; return *this; }
  BoundOptions &withMinPitch(double p) { minPitch = p; return *this; }
  BoundOptions &withMaxPitch(double p) { maxPitch = p; return *this; }

  std::optional<LatLngBounds> bounds;
  std::optional<double> maxZoom;
  std::optional<double> minZoom;
  std::optional<double> maxPitch;
  std::optional<double> minPitch;
};

enum class ConstrainMode : uint8_t { None, HeightOnly, WidthAndHeight, Screen };
enum class ViewportMode : uint8_t { Default, FlippedY };
enum class NorthOrientation : uint8_t { Upwards, Rightwards, Downwards, Leftwards };

enum class MapDebugOptions : uint32_t {
  NoDebug = 0,
  TileBorders = 1 << 1,
  ParseStatus = 1 << 2,
  Timestamps = 1 << 3,
  Collision = 1 << 4,
  Overdraw = 1 << 5,
  StencilClip = 1 << 6,
  DepthBuffer = 1 << 7,
};

constexpr MapDebugOptions operator|(MapDebugOptions lhs, MapDebugOptions rhs) {
  return MapDebugOptions(uint32_t(lhs) | uint32_t(rhs));
}
constexpr MapDebugOptions &operator|=(MapDebugOptions &lhs, MapDebugOptions rhs) {
  return (lhs = lhs | rhs);
}
constexpr bool operator&(MapDebugOptions lhs, MapDebugOptions rhs) {
  return uint32_t(lhs) & uint32_t(rhs);
}
constexpr MapDebugOptions &operator&=(MapDebugOptions &lhs, MapDebugOptions rhs) {
  return (lhs = MapDebugOptions(uint32_t(lhs) & uint32_t(rhs)));
}
constexpr MapDebugOptions operator~(MapDebugOptions value) {
  return MapDebugOptions(~uint32_t(value));
}

class MapOptions {
 public:
  ConstrainMode constrainMode() const { return _constrainMode; }
  MapOptions &withConstrainMode(ConstrainMode mode) {
    _constrainMode = mode;
    return *this;
  }

 private:
  ConstrainMode _constrainMode = ConstrainMode::HeightOnly;
};

class ProjectedMeters {
 public:
  ProjectedMeters(double northing_ = 0, double easting_ = 0) : _northing(northing_), _easting(easting_) {}
  double northing() const { return _northing; }
  double easting() const { return _easting; }

 private:
  double _northing;
  double _easting;
};

class Projection {
 public:
  static double getMetersPerPixelAtLatitude(double lat, double zoom) {
    return MLNCoreMetersPerPixelAtLatitude(lat, zoom);
  }
  static ProjectedMeters projectedMetersForLatLng(const LatLng &latLng) {
    mln_projected_meters meters = {};
    mln_projected_meters_for_lat_lng({latLng.latitude(), latLng.longitude()}, &meters, nullptr);
    return {meters.northing, meters.easting};
  }
};

// MARK: - Annotations

using AnnotationID = uint64_t;

/// A shape annotation's geometry as a GeoJSON geometry object.
using ShapeAnnotationGeometry = NSDictionary *;

struct SymbolAnnotation {
  Point<double> geometry;
  std::string icon;
};

struct LineAnnotation {
  ShapeAnnotationGeometry geometry;
  float opacity = 1;
  float width = 1;
  UIColor *color;
};

struct FillAnnotation {
  ShapeAnnotationGeometry geometry;
  float opacity = 1;
  UIColor *color;
  UIColor *outlineColor;
};

using Annotation = std::variant<SymbolAnnotation, LineAnnotation, FillAnnotation>;

// MARK: - Map

/// Forwards the core's Map interface to a C API map. Camera commands block
/// until the map applied them, so its events reach the view during the call.
class Map {
 public:
  explicit Map(MLNFFIMap *map);
  ~Map();

  MLNFFIMap *ffiMap() const { return map; }

  /// The render session, once the view attached one. Resizing and queries go
  /// through it.
  void setRenderSession(mln_render_session session) { renderSession = session; }
  mln_render_session getRenderSession() const { return renderSession; }

  // Style
  std::string getStyleURL() const;
  std::string getStyleJSON() const;
  void loadStyleURL(const std::string &url);
  void loadStyleJSON(const std::string &json);
  /// The style's default camera, read from the loaded document; the C API
  /// has no getter for it.
  CameraOptions getStyleDefaultCamera() const;

  // Camera
  CameraOptions getCameraOptions(const std::optional<EdgeInsets> &padding = {}) const;
  void jumpTo(const CameraOptions &camera);
  void easeTo(const CameraOptions &camera, const AnimationOptions &animation);
  void flyTo(const CameraOptions &camera, const AnimationOptions &animation);
  void moveBy(const ScreenCoordinate &offset, const AnimationOptions &animation = {});
  void cancelTransitions();
  void setGestureInProgress(bool inProgress);
  bool isGestureInProgress() const;

  CameraOptions cameraForLatLngBounds(const LatLngBounds &bounds, const EdgeInsets &padding,
                                      const std::optional<double> &bearing = std::nullopt,
                                      const std::optional<double> &pitch = std::nullopt) const;
  CameraOptions cameraForLatLngs(const std::vector<LatLng> &latLngs, const EdgeInsets &padding,
                                 const std::optional<double> &bearing = std::nullopt,
                                 const std::optional<double> &pitch = std::nullopt) const;
  CameraOptions cameraForGeometry(id geometry, const EdgeInsets &padding,
                                  const std::optional<double> &bearing = std::nullopt,
                                  const std::optional<double> &pitch = std::nullopt) const;
  LatLngBounds latLngBoundsForCamera(const CameraOptions &camera) const;

  void setBounds(const BoundOptions &options);
  BoundOptions getBounds() const;

  ScreenCoordinate pixelForLatLng(const LatLng &latLng) const;
  LatLng latLngForPixel(const ScreenCoordinate &pixel) const;

  // Size and options
  void setSize(Size size);
  const MapOptions &getMapOptions() const { return options; }
  void setConstrainMode(ConstrainMode mode);
  void setViewportMode(ViewportMode mode);
  void setFrustumOffset(const EdgeInsets &offset);
  EdgeInsets getFrustumOffset() const;

  // Debug and tiles
  void setDebug(MapDebugOptions debug);
  MapDebugOptions getDebug() const;
  void setPrefetchZoomDelta(uint8_t delta);
  uint8_t getPrefetchZoomDelta() const;
  void setTileLodMinRadius(double radius);
  double getTileLodMinRadius() const;
  void setTileLodScale(double scale);
  double getTileLodScale() const;
  void setTileLodPitchThreshold(double threshold);
  double getTileLodPitchThreshold() const;
  void setTileLodZoomShift(double shift);
  double getTileLodZoomShift() const;
  void enableRenderingStatsView(bool enabled);
  bool isRenderingStatsViewEnabled() const;
  void triggerRepaint();
  bool isFullyLoaded() const;

  // Annotations, emulated with style sources and layers.
  AnnotationID addAnnotation(const Annotation &annotation);
  void updateAnnotation(AnnotationID id, const Annotation &annotation);
  void removeAnnotation(AnnotationID id);
  void addAnnotationImage(NSString *name, UIImage *image);
  void removeAnnotationImage(NSString *name);
  /// Recreates the annotation sources, layers and images in a newly loaded
  /// style, as the core's annotation manager did.
  void restoreAnnotationsAfterStyleLoad();
  std::vector<AnnotationID> queryPointAnnotations(const ScreenBox &box) const;
  std::vector<AnnotationID> queryShapeAnnotations(const ScreenBox &box) const;

  // Queries on the render session; features as GeoJSON Feature objects.
  NSArray<NSDictionary *> *queryRenderedFeatures(const ScreenCoordinate &point, NSSet<NSString *> *layerIDs,
                                                 id filter) const;
  NSArray<NSDictionary *> *queryRenderedFeatures(const ScreenBox &box, NSSet<NSString *> *layerIDs,
                                                 id filter) const;

 private:
  mln_map handle() const;
  mln_map_snapshot snapshot() const;
  void updateCamera(mln_camera_update_mode mode, const CameraOptions &camera,
                    const AnimationOptions &animation);
  mln_gesture_phase nextGesturePhase();
  void setTileOptions(mln_map_tile_options options);
  void flushAnnotations();
  NSArray<NSDictionary *> *queryRenderedFeatures(mln_screen_point *points, size_t count,
                                                 uint32_t geometryType, NSSet<NSString *> *layerIDs,
                                                 id filter) const;

  MLNFFIMap *map;
  mln_render_session renderSession = MLN_HANDLE_NULL;
  MapOptions options;
  bool gestureInProgress = false;
  bool gestureBegun = false;

  AnnotationID nextAnnotationID = 0;
  std::map<AnnotationID, Annotation> annotations;
  NSMutableDictionary<NSString *, UIImage *> *annotationImages;
  bool annotationsDirty = false;
};

}  // namespace mln

inline mln::Point<double> MLNPointFromLocationCoordinate2D(CLLocationCoordinate2D coordinate) {
  return mln::Point<double>(coordinate.longitude, coordinate.latitude);
}

/// Converts from a duration in seconds to the core's duration type.
inline mln::Duration MLNDurationFromTimeInterval(NSTimeInterval duration) {
  return std::chrono::duration_cast<mln::Duration>(std::chrono::duration<NSTimeInterval>(duration));
}

inline NSTimeInterval MLNTimeIntervalFromDuration(mln::Duration duration) {
  return std::chrono::duration<NSTimeInterval, std::ratio<1>>(duration).count();
}
