// Based on platform/darwin/src/MLNShapeOfflineRegion_Private.h at ios-v7.0.0

#import <Foundation/Foundation.h>

#import <MaplibreNativeC/maplibre_native_c.h>

#import "MLNOfflineRegion.h"

NS_ASSUME_NONNULL_BEGIN

@protocol MLNShapeOfflineRegion_Private <MLNOfflineRegion>

/**
 Initializes and returns an offline region for the given C API region
 definition, whose geometry is GeoJSON text.

 @param definition An offline region definition reported by the C API.
 */
- (instancetype)initWithOfflineRegionDefinition:
    (const mln_offline_geometry_region_definition *)definition;

@end

NS_ASSUME_NONNULL_END
