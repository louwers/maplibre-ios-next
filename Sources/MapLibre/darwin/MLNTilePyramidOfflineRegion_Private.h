// Based on platform/darwin/src/MLNTilePyramidOfflineRegion_Private.h at ios-v7.0.0

#import <Foundation/Foundation.h>

#import <MaplibreNativeC/maplibre_native_c.h>

#import "MLNOfflineRegion.h"

NS_ASSUME_NONNULL_BEGIN

@protocol MLNTilePyramidOfflineRegion_Private <MLNOfflineRegion>

/**
 Initializes and returns an offline region for the given C API region
 definition.

 @param definition An offline region definition reported by the C API.
 */
- (instancetype)initWithOfflineRegionDefinition:
    (const mln_offline_tile_pyramid_region_definition *)definition;

@end

NS_ASSUME_NONNULL_END
