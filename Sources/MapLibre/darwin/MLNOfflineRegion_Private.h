// Based on platform/darwin/src/MLNOfflineRegion_Private.h at ios-v7.0.0
//
// Classic converted regions to and from mln::OfflineRegionDefinition. The C API
// takes an mln_offline_region_definition, whose strings are buffer views.

#import <Foundation/Foundation.h>

#import <MaplibreNativeC/maplibre_native_c.h>

#import "MLNOfflineRegion.h"

NS_ASSUME_NONNULL_BEGIN

@protocol MLNOfflineRegion_Private <MLNOfflineRegion>

/**
 Returns the definition to pass to mln_runtime_create_offline_region(), as
 classic's offlineRegionDefinition built the mln::OfflineRegionDefinition (with
 the main screen's scale as pixel ratio). Its buffer views (style URL and, for
 shape regions, the GeoJSON geometry) point into data the receiver keeps, so
 the definition stays valid as long as the receiver does.
 */
- (mln_offline_region_definition)mgl_offlineRegionDefinition;

/**
 Attributes to be passed into the offline download start event
 */
@property (nonatomic, readonly) NSDictionary *offlineStartEventAttributes;

@end

/**
 Returns the region for a definition the C API reported (an
 ``MLNTilePyramidOfflineRegion`` or an ``MLNShapeOfflineRegion``), as classic's
 initWithOfflineRegionDefinition: initializers created them, or nil for an
 unknown definition type.
 */
FOUNDATION_EXTERN id<MLNOfflineRegion> _Nullable MLNOfflineRegionFromDefinition(
    const mln_offline_region_definition *definition);

NS_ASSUME_NONNULL_END
