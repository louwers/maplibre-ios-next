#import "MLNFFI.h"

#import "MLNLoggingConfiguration_Private.h"

#include <os/lock.h>

// MARK: - Values

mln_buffer_view MLNFFIBufferView(NSString *string) {
  if (!string) {
    return (mln_buffer_view){NULL, 0};
  }
  const char *bytes = string.UTF8String;
  return (mln_buffer_view){bytes, strlen(bytes)};
}

NSString *MLNFFIStringFromBufferView(mln_buffer_view view) {
  if (!view.data) {
    return nil;
  }
  return [[NSString alloc] initWithBytes:view.data length:view.size encoding:NSUTF8StringEncoding];
}

NSData *MLNFFIDataFromBufferView(mln_buffer_view view) {
  if (!view.data) {
    return nil;
  }
  return [NSData dataWithBytes:view.data length:view.size];
}

id MLNFFIJSONObjectFromBufferView(mln_buffer_view view) {
  if (!view.data || !view.size) {
    return nil;
  }
  NSData *data = [NSData dataWithBytesNoCopy:(void *)view.data length:view.size freeWhenDone:NO];
  NSError *error;
  id object = [NSJSONSerialization JSONObjectWithData:data
                                              options:NSJSONReadingFragmentsAllowed
                                                error:&error];
  if (!object) {
    MLNLogError(@"Failed to parse JSON from the C API: %@", error);
  }
  return object;
}

NSString *MLNFFIJSONStringFromObject(id object) {
  if (!object) {
    object = [NSNull null];
  }
  NSError *error;
  NSData *data = [NSJSONSerialization dataWithJSONObject:object
                                                 options:NSJSONWritingFragmentsAllowed
                                                   error:&error];
  if (!data) {
    [NSException raise:NSInvalidArgumentException
                format:@"Value cannot be represented as JSON: %@ (%@)", object, error];
  }
  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

mln_lat_lng MLNFFILatLng(CLLocationCoordinate2D coordinate) {
  return (mln_lat_lng){coordinate.latitude, coordinate.longitude};
}

CLLocationCoordinate2D MLNFFICoordinate(mln_lat_lng latLng) {
  return CLLocationCoordinate2DMake(latLng.latitude, latLng.longitude);
}

mln_lat_lng_bounds MLNFFILatLngBounds(MLNCoordinateBounds bounds) {
  return (mln_lat_lng_bounds){MLNFFILatLng(bounds.sw), MLNFFILatLng(bounds.ne)};
}

MLNCoordinateBounds MLNFFICoordinateBounds(mln_lat_lng_bounds bounds) {
  return MLNCoordinateBoundsMake(MLNFFICoordinate(bounds.southwest),
                                 MLNFFICoordinate(bounds.northeast));
}

NSString *MLNFFIStatusDescription(mln_status status) {
  switch (status) {
    case MLN_STATUS_OK:
      return @"OK";
    case MLN_STATUS_INVALID_ARGUMENT:
      return @"invalid argument";
    case MLN_STATUS_INVALID_STATE:
      return @"invalid state";
    case MLN_STATUS_WRONG_THREAD:
      return @"wrong thread";
    case MLN_STATUS_UNSUPPORTED:
      return @"unsupported";
    case MLN_STATUS_NATIVE_ERROR:
      return @"native error";
    case MLN_STATUS_CANCELLED:
      return @"cancelled";
    case MLN_STATUS_BUSY:
      return @"busy";
    case MLN_STATUS_TARGET_LOST:
      return @"target lost";
    case MLN_STATUS_NOT_READY:
      return @"not ready";
    case MLN_STATUS_NOT_FOUND:
      return @"not found";
  }
  return [NSString stringWithFormat:@"status %d", status];
}

// MARK: - Completions

// Owns one submission's callback state. Blocking calls keep it alive
// themselves; asynchronous calls transfer a retained reference to the C API.
@interface MLNFFICall : NSObject
@property (nonatomic, copy, nullable) MLNFFIConsume consume;
@property (nonatomic, nullable) dispatch_semaphore_t done;
@property (nonatomic) mln_status status;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, copy, nullable) void (^completion)(mln_status, NSString *);
@end

@implementation MLNFFICall
@end

static void MLNFFICompletionCallback(void *userData, const mln_completion_result *result) {
  MLNFFICall *call = (__bridge MLNFFICall *)userData;
  call.status = result->status;
  call.message = MLNFFIStringFromBufferView(result->diagnostic) ?: @"";
  if (call.consume) {
    call.consume(result);
  }
  if (call.completion) {
    void (^completion)(mln_status, NSString *) = call.completion;
    mln_status status = call.status;
    NSString *message = call.message;
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(status, message);
    });
  }
  if (call.done) {
    dispatch_semaphore_signal(call.done);
  }
}

static void MLNFFIReleaseCall(void *userData) { CFBridgingRelease(userData); }

// Submits and blocks. The call object stays alive on this stack frame, so the
// C API borrows it without a release callback.
static mln_status MLNFFICallBlocking(MLNFFISubmit submit, MLNFFIConsume consume,
                                     NSString **message) {
  MLNFFICall *call = [MLNFFICall new];
  call.consume = consume;
  call.done = dispatch_semaphore_create(0);
  mln_completion completion = {sizeof(mln_completion), MLNFFICompletionCallback,
                               (__bridge void *)call, NULL, MLN_HANDLE_NULL};
  mln_diagnostic diagnostic = {sizeof(mln_diagnostic)};
  diagnostic.message[0] = '\0';
  mln_status status = submit(&completion, &diagnostic);
  if (status != MLN_STATUS_OK) {
    if (message) {
      *message = @(diagnostic.message);
    }
    return status;
  }
  dispatch_semaphore_wait(call.done, DISPATCH_TIME_FOREVER);
  if (message) {
    *message = call.message;
  }
  return call.status;
}

static void MLNFFICallAsync(MLNFFISubmit submit, MLNFFIConsume consume,
                            void (^completionBlock)(mln_status, NSString *)) {
  MLNFFICall *call = [MLNFFICall new];
  call.consume = consume;
  call.completion = completionBlock;
  void *userData = (void *)CFBridgingRetain(call);
  mln_completion completion = {sizeof(mln_completion), MLNFFICompletionCallback, userData,
                               MLNFFIReleaseCall, MLN_HANDLE_NULL};
  mln_diagnostic diagnostic = {sizeof(mln_diagnostic)};
  diagnostic.message[0] = '\0';
  mln_status status = submit(&completion, &diagnostic);
  if (status != MLN_STATUS_OK) {
    CFBridgingRelease(userData);
    if (completionBlock) {
      NSString *message = @(diagnostic.message);
      dispatch_async(dispatch_get_main_queue(), ^{
        completionBlock(status, message);
      });
    }
  }
}

// MARK: - Events

@implementation MLNFFIEvent

- (instancetype)initWithEvent:(const mln_runtime_event *)event {
  if (self = [super init]) {
    _type = event->type;
    _sourceType = event->source_type;
    _source = event->source;
    _generation = event->generation;
    _code = event->code;
    _message = MLNFFIStringFromBufferView(event->message) ?: @"";
    _payloadType = event->payload_type;
    _payload = event->payload;
    if (_payloadType == MLN_RUNTIME_EVENT_PAYLOAD_GLYPHS) {
      NSMutableArray *fontStack = [NSMutableArray array];
      for (size_t i = 0; i < event->payload.glyphs.font_count; i++) {
        [fontStack addObject:MLNFFIStringFromBufferView(event->payload.glyphs.font_stack[i]) ?: @""];
      }
      _fontStack = fontStack;
      _payload.glyphs.font_stack = NULL;
    } else if (_payloadType == MLN_RUNTIME_EVENT_PAYLOAD_SPRITE) {
      _spriteIdentifier = MLNFFIStringFromBufferView(event->payload.sprite.id);
      _spriteURL = MLNFFIStringFromBufferView(event->payload.sprite.url);
      _payload.sprite.id = (mln_buffer_view){NULL, 0};
      _payload.sprite.url = (mln_buffer_view){NULL, 0};
    }
  }
  return self;
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<MLNFFIEvent type=%u source=%llu generation=%llu code=%u message=%@>",
                                    self.type, self.source, self.generation, self.code, self.message];
}

@end

// MARK: - Map registry

// Maps handles to the MLNFFIMap objects that queue their events. The runtime
// worker reads it; maps register and unregister on any thread.
@interface MLNFFIMap ()
- (void)enqueueEvent:(MLNFFIEvent *)event;
@end

static os_unfair_lock MLNFFIRegistryLock = OS_UNFAIR_LOCK_INIT;
static NSMapTable<NSNumber *, MLNFFIMap *> *MLNFFIRegistry() {
  static NSMapTable *registry;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    registry = [NSMapTable strongToWeakObjectsMapTable];
  });
  return registry;
}

static void MLNFFIRuntimeEventCallback(void *userData, const mln_event_batch_view *batch) {
  for (size_t i = 0; i < batch->event_count; i++) {
    const mln_runtime_event *event =
        MLN_STRIDED_AT(mln_runtime_event, batch->events, batch->event_size, i);
    MLNFFIEvent *copy = [[MLNFFIEvent alloc] initWithEvent:event];
    if (event->source_type == MLN_RUNTIME_EVENT_SOURCE_MAP) {
      os_unfair_lock_lock(&MLNFFIRegistryLock);
      MLNFFIMap *map = [MLNFFIRegistry() objectForKey:@(event->source)];
      os_unfair_lock_unlock(&MLNFFIRegistryLock);
      [map enqueueEvent:copy];
    } else {
      dispatch_async(dispatch_get_main_queue(), ^{
        [[MLNFFIRuntime sharedRuntime].runtimeEventObserver ffiRuntimeDidReceiveEvent:copy];
      });
    }
  }
}

// MARK: - Runtime

static void MLNFFICompleteFileResourceRequest(mln_resource_request handle, NSData *data,
                                              NSError *error) {
  NSString *errorMessage;
  mln_resource_response response = {sizeof(mln_resource_response)};
  if (error) {
    // As classic's HTTP file source reported a failed file: request.
    errorMessage = error.localizedDescription;
    response.status = MLN_RESOURCE_RESPONSE_STATUS_ERROR;
    response.error_reason = MLN_RESOURCE_ERROR_REASON_OTHER;
    response.error_message = MLNFFIBufferView(errorMessage);
  } else {
    response.status = MLN_RESOURCE_RESPONSE_STATUS_OK;
  }
  if (data) {
    response.bytes = (const uint8_t *)data.bytes;
    response.byte_count = data.length;
  }
  mln_diagnostic diagnostic = {sizeof(mln_diagnostic)};
  if (mln_resource_request_complete(handle, &response, &diagnostic) != MLN_STATUS_OK) {
    mln_resource_request_release(handle);
  }
}

static void MLNFFIFileResourceProviderCallback(void *userData,
                                               const mln_resource_request_info *request,
                                               mln_resource_request handle) {
  NSString *string = MLNFFIStringFromBufferView(request->resolved_url);
  NSURL *url = string ? [NSURL URLWithString:string] : nil;
  if (!url) {
    NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil];
    MLNFFICompleteFileResourceRequest(handle, nil, error);
    return;
  }
  // NSURLSession, as classic read these URLs, so errors have its wording.
  NSURLSessionDataTask *task = [NSURLSession.sharedSession
        dataTaskWithURL:url
      completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        MLNFFICompleteFileResourceRequest(handle, data, error);
      }];
  [task resume];
}

static NSString *MLNFFIConfiguredCachePath;
static BOOL MLNFFICachePathConfigured;
static NSString *_Nullable (^MLNFFIDefaultCachePathProvider)(void);

@implementation MLNFFIRuntime

+ (void)setCachePath:(NSString *)path {
  MLNFFIConfiguredCachePath = [path copy];
  MLNFFICachePathConfigured = YES;
}

+ (NSString *)cachePath {
  return MLNFFIConfiguredCachePath;
}

+ (void)setDefaultCachePathProvider:(NSString *_Nullable (^)(void))provider {
  MLNFFIDefaultCachePathProvider = [provider copy];
}

+ (instancetype)sharedRuntime {
  static MLNFFIRuntime *runtime;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    runtime = [[MLNFFIRuntime alloc] initShared];
  });
  return runtime;
}

- (instancetype)initShared {
  if (self = [super init]) {
    // Route core logs through MLNLoggingConfiguration before anything can log.
    [MLNLoggingConfiguration sharedConfiguration];
    mln_diagnostic diagnostic = {sizeof(mln_diagnostic)};

    NSString *cachePath = MLNFFIConfiguredCachePath;
    if (!MLNFFICachePathConfigured && MLNFFIDefaultCachePathProvider) {
      cachePath = MLNFFIDefaultCachePathProvider();
    }
    // Classic resolved asset:// URLs against the main bundle's resources.
    NSString *assetPath = [NSBundle mainBundle].resourceURL.path;
    mln_runtime_options options = {sizeof(mln_runtime_options)};
    options.cache_path = MLNFFIBufferView(cachePath);
    options.asset_path = MLNFFIBufferView(assetPath);
    if (mln_runtime_create(&options, &_handle, &diagnostic) != MLN_STATUS_OK) {
      [NSException raise:NSInternalInconsistencyException
                  format:@"Failed to create the MapLibre Native runtime: %s", diagnostic.message];
    }

    mln_runtime_event_handler handler = {sizeof(mln_runtime_event_handler)};
    handler.callback = MLNFFIRuntimeEventCallback;
    mln_runtime runtime = _handle;
    NSString *message;
    mln_status status = MLNFFICallBlocking(
        ^(const mln_completion *completion, mln_diagnostic *diagnostic) {
          return mln_runtime_set_event_handler(runtime, &handler, completion, diagnostic);
        },
        nil, &message);
    if (status != MLN_STATUS_OK) {
      MLNLogError(@"Failed to set the runtime event handler: %@", message);
    }

    // Offline downloads fetch every resource through the network loader, which
    // in classic was NSURLSession and so also read file:// URLs. The C API's
    // network loader refuses them, so this provider reads them instead. Map
    // loads never reach it: they read file:// URLs from disk before the network.
    mln_resource_route route = {sizeof(mln_resource_route)};
    route.flags = MLN_URL_MATCH_GLOB;
    route.url = MLNFFIBufferView(@"file://**");
    mln_resource_provider provider = {sizeof(mln_resource_provider)};
    provider.callback = MLNFFIFileResourceProviderCallback;
    provider.routes = &route;
    provider.route_count = 1;
    status = MLNFFICallBlocking(
        ^(const mln_completion *completion, mln_diagnostic *diagnostic) {
          return mln_runtime_set_resource_provider(runtime, &provider, completion, diagnostic);
        },
        nil, &message);
    if (status != MLN_STATUS_OK) {
      MLNLogError(@"Failed to set the file resource provider: %@", message);
    }
  }
  return self;
}

- (mln_status)call:(MLNFFISubmit)submit
           consume:(MLNFFIConsume)consume
           message:(NSString **)message {
  return MLNFFICallBlocking(submit, consume, message);
}

- (void)callAsync:(MLNFFISubmit)submit
          consume:(MLNFFIConsume)consume
       completion:(void (^)(mln_status, NSString *))completion {
  MLNFFICallAsync(submit, consume, completion);
}

@end

// MARK: - Map

/// Events classic's core raised during the call that caused them: camera
/// changes and the start of a style load.
static const mln_runtime_event_flags MLNFFIDefaultSynchronousEventTypes =
    MLN_RUNTIME_EVENT_FLAG_MAP_CAMERA_WILL_CHANGE | MLN_RUNTIME_EVENT_FLAG_MAP_CAMERA_IS_CHANGING |
    MLN_RUNTIME_EVENT_FLAG_MAP_CAMERA_DID_CHANGE | MLN_RUNTIME_EVENT_FLAG_MAP_LOADING_STARTED;

@implementation MLNFFIMap {
  mln_runtime_event_flags _synchronousEventTypes;
  os_unfair_lock _eventLock;
  NSMutableArray<MLNFFIEvent *> *_events;
  BOOL _drainScheduled;
  BOOL _draining;
  BOOL _invalidated;
}

- (instancetype)initWithSize:(CGSize)size scaleFactor:(double)scaleFactor mode:(mln_map_mode)mode {
  if (self = [super init]) {
    _eventLock = OS_UNFAIR_LOCK_INIT;
    _events = [NSMutableArray array];
    _scaleFactor = scaleFactor;
    mln_runtime runtime = [MLNFFIRuntime sharedRuntime].handle;
    mln_map_options options = {sizeof(mln_map_options)};
    options.initial_extent = (mln_logical_extent){(uint32_t)MAX(1, round(size.width)),
                                                  (uint32_t)MAX(1, round(size.height)), scaleFactor};
    options.map_mode = mode;
    __block mln_map handle = MLN_HANDLE_NULL;
    __block mln_map *out = &handle;
    // Register before the map can raise events: the handle is known when the
    // submit returns, before the creation completes.
    __weak MLNFFIMap *weakSelf = self;
    NSString *message;
    mln_status status = MLNFFICallBlocking(
        ^(const mln_completion *completion, mln_diagnostic *diagnostic) {
          mln_status submitted =
              mln_runtime_create_map(runtime, &options, out, completion, diagnostic);
          if (submitted == MLN_STATUS_OK) {
            os_unfair_lock_lock(&MLNFFIRegistryLock);
            [MLNFFIRegistry() setObject:weakSelf forKey:@(*out)];
            os_unfair_lock_unlock(&MLNFFIRegistryLock);
          }
          return submitted;
        },
        nil, &message);
    _handle = handle;
    if (status != MLN_STATUS_OK) {
      MLNLogError(@"Failed to create a map: %@ (%@)", message, MLNFFIStatusDescription(status));
      [self invalidate];
      return nil;
    }
  }
  return self;
}

+ (instancetype)scratchMap {
  static MLNFFIMap *map;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    map = [[MLNFFIMap alloc] initWithSize:CGSizeMake(64, 64) scaleFactor:1 mode:MLN_MAP_MODE_STATIC];
    mln_map handle = map.handle;
    [map perform:@"load the scratch style"
          submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
            return mln_map_set_style_json(
                handle, MLNFFIBufferView(@"{\"version\":8,\"sources\":{},\"layers\":[]}"),
                completion, diagnostic);
          }];
  });
  return map;
}

- (void)dealloc {
  [self invalidate];
}

- (void)invalidate {
  if (_invalidated) {
    return;
  }
  _invalidated = YES;
  if (_handle != MLN_HANDLE_NULL) {
    os_unfair_lock_lock(&MLNFFIRegistryLock);
    [MLNFFIRegistry() removeObjectForKey:@(_handle)];
    os_unfair_lock_unlock(&MLNFFIRegistryLock);
    mln_diagnostic diagnostic = {sizeof(mln_diagnostic)};
    if (mln_map_release(_handle, NULL, &diagnostic) != MLN_STATUS_OK) {
      mln_map_dispose(_handle, &diagnostic);
    }
  }
}

- (mln_status)call:(MLNFFISubmit)submit
           consume:(MLNFFIConsume)consume
           message:(NSString **)message {
  if (![NSThread isMainThread]) {
    return MLNFFICallBlocking(submit, consume, message);
  }
  mln_status status = MLNFFICallBlocking(submit, consume, message);
  [self drainEventsOfTypes:self.synchronousEventTypes];
  return status;
}

- (mln_status)callReplacingEventsOfTypes:(mln_runtime_event_flags)types
                                  submit:(MLNFFISubmit)submit
                                 message:(NSString **)message {
  __block uint64_t generation = UINT64_MAX;
  mln_status status = MLNFFICallBlocking(
      submit,
      ^(const mln_completion_result *result) {
        if (result->generation) {
          generation = result->generation;
        }
      },
      message);
  os_unfair_lock_lock(&_eventLock);
  NSIndexSet *stale = [_events indexesOfObjectsPassingTest:^BOOL(MLNFFIEvent *event, NSUInteger i, BOOL *stop) {
    return event.generation < generation && (types & (1ULL << event.type));
  }];
  [_events removeObjectsAtIndexes:stale];
  os_unfair_lock_unlock(&_eventLock);
  if ([NSThread isMainThread]) {
    [self drainEventsOfTypes:self.synchronousEventTypes];
  }
  return status;
}

- (mln_runtime_event_flags)synchronousEventTypes {
  return _synchronousEventTypes ?: MLNFFIDefaultSynchronousEventTypes;
}

- (BOOL)perform:(NSString *)label submit:(MLNFFISubmit)submit {
  NSString *message;
  mln_status status = [self call:submit consume:nil message:&message];
  if (status != MLN_STATUS_OK) {
    MLNLogError(@"Failed to %@: %@ (%@)", label, message, MLNFFIStatusDescription(status));
    return NO;
  }
  return YES;
}

- (void)post:(NSString *)label submit:(MLNFFISubmit)submit {
  MLNFFICallAsync(submit, nil, ^(mln_status status, NSString *message) {
    if (status != MLN_STATUS_OK) {
      MLNLogError(@"Failed to %@: %@ (%@)", label, message, MLNFFIStatusDescription(status));
    }
  });
}

- (void)callAsync:(MLNFFISubmit)submit
          consume:(MLNFFIConsume)consume
       completion:(void (^)(mln_status, NSString *))completion {
  MLNFFICallAsync(submit, consume, completion);
}

- (mln_map_snapshot)snapshot {
  mln_map_snapshot snapshot = {sizeof(mln_map_snapshot)};
  mln_diagnostic diagnostic = {sizeof(mln_diagnostic)};
  mln_map_get_snapshot(_handle, &snapshot, &diagnostic);
  return snapshot;
}

- (void)enqueueEvent:(MLNFFIEvent *)event {
  BOOL schedule = NO;
  os_unfair_lock_lock(&_eventLock);
  [_events addObject:event];
  if (!_drainScheduled) {
    _drainScheduled = YES;
    schedule = YES;
  }
  os_unfair_lock_unlock(&_eventLock);
  if (schedule) {
    __weak MLNFFIMap *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      [weakSelf drainEvents];
    });
  }
}

- (void)drainEvents {
  [self drainEventsOfTypes:MLN_RUNTIME_EVENT_FLAG_ALL];
}

// Delivers the queued events whose types are in `types`, in order. Events of
// other types stay queued, in order, for the asynchronous drain: after a
// call, classic delivered only the events that the call itself raised
// (camera changes, ...), while everything else (style and tile loads,
// rendering, idleness) came on later turns of the run loop.
- (void)drainEventsOfTypes:(mln_runtime_event_flags)types {
  NSAssert([NSThread isMainThread], @"Map events are delivered on the main thread.");
  // An observer that makes a blocking call drains again; deliver the rest of
  // this batch in order from the outer drain.
  if (_draining) {
    return;
  }
  _draining = YES;
  while (true) {
    os_unfair_lock_lock(&_eventLock);
    NSMutableArray<MLNFFIEvent *> *events = [NSMutableArray array];
    NSMutableArray<MLNFFIEvent *> *kept = [NSMutableArray array];
    for (MLNFFIEvent *event in _events) {
      [(types & (1ULL << event.type)) ? events : kept addObject:event];
    }
    [_events setArray:kept];
    if (types == MLN_RUNTIME_EVENT_FLAG_ALL) {
      // A full drain empties the queue; later events schedule another.
      _drainScheduled = NO;
    }
    BOOL schedule = _events.count > 0 && !_drainScheduled;
    if (schedule) {
      _drainScheduled = YES;
    }
    os_unfair_lock_unlock(&_eventLock);
    if (schedule) {
      __weak MLNFFIMap *weakSelf = self;
      dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf drainEvents];
      });
    }
    if (!events.count) {
      break;
    }
    id<MLNFFIMapEventObserver> observer = self.eventObserver;
    for (MLNFFIEvent *event in events) {
      [observer ffiMap:self didReceiveEvent:event];
    }
  }
  _draining = NO;
}

@end
