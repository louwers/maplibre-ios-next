// mln::LatLngBounds::empty() and extend() (include/mln/util/geo.hpp at
// ios-v7.0.0) on the C API's bounds type, for the shape classes that
// accumulated bounds with them.

#import <MaplibreNativeC/maplibre_native_c.h>

#import "MLNGeometry_Private.h"

#include <algorithm>

/// A bounds that serves as the identity element for the extend operation.
NS_INLINE mln_lat_lng_bounds MLNLatLngBoundsEmpty(void) { return {{90, 180}, {-90, -180}}; }

NS_INLINE void MLNLatLngBoundsExtend(mln_lat_lng_bounds &bounds, mln_lat_lng point) {
  bounds.southwest = {std::min(point.latitude, bounds.southwest.latitude),
                      std::min(point.longitude, bounds.southwest.longitude)};
  bounds.northeast = {std::max(point.latitude, bounds.northeast.latitude),
                      std::max(point.longitude, bounds.northeast.longitude)};
}

NS_INLINE void MLNLatLngBoundsExtendBounds(mln_lat_lng_bounds &bounds, mln_lat_lng_bounds other) {
  MLNLatLngBoundsExtend(bounds, other.southwest);
  MLNLatLngBoundsExtend(bounds, other.northeast);
}
