#import "MLNFFIOfflineRegions.h"

#import "MLNFFI.h"
#import "MLNLoggingConfiguration_Private.h"
#import "MLNOfflineRegion_Private.h"

@implementation MLNFFIOfflineRegionInfo
@end

MLNFFIOfflineRegionInfo *MLNFFIOfflineRegionInfoFromC(const mln_offline_region_info *info) {
  MLNFFIOfflineRegionInfo *copy = [MLNFFIOfflineRegionInfo new];
  copy.identifier = info->id;
  copy.metadata = info->metadata ? [NSData dataWithBytes:info->metadata length:info->metadata_size]
                                 : [NSData data];
  @try {
    copy.region = MLNOfflineRegionFromDefinition(&info->definition);
  } @catch (NSException *exception) {
    MLNLogError(@"Offline region %lld cannot be represented: %@", info->id, exception.reason);
  }
  return copy;
}

BOOL MLNFFIWithOfflineRegionDefinition(id<MLNOfflineRegion> region,
                                       void (^block)(const mln_offline_region_definition *)) {
  if (![region conformsToProtocol:@protocol(MLNOfflineRegion_Private)]) {
    return NO;
  }
  // The definition's buffer views point into the region, which this frame keeps.
  mln_offline_region_definition definition =
      [(id<MLNOfflineRegion_Private>)region mgl_offlineRegionDefinition];
  block(&definition);
  return YES;
}
