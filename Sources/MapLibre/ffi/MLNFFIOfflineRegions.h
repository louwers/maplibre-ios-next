// Copies of the C API's offline region records, and region definitions for
// creating regions, built on the region classes' C API conversions
// (MLNOfflineRegion_Private.h).

#import <Foundation/Foundation.h>
#import <MaplibreNativeC/maplibre_native_c.h>

#import "MLNOfflineRegion.h"

NS_ASSUME_NONNULL_BEGIN

/// A copy of one `mln_offline_region_info`.
@interface MLNFFIOfflineRegionInfo : NSObject
@property (nonatomic) mln_offline_region_id identifier;
@property (nonatomic, copy) NSData *metadata;
/// The region the definition describes, or nil if it cannot be represented.
@property (nonatomic, strong, nullable) id<MLNOfflineRegion> region;
@end

/// Copies a borrowed region record.
FOUNDATION_EXTERN MLNFFIOfflineRegionInfo *MLNFFIOfflineRegionInfoFromC(
    const mln_offline_region_info *info);

/**
 Calls `block` with the C API definition of a region, valid for the duration of
 the block. Returns NO without calling it for region types that are not
 MLNOfflineRegion_Private, which classic rejected too.
 */
FOUNDATION_EXTERN BOOL MLNFFIWithOfflineRegionDefinition(
    id<MLNOfflineRegion> region, void (^block)(const mln_offline_region_definition *definition));

NS_ASSUME_NONNULL_END
