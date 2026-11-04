// Based on platform/darwin/src/MLNShape_Private.h at ios-v7.0.0
//
// Classic converted shapes to mbgl::GeoJSON and mbgl::Geometry objects. The C
// API takes GeoJSON text, so these return the Foundation objects that
// NSJSONSerialization writes as the same GeoJSON.

#import "MLNShape.h"

#ifdef __cplusplus
bool operator==(const CLLocationCoordinate2D lhs, const CLLocationCoordinate2D rhs);
#endif

NS_ASSUME_NONNULL_BEGIN

@interface MLNShape (Private)

/**
 Returns the GeoJSON object that represents the ``MLNShape`` as classic's
 `mln::GeoJSON` did: a geometry object for a plain shape, a Feature object for a
 feature, and a FeatureCollection object for an ``MLNShapeCollectionFeature``.
 */
- (id)geoJSONObject;

/**
 Returns the GeoJSON geometry object of the ``MLNShape``, as classic's
 `mln::Geometry<double>` did: the geometry without a feature's identifier and
 attributes, or NSNull for an empty geometry.
 */
- (id)geometryObject;

/**
 Returns a dictionary with the GeoJSON geometry member object.
 */
- (NSDictionary *)geoJSONDictionary;

@end

NS_ASSUME_NONNULL_END
