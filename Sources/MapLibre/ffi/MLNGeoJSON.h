// GeoJSON conversion between Foundation objects and MLNShape/MLNFeature.
//
// Classic MapLibre iOS parsed and produced GeoJSON with mapbox::geojson and
// converted mbgl::Feature values. The C API takes and returns GeoJSON text, so
// these functions do the conversion in Objective-C, with the same results.

#import <Foundation/Foundation.h>

#import "MLNFeature.h"
#import "MLNShape.h"

NS_ASSUME_NONNULL_BEGIN

/**
 The shape for a parsed GeoJSON object (a geometry, Feature or
 FeatureCollection), as MLNShapeFromGeoJSON did. Returns nil and sets `error`
 for invalid GeoJSON.
 */
FOUNDATION_EXTERN MLNShape *_Nullable MLNShapeFromGeoJSONObject(id object,
                                                                NSError *_Nullable *_Nullable error);

/**
 The feature for a GeoJSON Feature object, as MLNFeatureFromMBGLFeature did:
 the geometry type picks the class, `id` becomes the identifier, and
 properties become attributes. Cluster features (with `cluster: true`) become
 the MLNCluster classes.
 */
FOUNDATION_EXTERN id<MLNFeature> MLNFeatureFromGeoJSONFeature(NSDictionary *feature);

/// Features for GeoJSON Feature objects, as MLNFeaturesFromMBGLFeatures did.
FOUNDATION_EXTERN NSArray<MLNShape<MLNFeature> *> *MLNFeaturesFromGeoJSONFeatures(
    NSArray<NSDictionary *> *features);

/// The GeoJSON object for a shape: its `geoJSONDictionary`.
FOUNDATION_EXTERN NSDictionary *MLNGeoJSONObjectFromShape(MLNShape *shape);

/// The GeoJSON text for a shape, as the C API takes it.
FOUNDATION_EXTERN NSString *MLNGeoJSONStringFromShape(MLNShape *shape);

NS_ASSUME_NONNULL_END
