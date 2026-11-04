// Based on platform/darwin/src/MLNOfflinePack_Private.h at ios-v7.0.0
//
// Classic packs wrapped an mbgl::OfflineRegion and observed it through an
// mbgl::OfflineRegionObserver. Here a pack holds a copy of the C API's region
// record, and MLNOfflineStorage routes the runtime's offline region events to
// it.

#import <MaplibreNativeC/maplibre_native_c.h>

#import "MLNOfflinePack.h"

NS_ASSUME_NONNULL_BEGIN

@class MLNFFIOfflineRegionInfo;

@interface MLNOfflinePack (Private)

/// The region record, or nil once the pack is invalid.
@property (nonatomic, nullable) MLNFFIOfflineRegionInfo *mgl_regionInfo;

@property (nonatomic, readwrite) MLNOfflinePackState state;

- (instancetype)initWithRegionInfo:(MLNFFIOfflineRegionInfo *)regionInfo;

/**
 Invalidates the pack and ensures that no future progress update can ever
 revalidate it. This method must be called before the pack is deallocated.
 */
- (void)invalidate;

// Runtime events for the pack's region, on the main thread.
- (void)offlineRegionStatusDidChange:(mln_offline_region_status)status;
- (void)didReceiveError:(NSError *)error;
- (void)didReceiveMaximumAllowedMapboxTiles:(uint64_t)limit;

@end

/// The NSError for an offline response error, as MLNErrorFromResponseError
/// built it from mbgl::Response::Error.
FOUNDATION_EXTERN NSError *MLNErrorFromResponseErrorReason(mln_resource_error_reason reason,
                                                           NSString *message);

NS_ASSUME_NONNULL_END
