// Based on platform/darwin/src/MLNOfflineStorage.mm at ios-v7.0.0

#import "MLNOfflineStorage_Private.h"

#import "MLNFFI.h"
#import "MLNFFIOfflineRegions.h"
#import "MLNFoundation_Private.h"
#import "MLNGeometry_Private.h"
#import "MLNLoggingConfiguration_Private.h"
#import "MLNNetworkConfiguration_Private.h"
#import "MLNOfflinePack_Private.h"
#import "MLNSettings_Private.h"
#import "MLNShapeOfflineRegion.h"
#import "MLNTilePyramidOfflineRegion.h"
#import "NSBundle+MLNAdditions.h"
#import "NSDate+MLNAdditions.h"
#import "NSValue+MLNAdditions.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

static NSString *const MLNOfflineStorageDatabasePathInfoDictionaryKey =
    @"MLNOfflineStorageDatabasePath";
static NSString *const MLNOfflineStorageFileName = @"cache.db";
static NSString *const MLNOfflineStorageFileName3_2_0_beta_1 = @"offline.db";

const NSNotificationName MLNOfflinePackProgressChangedNotification =
    @"MLNOfflinePackProgressChanged";
const NSNotificationName MLNOfflinePackErrorNotification = @"MLNOfflinePackError";
const NSNotificationName MLNOfflinePackMaximumMapboxTilesReachedNotification =
    @"MLNOfflinePackMaximumMapboxTilesReached";

const MLNOfflinePackUserInfoKey MLNOfflinePackUserInfoKeyState = @"State";
const MLNOfflinePackUserInfoKey MLNOfflinePackUserInfoKeyProgress = @"Progress";
const MLNOfflinePackUserInfoKey MLNOfflinePackUserInfoKeyError = @"Error";
const MLNOfflinePackUserInfoKey MLNOfflinePackUserInfoKeyMaximumCount = @"MaximumCount";

const MLNExceptionName MLNUnsupportedRegionTypeException = @"MLNUnsupportedRegionTypeException";

@interface MLNOfflineStorage () <MLNFFIRuntimeEventObserver>

@property (nonatomic, strong, readwrite) NSMutableArray<MLNOfflinePack *> *packs;
@property (nonatomic, getter=isPaused) BOOL paused;
@end

/// Logs once that a classic feature has no C API counterpart.
static void MLNLogUnsupportedOnce(NSString *feature) {
  static NSMutableSet<NSString *> *logged;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    logged = [NSMutableSet set];
  });
  @synchronized(logged) {
    if ([logged containsObject:feature]) {
      return;
    }
    [logged addObject:feature];
  }
  MLNLogWarning(@"%@ is not supported: the MapLibre Native C API has no equivalent. See "
                @"C_API_GAPS.md.",
                feature);
}

/// The resource kind for a C API resource kind.
static MLNResourceKind MLNResourceKindFromFFI(mln_resource_kind kind) {
  switch (kind) {
    case MLN_RESOURCE_KIND_TILE:
      return MLNResourceKindTile;
    case MLN_RESOURCE_KIND_GLYPHS:
      return MLNResourceKindGlyphs;
    case MLN_RESOURCE_KIND_STYLE:
      return MLNResourceKindStyle;
    case MLN_RESOURCE_KIND_SOURCE:
      return MLNResourceKindSource;
    case MLN_RESOURCE_KIND_SPRITE_IMAGE:
      return MLNResourceKindSpriteImage;
    case MLN_RESOURCE_KIND_SPRITE_JSON:
      return MLNResourceKindSpriteJSON;
    case MLN_RESOURCE_KIND_IMAGE:
      return MLNResourceKindImage;
    case MLN_RESOURCE_KIND_UNKNOWN:
      return MLNResourceKindUnknown;
  }
  return MLNResourceKindUnknown;
}

/// Asks the delegate for each network URL on the main thread, where classic's
/// resource transform actor ran, and answers the C API's request from there.
static void MLNOfflineStorageResourceTransform(void *userData, mln_resource_kind kind,
                                               mln_buffer_view url,
                                               mln_resource_transform_request request) {
  NSString *urlString = MLNFFIStringFromBufferView(url) ?: @"";
  MLNResourceKind resourceKind = MLNResourceKindFromFFI(kind);
  dispatch_async(dispatch_get_main_queue(), ^{
    MLNOfflineStorage *storage = [MLNOfflineStorage sharedOfflineStorage];
    id<MLNOfflineStorageDelegate> delegate = storage.delegate;
    NSURL *transformed = [NSURL URLWithString:urlString];
    if ([delegate respondsToSelector:@selector(offlineStorage:URLForResourceOfKind:withURL:)]) {
      transformed = [delegate offlineStorage:storage
                        URLForResourceOfKind:resourceKind
                                     withURL:transformed];
    }
    NSString *answer = transformed.absoluteString;
    mln_diagnostic diagnostic = {sizeof(mln_diagnostic)};
    if (!answer.length ||
        mln_resource_transform_request_complete(request, MLNFFIBufferView(answer), &diagnostic) !=
            MLN_STATUS_OK) {
      // A request released without an answer keeps its URL.
      mln_resource_transform_request_release(request);
    }
  });
}

@implementation MLNOfflineStorage

+ (void)load {
  // The runtime opens its database when it is created, by whichever object
  // needs it first (a map, a snapshotter, or this storage), so supply the
  // classic database location and network configuration up front.
  [MLNFFIRuntime setDefaultCachePathProvider:^NSString * {
    [MLNNetworkConfiguration sharedManager];
    return [MLNOfflineStorage mgl_databasePath];
  }];
}

+ (instancetype)sharedOfflineStorage {
  static dispatch_once_t onceToken;
  static MLNOfflineStorage *sharedOfflineStorage;
  dispatch_once(&onceToken, ^{
    sharedOfflineStorage = [[self alloc] init];
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    [[NSNotificationCenter defaultCenter] addObserver:sharedOfflineStorage
                                             selector:@selector(unpauseFileSource:)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:sharedOfflineStorage
                                             selector:@selector(pauseFileSource:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
#endif
    [sharedOfflineStorage reloadPacks];
  });

  // Always ensure the MLNNativeNetworkManager delegate is setup. Calling
  // `resetNativeNetworkManagerDelegate` is not necessary here, since the shared
  // manager already calls it.
  //
  // TODO: Consider only calling this for testing?
  [MLNNetworkConfiguration sharedManager];

  return sharedOfflineStorage;
}

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
// Classic paused the online and database file sources in the background. The
// C API cannot pause a runtime's file sources (C_API_GAPS.md); requests keep
// running.
- (void)pauseFileSource:(__unused NSNotification *)notification {
  if (self.isPaused) {
    return;
  }

  self.paused = YES;
}

- (void)unpauseFileSource:(__unused NSNotification *)notification {
  if (!self.isPaused) {
    return;
  }

  self.paused = NO;
}
#endif

- (void)setDelegate:(id<MLNOfflineStorageDelegate>)newValue {
  MLNLogDebug(@"Setting delegate: %@", newValue);
  _delegate = newValue;
  mln_runtime runtime = [MLNFFIRuntime sharedRuntime].handle;
  NSString *message;
  mln_status status;
  if ([self.delegate respondsToSelector:@selector(offlineStorage:URLForResourceOfKind:withURL:)]) {
    mln_resource_transform transform = {sizeof(mln_resource_transform)};
    transform.callback = MLNOfflineStorageResourceTransform;
    status = [[MLNFFIRuntime sharedRuntime]
           call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
             return mln_runtime_set_resource_transform(runtime, &transform, completion, diagnostic);
           }
        consume:nil
        message:&message];
  } else {
    status = [[MLNFFIRuntime sharedRuntime]
           call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
             return mln_runtime_clear_resource_transform(runtime, completion, diagnostic);
           }
        consume:nil
        message:&message];
  }
  if (status != MLN_STATUS_OK) {
    MLNLogError(@"Failed to update the resource transform: %@", message);
  }
}

- (instancetype)init {
  // Ensure network configuration & appropriate delegate prior to starting the
  // run loop. Calling `resetNativeNetworkManagerDelegate` is not necessary here,
  // since the shared manager already calls it.
  [MLNNetworkConfiguration sharedManager];

  if (self = [super init]) {
    // Creates the runtime, which opens the database at -databasePath (see
    // +load), and receives its offline region events.
    [MLNFFIRuntime sharedRuntime].runtimeEventObserver = self;
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];

  for (MLNOfflinePack *pack in self.packs) {
    [pack invalidate];
  }
}

// Classic synchronized the online file source's API key and tile server
// options with MLNSettings here. The C API's runtime has neither
// (C_API_GAPS.md).

// MARK: - Runtime events

- (void)ffiRuntimeDidReceiveEvent:(MLNFFIEvent *)event {
  mln_offline_region_id regionID;
  switch (event.payloadType) {
    case MLN_RUNTIME_EVENT_PAYLOAD_OFFLINE_REGION_STATUS:
      regionID = event.payload.offline_region_status.region_id;
      break;
    case MLN_RUNTIME_EVENT_PAYLOAD_OFFLINE_REGION_RESPONSE_ERROR:
      regionID = event.payload.offline_region_response_error.region_id;
      break;
    case MLN_RUNTIME_EVENT_PAYLOAD_OFFLINE_REGION_TILE_COUNT_LIMIT:
      regionID = event.payload.offline_region_tile_count_limit.region_id;
      break;
    default:
      return;
  }
  for (MLNOfflinePack *pack in [self.packs copy]) {
    if (pack.state == MLNOfflinePackStateInvalid || pack.mgl_regionInfo.identifier != regionID) {
      continue;
    }
    switch (event.type) {
      case MLN_RUNTIME_EVENT_OFFLINE_REGION_STATUS_CHANGED:
        [pack offlineRegionStatusDidChange:event.payload.offline_region_status.status];
        break;
      case MLN_RUNTIME_EVENT_OFFLINE_REGION_RESPONSE_ERROR:
        [pack didReceiveError:MLNErrorFromResponseErrorReason(
                                  event.payload.offline_region_response_error.reason,
                                  event.message)];
        break;
      case MLN_RUNTIME_EVENT_OFFLINE_REGION_TILE_COUNT_LIMIT_EXCEEDED:
        [pack didReceiveMaximumAllowedMapboxTiles:event.payload.offline_region_tile_count_limit
                                                      .limit];
        break;
      default:
        break;
    }
  }
}

// MARK: Database management methods

- (NSString *)databasePath {
  return self.databaseURL.path;
}

+ (NSString *)mgl_databasePath {
  return [self mgl_databaseURL].path;
}

- (NSURL *)databaseURL {
  return [[self class] mgl_databaseURL];
}

// Classic computed this per instance; the runtime needs it before the shared
// storage exists, so it is computed once for the process.
+ (NSURL *)mgl_databaseURL {
  static NSURL *_databaseURL;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSString *customPath = [NSBundle.mainBundle
        objectForInfoDictionaryKey:MLNOfflineStorageDatabasePathInfoDictionaryKey];
    if ([customPath isKindOfClass:[NSString class]]) {
      _databaseURL = [NSURL fileURLWithPath:customPath.stringByStandardizingPath
                                isDirectory:NO
                              relativeToURL:NSBundle.mainBundle.resourceURL];

      NSURL *directoryURL = _databaseURL.URLByDeletingLastPathComponent;
      [NSFileManager.defaultManager createDirectoryAtURL:directoryURL
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
    } else {
      _databaseURL = [[self class] defaultDatabaseURLIncludingSubdirectory:YES];
    }
    NSString *databasePath = _databaseURL.path;
    NSAssert(databasePath, @"Offline pack database URL “%@” is not a valid file URL.",
             _databaseURL);

    // Move the offline database from v3.2.0-beta.1 to a location that can
    // also be used for ambient caching.
    if (![[NSFileManager defaultManager] fileExistsAtPath:databasePath]) {
      NSString *legacyDatabasePath = [[self class] legacyDatabasePath];
      [[NSFileManager defaultManager] moveItemAtPath:legacyDatabasePath
                                              toPath:databasePath
                                               error:NULL];
    }

    // Move the offline database from v3.2.x path to a subdirectory that can
    // be reliably excluded from backups.
    if (![[NSFileManager defaultManager] fileExistsAtPath:databasePath]) {
      NSURL *subdirectorylessDatabaseURL =
          [[self class] defaultDatabaseURLIncludingSubdirectory:NO];
      [[NSFileManager defaultManager] moveItemAtPath:subdirectorylessDatabaseURL.path
                                              toPath:databasePath
                                               error:NULL];
    }
  });
  return _databaseURL;
}

/**
 Returns the default file URL to the offline pack database, with the option to
 omit the private subdirectory for legacy (v3.2.0–v3.2.3) migration purposes.

 The database is located in a directory specific to the application, so that
 packs downloaded by other applications don’t count toward this application’s
 limits.

 The database is located at:
 ~/Library/Application Support/tld.app.bundle.id/.mapbox/cache.db

 The subdirectory-less database was located at:
 ~/Library/Application Support/tld.app.bundle.id/cache.db
 */
+ (NSURL *)defaultDatabaseURLIncludingSubdirectory:(BOOL)useSubdirectory {
  NSURL *databaseDirectoryURL =
      [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory
                                             inDomain:NSUserDomainMask
                                    appropriateForURL:nil
                                               create:YES
                                                error:nil];
  NSString *bundleIdentifier = [NSBundle mgl_applicationBundleIdentifier];
  if (!bundleIdentifier) {
    // There’s no main bundle identifier when running in a unit test bundle.
    bundleIdentifier = [[NSUUID UUID] UUIDString];
  }
  databaseDirectoryURL = [databaseDirectoryURL URLByAppendingPathComponent:bundleIdentifier];
  if (useSubdirectory) {
    databaseDirectoryURL = [databaseDirectoryURL URLByAppendingPathComponent:@".mapbox"];
  }
  [[NSFileManager defaultManager] createDirectoryAtURL:databaseDirectoryURL
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:nil];
  if (useSubdirectory) {
    // Avoid backing up the database onto iCloud, because it can be
    // redownloaded. Ideally, we’d even put the ambient cache in Caches, so
    // it can be reclaimed by the system when disk space runs low. But
    // unfortunately it has to live in the same file as offline resources.
    [databaseDirectoryURL setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:NULL];
  }
  return [databaseDirectoryURL URLByAppendingPathComponent:MLNOfflineStorageFileName];
}

/**
 Returns the absolute path to the location where v3.2.0-beta.1 placed the
 offline pack database.
 */
+ (NSString *)legacyDatabasePath {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  // ~/Documents/offline.db
  NSArray *legacyPaths =
      NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
  NSString *legacyDatabasePath = [legacyPaths.firstObject
      stringByAppendingPathComponent:MLNOfflineStorageFileName3_2_0_beta_1];
#elif TARGET_OS_MAC
  // ~/Library/Caches/tld.app.bundle.id/offline.db
  NSString *bundleIdentifier = [NSBundle mgl_applicationBundleIdentifier];
  NSURL *legacyDatabaseDirectoryURL =
      [[NSFileManager defaultManager] URLForDirectory:NSCachesDirectory
                                             inDomain:NSUserDomainMask
                                    appropriateForURL:nil
                                               create:NO
                                                error:nil];
  legacyDatabaseDirectoryURL =
      [legacyDatabaseDirectoryURL URLByAppendingPathComponent:bundleIdentifier];
  NSURL *legacyDatabaseURL = [legacyDatabaseDirectoryURL
      URLByAppendingPathComponent:MLNOfflineStorageFileName3_2_0_beta_1];
  NSString *legacyDatabasePath = legacyDatabaseURL ? legacyDatabaseURL.path : @"";
#endif
  return legacyDatabasePath;
}

- (void)addContentsOfFile:(NSString *)filePath
    withCompletionHandler:(MLNBatchedOfflinePackAdditionCompletionHandler)completion {
  MLNLogDebug(@"Adding contentsOfFile: %@ completionHandler: %@", filePath, completion);
  NSURL *fileURL = [NSURL fileURLWithPath:filePath];

  [self addContentsOfURL:fileURL withCompletionHandler:completion];
}

- (void)addContentsOfURL:(NSURL *)fileURL
    withCompletionHandler:(MLNBatchedOfflinePackAdditionCompletionHandler)completion {
  MLNLogDebug(@"Adding contentsOfURL: %@ completionHandler: %@", fileURL, completion);
  NSFileManager *fileManager = [NSFileManager defaultManager];

  if (!fileURL.isFileURL) {
    [NSException raise:NSInvalidArgumentException
                format:@"%@ must be a valid file path", fileURL.absoluteString];
  }
  if (![fileManager isWritableFileAtPath:fileURL.path]) {
    [NSException raise:NSInvalidArgumentException
                format:@"The file path: %@ must be writable", fileURL.absoluteString];
  }

  __weak MLNOfflineStorage *weakSelf = self;
  [self _addContentsOfFile:fileURL.path
      withCompletionHandler:^(NSArray<MLNOfflinePack *> *_Nullable packs,
                              NSError *_Nullable error) {
        if (packs) {
          NSMutableDictionary *packsByIdentifier = [NSMutableDictionary dictionary];

          MLNOfflineStorage *strongSelf = weakSelf;
          for (MLNOfflinePack *pack in packs) {
            [packsByIdentifier setObject:pack forKey:@(pack.mgl_regionInfo.identifier)];
          }

          id mutablePacks = [strongSelf mutableArrayValueForKey:@"packs"];
          NSMutableIndexSet *replaceIndexSet = [NSMutableIndexSet indexSet];
          NSMutableArray *replacePacksArray = [NSMutableArray array];
          [strongSelf.packs enumerateObjectsUsingBlock:^(MLNOfflinePack *_Nonnull pack,
                                                         NSUInteger idx, BOOL *_Nonnull stop) {
            MLNOfflinePack *newPack = packsByIdentifier[@(pack.mgl_regionInfo.identifier)];
            if (newPack) {
              MLNOfflinePack *previousPack = [mutablePacks objectAtIndex:idx];
              [previousPack invalidate];
              [replaceIndexSet addIndex:idx];
              [replacePacksArray
                  addObject:[packsByIdentifier objectForKey:@(newPack.mgl_regionInfo.identifier)]];
              [packsByIdentifier removeObjectForKey:@(newPack.mgl_regionInfo.identifier)];
            }
          }];

          if (replaceIndexSet.count > 0) {
            [mutablePacks replaceObjectsAtIndexes:replaceIndexSet withObjects:replacePacksArray];
          }

          [mutablePacks addObjectsFromArray:packsByIdentifier.allValues];
        }
        if (completion) {
          completion(fileURL, packs, error);
        }
      }];
}

- (void)_addContentsOfFile:(NSString *)filePath
     withCompletionHandler:(void (^)(NSArray<MLNOfflinePack *> *_Nullable packs,
                                     NSError *_Nullable error))completion {
  __block NSMutableArray<MLNFFIOfflineRegionInfo *> *regions = [NSMutableArray array];
  mln_runtime runtime = [MLNFFIRuntime sharedRuntime].handle;
  [[MLNFFIRuntime sharedRuntime]
       callAsync:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
         return mln_runtime_merge_offline_regions(runtime, MLNFFIBufferView(filePath), completion,
                                                  diagnostic);
       }
       consume:^(const mln_completion_result *result) {
         for (size_t i = 0; i < result->value_count; i++) {
           [regions addObject:MLNFFIOfflineRegionInfoFromC(MLN_STRIDED_AT(
                                  mln_offline_region_info, result->value, result->value_size, i))];
         }
       }
      completion:^(mln_status status, NSString *message) {
        NSError *error;
        NSMutableArray *packs;
        if (status != MLN_STATUS_OK) {
          NSString *description =
              [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(
                                             @"ADD_FILE_CONTENTS_FAILED_DESC", @"Foundation", nil,
                                             @"Unable to add offline packs from the file at %@.",
                                             @"User-friendly error description"),
                                         filePath];
          error = [NSError errorWithDomain:MLNErrorDomain
                                      code:MLNErrorCodeModifyingOfflineStorageFailed
                                  userInfo:@{
                                    NSLocalizedDescriptionKey : description,
                                    NSLocalizedFailureReasonErrorKey : message ?: @""
                                  }];
        } else {
          packs = [NSMutableArray arrayWithCapacity:regions.count];
          for (MLNFFIOfflineRegionInfo *region in regions) {
            [packs addObject:[[MLNOfflinePack alloc] initWithRegionInfo:region]];
          }
        }
        if (completion) {
          completion(packs, error);
        }
      }];
}

// MARK: Pack management methods

- (void)addPackForRegion:(id<MLNOfflineRegion>)region
             withContext:(NSData *)context
       completionHandler:(MLNOfflinePackAdditionCompletionHandler)completion {
  MLNLogDebug(@"Adding packForRegion: %@ contextLength: %lu completionHandler: %@", region,
              (unsigned long)context.length, completion);
  __weak MLNOfflineStorage *weakSelf = self;
  [self _addPackForRegion:region
              withContext:context
        completionHandler:^(MLNOfflinePack *_Nullable pack, NSError *_Nullable error) {
          pack.state = MLNOfflinePackStateInactive;
          MLNOfflineStorage *strongSelf = weakSelf;
          [[strongSelf mutableArrayValueForKey:@"packs"] addObject:pack];
          if (completion) {
            completion(pack, error);
          }
        }];
}

- (void)_addPackForRegion:(id<MLNOfflineRegion>)region
              withContext:(NSData *)context
        completionHandler:(MLNOfflinePackAdditionCompletionHandler)completion {
  __block MLNFFIOfflineRegionInfo *regionInfo;
  mln_runtime runtime = [MLNFFIRuntime sharedRuntime].handle;
  NSData *metadata = [context copy];
  void (^completionHandler)(mln_status, NSString *) = ^(mln_status status, NSString *message) {
    NSError *error;
    if (status != MLN_STATUS_OK) {
      error = [NSError errorWithDomain:MLNErrorDomain
                                  code:MLNErrorCodeModifyingOfflineStorageFailed
                              userInfo:message.length ? @{
                                NSLocalizedDescriptionKey : message,
                              }
                                                      : nil];
    }
    if (completion) {
      MLNOfflinePack *pack =
          regionInfo ? [[MLNOfflinePack alloc] initWithRegionInfo:regionInfo] : nil;
      completion(pack, error);
    }
  };
  BOOL supported = MLNFFIWithOfflineRegionDefinition(
      region, ^(const mln_offline_region_definition *definition) {
        [[MLNFFIRuntime sharedRuntime]
             callAsync:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
               return mln_runtime_create_offline_region(runtime, definition,
                                                        (const uint8_t *)metadata.bytes,
                                                        metadata.length, completion, diagnostic);
             }
             consume:^(const mln_completion_result *result) {
               if (result->value) {
                 regionInfo =
                     MLNFFIOfflineRegionInfoFromC((const mln_offline_region_info *)result->value);
               }
             }
            completion:completionHandler];
      });
  if (!supported) {
    [NSException raise:MLNUnsupportedRegionTypeException
                format:@"Regions of type %@ are unsupported.", NSStringFromClass([region class])];
    return;
  }
}

- (void)removePack:(MLNOfflinePack *)pack
    withCompletionHandler:(MLNOfflinePackRemovalCompletionHandler)completion {
  MLNLogDebug(@"Removing pack: %@ completionHandler: %@", pack, completion);
  [[self mutableArrayValueForKey:@"packs"] removeObject:pack];
  [self _removePack:pack
      withCompletionHandler:^(NSError *_Nullable error) {
        if (completion) {
          completion(error);
        }
      }];
}

- (void)_removePack:(MLNOfflinePack *)pack
    withCompletionHandler:(MLNOfflinePackRemovalCompletionHandler)completion {
  MLNFFIOfflineRegionInfo *regionInfo = pack.mgl_regionInfo;

  [pack invalidate];

  if (!regionInfo) {
    MLNAssert(pack.state == MLNOfflinePackStateInvalid, @"State should be invalid");
    completion(nil);
    return;
  }

  mln_runtime runtime = [MLNFFIRuntime sharedRuntime].handle;
  mln_offline_region_id regionID = regionInfo.identifier;
  [[MLNFFIRuntime sharedRuntime]
       callAsync:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
         return mln_runtime_delete_offline_region(runtime, regionID, completion, diagnostic);
       }
         consume:nil
      completion:^(mln_status status, NSString *message) {
        NSError *error;
        if (status != MLN_STATUS_OK) {
          error = [NSError errorWithDomain:MLNErrorDomain
                                      code:MLNErrorCodeModifyingOfflineStorageFailed
                                  userInfo:@{
                                    NSLocalizedDescriptionKey : message ?: @"",
                                  }];
        }
        if (completion) {
          completion(error);
        }
      }];
}

- (void)invalidatePack:(MLNOfflinePack *)pack
    withCompletionHandler:(void (^)(NSError *_Nullable))completion {
  MLNFFIOfflineRegionInfo *regionInfo = pack.mgl_regionInfo;
  if (!regionInfo) {
    if (completion) {
      dispatch_async(dispatch_get_main_queue(), ^{
        completion(nil);
      });
    }
    return;
  }

  mln_runtime runtime = [MLNFFIRuntime sharedRuntime].handle;
  mln_offline_region_id regionID = regionInfo.identifier;
  [[MLNFFIRuntime sharedRuntime]
       callAsync:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
         return mln_runtime_invalidate_offline_region(runtime, regionID, completion, diagnostic);
       }
         consume:nil
      completion:^(mln_status status, NSString *message) {
        NSError *error = nil;
        if (status != MLN_STATUS_OK) {
          error = [NSError errorWithDomain:MLNErrorDomain
                                      code:MLNErrorCodeModifyingOfflineStorageFailed
                                  userInfo:@{
                                    NSLocalizedDescriptionKey : message ?: @"",
                                  }];
        }
        if (completion) {
          completion(error);
        }
      }];
}

- (void)reloadPacks {
  MLNLogInfo(@"Reloading packs.");
  [self getPacksWithCompletionHandler:^(NSArray<MLNOfflinePack *> *packs,
                                        __unused NSError *_Nullable error) {
    for (MLNOfflinePack *pack in self.packs) {
      [pack invalidate];
    }
    self.packs = [packs mutableCopy];
  }];
}

- (void)getPacksWithCompletionHandler:(void (^)(NSArray<MLNOfflinePack *> *packs,
                                                NSError *_Nullable error))completion {
  __block NSMutableArray<MLNFFIOfflineRegionInfo *> *regions = [NSMutableArray array];
  mln_runtime runtime = [MLNFFIRuntime sharedRuntime].handle;
  [[MLNFFIRuntime sharedRuntime]
       callAsync:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
         return mln_runtime_list_offline_regions(runtime, completion, diagnostic);
       }
       consume:^(const mln_completion_result *result) {
         for (size_t i = 0; i < result->value_count; i++) {
           [regions addObject:MLNFFIOfflineRegionInfoFromC(MLN_STRIDED_AT(
                                  mln_offline_region_info, result->value, result->value_size, i))];
         }
       }
      completion:^(mln_status status, NSString *message) {
        NSError *error;
        NSMutableArray *packs;
        if (status != MLN_STATUS_OK) {
          error = [NSError errorWithDomain:MLNErrorDomain
                                      code:MLNErrorCodeUnknown
                                  userInfo:@{
                                    NSLocalizedDescriptionKey : message ?: @"",
                                  }];
        } else {
          packs = [NSMutableArray arrayWithCapacity:regions.count];
          for (MLNFFIOfflineRegionInfo *region in regions) {
            [packs addObject:[[MLNOfflinePack alloc] initWithRegionInfo:region]];
          }
        }
        if (completion) {
          completion(packs, error);
        }
      }];
}

- (void)setMaximumAllowedMapboxTiles:(uint64_t)maximumCount {
  MLNLogDebug(@"Setting maximumAllowedMapboxTiles: %lu", (unsigned long)maximumCount);
  MLNLogUnsupportedOnce(@"-[MLNOfflineStorage setMaximumAllowedMapboxTiles:]");
}

// MARK: - Ambient cache management

/// Runs a runtime cache call and reports its outcome on the main queue.
- (void)mgl_runCacheCall:(MLNFFISubmit)submit
               errorCode:(MLNErrorCode)errorCode
              completion:(void (^)(NSError *_Nullable))completion {
  [[MLNFFIRuntime sharedRuntime] callAsync:submit
                                   consume:nil
                                completion:^(mln_status status, NSString *message) {
                                  NSError *error;
                                  if (status != MLN_STATUS_OK) {
                                    error = [NSError
                                        errorWithDomain:MLNErrorDomain
                                                   code:errorCode
                                               userInfo:@{
                                                 NSLocalizedDescriptionKey : message ?: @"",
                                               }];
                                  }
                                  if (completion) {
                                    completion(error);
                                  }
                                }];
}

- (void)mgl_runAmbientCacheOperation:(mln_ambient_cache_operation)operation
                           errorCode:(MLNErrorCode)errorCode
                          completion:(void (^)(NSError *_Nullable))completion {
  mln_runtime runtime = [MLNFFIRuntime sharedRuntime].handle;
  [self mgl_runCacheCall:^(const mln_completion *callCompletion, mln_diagnostic *diagnostic) {
    return mln_runtime_run_ambient_cache_operation(runtime, operation, callCompletion, diagnostic);
  }
               errorCode:errorCode
              completion:completion];
}

- (void)setMaximumAmbientCacheSize:(NSUInteger)cacheSize
             withCompletionHandler:(void (^)(NSError *_Nullable))completion {
  mln_runtime runtime = [MLNFFIRuntime sharedRuntime].handle;
  [self mgl_runCacheCall:^(const mln_completion *callCompletion, mln_diagnostic *diagnostic) {
    return mln_runtime_set_maximum_ambient_cache_size(runtime, cacheSize, callCompletion,
                                                      diagnostic);
  }
               errorCode:MLNErrorCodeModifyingOfflineStorageFailed
              completion:completion];
}

- (void)invalidateAmbientCacheWithCompletionHandler:(void (^)(NSError *_Nullable))completion {
  [self mgl_runAmbientCacheOperation:MLN_AMBIENT_CACHE_OPERATION_INVALIDATE
                           errorCode:MLNErrorCodeModifyingOfflineStorageFailed
                          completion:completion];
}

- (void)clearAmbientCacheWithCompletionHandler:(void (^)(NSError *_Nullable error))completion {
  [self mgl_runAmbientCacheOperation:MLN_AMBIENT_CACHE_OPERATION_CLEAR
                           errorCode:MLNErrorCodeModifyingOfflineStorageFailed
                          completion:completion];
}

- (void)resetDatabaseWithCompletionHandler:(void (^)(NSError *_Nullable error))completion {
  [self mgl_runAmbientCacheOperation:MLN_AMBIENT_CACHE_OPERATION_RESET_DATABASE
                           errorCode:MLNErrorCodeUnknown
                          completion:completion];
}
// MARK: -

- (unsigned long long)countOfBytesCompleted {
  NSDictionary *attributes =
      [[NSFileManager defaultManager] attributesOfItemAtPath:self.databasePath error:NULL];
  return attributes.fileSize;
}

- (void)preloadData:(NSData *)data
              forURL:(NSURL *)url
    modificationDate:(nullable NSDate *)modified
      expirationDate:(nullable NSDate *)expires
                eTag:(nullable NSString *)eTag
      mustRevalidate:(BOOL)mustRevalidate {
  [self preloadData:data
                 forURL:url
       modificationDate:modified
         expirationDate:expires
                   eTag:eTag
         mustRevalidate:mustRevalidate
      completionHandler:nil];
}

- (void)preloadData:(NSData *)data
               forURL:(NSURL *)url
     modificationDate:(nullable NSDate *)modified
       expirationDate:(nullable NSDate *)expires
                 eTag:(nullable NSString *)eTag
       mustRevalidate:(BOOL)mustRevalidate
    completionHandler:(nullable MLNOfflinePreloadDataCompletionHandler)completion {
  // Classic forwarded the response into the database file source. The C API
  // cannot put a resource into the cache (C_API_GAPS.md).
  MLNLogUnsupportedOnce(@"-[MLNOfflineStorage preloadData:forURL:...]");
  if (completion) {
    NSError *error = [NSError
        errorWithDomain:MLNErrorDomain
                   code:MLNErrorCodeModifyingOfflineStorageFailed
               userInfo:@{
                 NSLocalizedDescriptionKey :
                     @"Preloading data into the cache is not supported by the MapLibre Native C API."
               }];
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(url, error);
    });
  }
}

- (void)putResourceWithUrl:(NSURL *)url
                      data:(NSData *)data
                  modified:(nullable NSDate *)modified
                   expires:(nullable NSDate *)expires
                      etag:(nullable NSString *)etag
            mustRevalidate:(BOOL)mustRevalidate {
  [self preloadData:data
                forURL:url
      modificationDate:modified
        expirationDate:expires
                  eTag:etag
        mustRevalidate:mustRevalidate];
}

@end
