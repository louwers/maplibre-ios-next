// Based on platform/darwin/src/MLNOfflineStorage_Private.h at ios-v7.0.0
//
// Classic exposed the shared mbgl file sources here. The C API's runtime
// (MLNFFIRuntime) takes their place; the offline storage configures its
// database path before the runtime opens it.

#import "MLNOfflinePack.h"
#import "MLNOfflineStorage.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLNOfflineStorage (Private)

/// The database path the runtime opens, as `databasePath` reports it, without
/// creating the shared storage.
+ (NSString *)mgl_databasePath;

- (void)getPacksWithCompletionHandler:(void (^)(NSArray<MLNOfflinePack *> *packs,
                                                NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
