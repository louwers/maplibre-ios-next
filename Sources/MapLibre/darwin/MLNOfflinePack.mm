// Based on platform/darwin/src/MLNOfflinePack.mm at ios-v7.0.0

#import "MLNOfflinePack_Private.h"

#import "MLNFFI.h"
#import "MLNFFIOfflineRegions.h"
#import "MLNLoggingConfiguration_Private.h"
#import "MLNOfflineStorage_Private.h"
#import "MLNShapeOfflineRegion.h"
#import "MLNTilePyramidOfflineRegion.h"

#import "NSValue+MLNAdditions.h"

const MLNExceptionName MLNInvalidOfflinePackException = @"MLNInvalidOfflinePackException";

/**
 Assert that the current offline pack is valid.

 This macro should be used at the beginning of any public-facing instance method
 of ``MLNOfflinePack``. For private methods, an assertion is more appropriate.
 */
#define MLNAssertOfflinePackIsValid()                                                       \
  do {                                                                                      \
    if (_state == MLNOfflinePackStateInvalid) {                                             \
      [NSException                                                                          \
           raise:MLNInvalidOfflinePackException                                             \
          format:@"-[MLNOfflineStorage removePack:withCompletionHandler:] has been called " \
                 @"on this instance of MLNOfflinePack, rendering it invalid. It is an "     \
                 @"error to send any message to this pack."];                               \
    }                                                                                       \
  } while (NO);


@interface MLNOfflinePack ()

@property (nonatomic, nullable, readwrite) MLNFFIOfflineRegionInfo *mgl_regionInfo;
@property (nonatomic, readwrite) MLNOfflinePackProgress progress;

@end

@implementation MLNOfflinePack {
  BOOL _isSuspending;
}

- (instancetype)init {
  MLNLogInfo(@"Calling this initializer is not allowed.");
  if (self = [super init]) {
    _state = MLNOfflinePackStateInvalid;
    NSLog(@"%s called; did you mean to call +[MLNOfflineStorage "
          @"addPackForRegion:withContext:completionHandler:] instead?",
          __PRETTY_FUNCTION__);
  }
  return self;
}

- (instancetype)initWithRegionInfo:(MLNFFIOfflineRegionInfo *)regionInfo {
  if (self = [super init]) {
    _mgl_regionInfo = regionInfo;
    _state = MLNOfflinePackStateUnknown;

    // Classic observed every pack's region; the runtime reports a region's
    // events only once it is observed. MLNOfflineStorage routes them.
    mln_runtime runtime = [MLNFFIRuntime sharedRuntime].handle;
    mln_offline_region_id regionID = regionInfo.identifier;
    [[MLNFFIRuntime sharedRuntime]
         callAsync:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
           return mln_runtime_set_offline_region_observed(runtime, regionID, true, completion,
                                                          diagnostic);
         }
           consume:nil
        completion:nil];
  }
  return self;
}

- (void)dealloc {
  MLNAssert(_state == MLNOfflinePackStateInvalid,
            @"MLNOfflinePack was not invalided prior to deallocation.");
}

- (nullable NSNumber *)regionId {
  if (_state == MLNOfflinePackStateInvalid || !_mgl_regionInfo) {
    return nil;
  }

  return @(_mgl_regionInfo.identifier);
}

- (id<MLNOfflineRegion>)region {
  MLNAssertOfflinePackIsValid();

  return _mgl_regionInfo.region;
}

- (NSData *)context {
  MLNAssertOfflinePackIsValid();

  return _mgl_regionInfo.metadata;
}

- (void)setContext:(NSData *)context
    completionHandler:(void (^_Nullable)(NSError *_Nullable error))completion {
  MLNAssertOfflinePackIsValid();

  [self willChangeValueForKey:@"context"];
  __weak MLNOfflinePack *weakSelf = self;
  __block MLNFFIOfflineRegionInfo *updatedInfo;
  mln_runtime runtime = [MLNFFIRuntime sharedRuntime].handle;
  mln_offline_region_id regionID = _mgl_regionInfo.identifier;
  NSData *metadata = [context copy];
  [[MLNFFIRuntime sharedRuntime]
       callAsync:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
         return mln_runtime_update_offline_region_metadata(
             runtime, regionID, (const uint8_t *)metadata.bytes, metadata.length, completion,
             diagnostic);
       }
       consume:^(const mln_completion_result *result) {
         if (result->value) {
           updatedInfo = MLNFFIOfflineRegionInfoFromC((const mln_offline_region_info *)result->value);
         }
       }
      completion:^(mln_status status, NSString *message) {
        NSError *error;
        if (status != MLN_STATUS_OK) {
          error = [NSError errorWithDomain:MLNErrorDomain
                                      code:MLNErrorCodeModifyingOfflineStorageFailed
                                  userInfo:message.length ? @{
                                    NSLocalizedDescriptionKey : message,
                                  }
                                                          : nil];
        }
        MLNOfflinePack *strongSelf = weakSelf;
        // The C API returns the updated region, which classic read back by
        // reloading the packs.
        if (updatedInfo && strongSelf.mgl_regionInfo) {
          strongSelf.mgl_regionInfo = updatedInfo;
        }
        [strongSelf didChangeValueForKey:@"context"];
        if (completion) {
          completion(error);
        }
      }];
}

- (void)reloadWithCompletionHandler:(void (^)(NSError *_Nullable error))completion {
  mln_offline_region_id regionID = _mgl_regionInfo.identifier;
  MLNOfflineStorage *sharedOfflineStorage = [MLNOfflineStorage sharedOfflineStorage];
  __weak MLNOfflinePack *weakSelf = self;
  [sharedOfflineStorage getPacksWithCompletionHandler:^(NSArray<MLNOfflinePack *> *packs,
                                                        __unused NSError *_Nullable error) {
    MLNOfflinePack *strongSelf = weakSelf;
    for (MLNOfflinePack *pack in packs) {
      if (pack.mgl_regionInfo.identifier == regionID) {
        strongSelf.mgl_regionInfo = pack.mgl_regionInfo;
      }
      [pack invalidate];
    }
    completion(error);
  }];
}

- (void)resume {
  MLNLogInfo(@"Resuming pack download.");
  MLNAssertOfflinePackIsValid();

  self.state = MLNOfflinePackStateActive;

  [self mgl_setDownloadState:MLN_OFFLINE_REGION_DOWNLOAD_ACTIVE];
}

- (void)suspend {
  MLNLogInfo(@"Suspending pack download.");
  MLNAssertOfflinePackIsValid();

  if (self.state == MLNOfflinePackStateActive) {
    self.state = MLNOfflinePackStateInactive;
    _isSuspending = YES;
  }

  [self mgl_setDownloadState:MLN_OFFLINE_REGION_DOWNLOAD_INACTIVE];
}

- (void)mgl_setDownloadState:(mln_offline_region_download_state)state {
  mln_runtime runtime = [MLNFFIRuntime sharedRuntime].handle;
  mln_offline_region_id regionID = _mgl_regionInfo.identifier;
  [[MLNFFIRuntime sharedRuntime]
       callAsync:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
         return mln_runtime_set_offline_region_download_state(runtime, regionID, state, completion,
                                                              diagnostic);
       }
         consume:nil
      completion:^(mln_status status, NSString *message) {
        if (status != MLN_STATUS_OK) {
          MLNLogError(@"Failed to set the download state of offline region %lld: %@", regionID,
                      message);
        }
      }];
}

- (void)invalidate {
  MLNLogInfo(@"Invalidating pack.");
  MLNAssert(_state != MLNOfflinePackStateInvalid,
            @"Cannot invalidate an already invalid offline pack.");
  MLNAssert(self.mgl_regionInfo, @"Should have a valid region");

  // Classic removed the region's observer here. Several pack objects can stand
  // for one region (MLNOfflineStorage creates temporary ones when reloading),
  // so observation stays on; MLNOfflineStorage only routes events to the packs
  // it holds.
  @synchronized(self) {
    self.state = MLNOfflinePackStateInvalid;
    self.mgl_regionInfo = nil;
  }
}

- (void)setState:(MLNOfflinePackState)state {
  MLNLogDebug(@"Setting state: %ld", (long)state);
  if (!self.mgl_regionInfo) {
    // A progress update has arrived after the call to
    // -[MLNOfflineStorage removePack:withCompletionHandler:] but before the
    // removal is complete and the completion handler is called.
    MLNAssert(_state == MLNOfflinePackStateInvalid,
              @"A valid MLNOfflinePack has no offline region.");
    return;
  }

  MLNAssert(_state != MLNOfflinePackStateInvalid,
            @"Cannot change the state of an invalid offline pack.");

  if (!_isSuspending || state != MLNOfflinePackStateActive) {
    _isSuspending = NO;
    _state = state;
  }
}

- (void)requestProgress {
  MLNLogInfo(@"Requesting pack progress.");
  MLNAssertOfflinePackIsValid();

  __weak MLNOfflinePack *weakSelf = self;
  __block mln_offline_region_status status;
  __block BOOL hasStatus = NO;
  mln_runtime runtime = [MLNFFIRuntime sharedRuntime].handle;
  mln_offline_region_id regionID = _mgl_regionInfo.identifier;
  [[MLNFFIRuntime sharedRuntime]
       callAsync:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
         return mln_runtime_get_offline_region_status(runtime, regionID, completion, diagnostic);
       }
       consume:^(const mln_completion_result *result) {
         if (result->value) {
           status = *(const mln_offline_region_status *)result->value;
           hasStatus = YES;
         }
       }
      completion:^(mln_status, NSString *) {
        MLNOfflinePack *strongSelf = weakSelf;
        if (hasStatus && strongSelf.mgl_regionInfo) {
          [strongSelf offlineRegionStatusDidChange:status];
        }
      }];
}

- (void)offlineRegionStatusDidChange:(mln_offline_region_status)status {
  MLNAssert(_state != MLNOfflinePackStateInvalid,
            @"Cannot change update progress of an invalid offline pack.");

  switch (status.download_state) {
    case MLN_OFFLINE_REGION_DOWNLOAD_INACTIVE:
      self.state = status.complete ? MLNOfflinePackStateComplete : MLNOfflinePackStateInactive;
      break;

    case MLN_OFFLINE_REGION_DOWNLOAD_ACTIVE:
      self.state = MLNOfflinePackStateActive;
      break;
  }

  if (_isSuspending) {
    return;
  }

  MLNOfflinePackProgress progress;
  progress.countOfResourcesCompleted = status.completed_resource_count;
  progress.countOfBytesCompleted = status.completed_resource_size;
  progress.countOfTilesCompleted = status.completed_tile_count;
  progress.countOfTileBytesCompleted = status.completed_tile_size;
  progress.countOfResourcesExpected = status.required_resource_count;
  progress.maximumResourcesExpected =
      status.required_resource_count_is_precise ? status.required_resource_count : UINT64_MAX;
  self.progress = progress;

  NSDictionary *userInfo = @{
    MLNOfflinePackUserInfoKeyState : @(self.state),
    MLNOfflinePackUserInfoKeyProgress : [NSValue valueWithMLNOfflinePackProgress:progress]
  };

  NSNotificationCenter *noteCenter = [NSNotificationCenter defaultCenter];
  [noteCenter postNotificationName:MLNOfflinePackProgressChangedNotification
                            object:self
                          userInfo:userInfo];
}

- (void)didReceiveError:(NSError *)error {
  MLNLogError(@"Error: %@", error.localizedDescription);
  MLNLogInfo(@"Notifying about pack error.");

  NSDictionary *userInfo = @{MLNOfflinePackUserInfoKeyError : error};
  NSNotificationCenter *noteCenter = [NSNotificationCenter defaultCenter];
  [noteCenter postNotificationName:MLNOfflinePackErrorNotification object:self userInfo:userInfo];
}

- (void)didReceiveMaximumAllowedMapboxTiles:(uint64_t)limit {
  MLNLogInfo(@"Notifying reached maximum allowed Mapbox tiles: %lu", (unsigned long)limit);
  NSDictionary *userInfo = @{MLNOfflinePackUserInfoKeyMaximumCount : @(limit)};
  NSNotificationCenter *noteCenter = [NSNotificationCenter defaultCenter];
  [noteCenter postNotificationName:MLNOfflinePackMaximumMapboxTilesReachedNotification
                            object:self
                          userInfo:userInfo];
}

@end

NSError *MLNErrorFromResponseErrorReason(mln_resource_error_reason reason, NSString *message) {
  NSInteger errorCode = MLNErrorCodeUnknown;
  switch (reason) {
    case MLN_RESOURCE_ERROR_REASON_NOT_FOUND:
      errorCode = MLNErrorCodeNotFound;
      break;

    case MLN_RESOURCE_ERROR_REASON_SERVER:
      errorCode = MLNErrorCodeBadServerResponse;
      break;

    case MLN_RESOURCE_ERROR_REASON_CONNECTION:
      errorCode = MLNErrorCodeConnectionFailed;
      break;

    default:
      break;
  }
  return [NSError errorWithDomain:MLNErrorDomain
                             code:errorCode
                         userInfo:@{NSLocalizedFailureReasonErrorKey : message ?: @""}];
}

