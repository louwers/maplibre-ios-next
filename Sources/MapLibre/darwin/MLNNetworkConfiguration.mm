// Based on platform/darwin/src/MLNNetworkConfiguration.mm at ios-v7.0.0

#import "MLNLoggingConfiguration_Private.h"
#import "MLNNetworkConfiguration_Private.h"
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import "MLNSettings_Private.h"
#endif

#import "MLNReachability.h"

#import <MaplibreNativeC/maplibre_native_c.h>

#import "MLNFFI.h"

#include <vector>

// The C API has no hook for the NSURLSession it downloads with. Its Apple build
// does compile the core's Objective-C network bridge
// (platform/darwin/core/native_apple_interface.m): the classes
// MLNNativeNetworkManager and MLNInternalNetworkResponse, whose delegate its
// HTTP file source asks for the session configuration, a custom session, and
// request and response rewriting, and tells about downloads. Those classes are
// not exported symbols, so they are looked up at run time; this SDK must not
// define classes with these names. If a later C API drops them, only the
// additional HTTP headers of the session configuration still apply, through the
// runtime's HTTP header transform (C_API_GAPS.md).

/// The class methods of MLNNativeNetworkManager this file uses.
@protocol MLNFFINativeNetworkManagerClass <NSObject>
+ (id)sharedManager;
@end

/// The instance interface of MLNNativeNetworkManager this file uses.
@protocol MLNFFINativeNetworkManager <NSObject>
@property (nonatomic, weak) id delegate;
@end

/// The class methods of MLNInternalNetworkResponse this file uses.
@protocol MLNFFIInternalNetworkResponseClass <NSObject>
+ (id)responseWithData:(NSData *)data urlResponse:(NSURLResponse *)response error:(NSError *)error;
@end

/// The instance interface of MLNInternalNetworkResponse this file uses.
@protocol MLNFFIInternalNetworkResponse <NSObject>
@property (retain, nullable) NSError *error;
@property (retain, nullable) NSData *data;
@property (retain, nullable) NSURLResponse *response;
@end

/// The C API's shared network manager, or nil if its build has none.
static id<MLNFFINativeNetworkManager> MLNFFINativeNetworkManager(void) {
  Class managerClass = NSClassFromString(@"MLNNativeNetworkManager");
  if (![managerClass respondsToSelector:@selector(sharedManager)]) {
    return nil;
  }
  return [(Class<MLNFFINativeNetworkManagerClass>)managerClass sharedManager];
}

static NSString *const MLNStartTime = @"start_time";
static NSString *const MLNResourceType = @"resource_type";
NSString *const kMLNDownloadPerformanceEvent = @"mobile.performance_trace";

@interface MLNNetworkConfiguration ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *events;
@property (nonatomic, weak) id<MLNNetworkConfigurationMetricsDelegate> metricsDelegate;
@property (nonatomic) dispatch_queue_t eventsQueue;

@end

@implementation MLNNetworkConfiguration {
  NSURLSessionConfiguration *_sessionConfig;
}

- (instancetype)init {
  if (self = [super init]) {
    self.sessionConfiguration = nil;
    _events = [NSMutableDictionary dictionary];
    _eventsQueue =
        dispatch_queue_create("org.maplibre.network-configuration", DISPATCH_QUEUE_CONCURRENT);
  }

  return self;
}

+ (instancetype)sharedManager {
  static dispatch_once_t onceToken;
  static MLNNetworkConfiguration *_sharedManager;
  dispatch_once(&onceToken, ^{
    _sharedManager = [[self alloc] init];
  });

  // Notice, this is reset for each call. This is primarily for testing purposes.
  // TODO: Consider only calling this for testing?
  [_sharedManager resetNativeNetworkManagerDelegate];

  return _sharedManager;
}

- (void)resetNativeNetworkManagerDelegate {
  // Tell core about our network integration. `delegate` here is not (yet)
  // intended to be set to nil, except for testing.
  id<MLNFFINativeNetworkManager> manager = MLNFFINativeNetworkManager();
  if (manager) {
    manager.delegate = self;
  } else {
    // Asynchronously: this runs while the runtime is being created, and the
    // header transform needs the runtime.
    dispatch_async(dispatch_get_main_queue(), ^{
      [self mgl_applyAdditionalHeadersWithHeaderTransform];
    });
  }
}

/// Without the network bridge, sends the session configuration's additional
/// HTTP headers through the runtime's header transform. The transform cannot
/// set User-Agent and other headers the C API manages.
- (void)mgl_applyAdditionalHeadersWithHeaderTransform {
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    MLNLogWarning(@"The MapLibre Native C API has no network manager to configure; only additional "
                  @"HTTP headers of the session configuration apply.");
  });
  NSDictionary *headers = self.sessionConfiguration.HTTPAdditionalHeaders;
  NSMutableArray<NSString *> *names = [NSMutableArray array];
  NSMutableArray<NSString *> *values = [NSMutableArray array];
  for (id name in headers) {
    if (![name isKindOfClass:[NSString class]] ||
        [(NSString *)name caseInsensitiveCompare:@"User-Agent"] == NSOrderedSame) {
      continue;
    }
    [names addObject:name];
    [values addObject:[headers[name] description]];
  }
  if (!names.count) {
    return;
  }
  std::vector<mln_http_header> cHeaders;
  for (NSUInteger i = 0; i < names.count; i++) {
    cHeaders.push_back({MLNFFIBufferView(names[i]), MLNFFIBufferView(values[i])});
  }
  mln_http_header_rule rule = {sizeof(mln_http_header_rule)};
  rule.kinds = MLN_RESOURCE_KIND_FLAG_ALL;
  rule.flags = MLN_URL_MATCH_GLOB;
  rule.url = MLNFFIBufferView(@"*");
  rule.headers = cHeaders.data();
  rule.header_count = cHeaders.size();
  mln_http_header_transform transform = {sizeof(mln_http_header_transform)};
  transform.rules = &rule;
  transform.rule_count = 1;
  mln_runtime runtime = [MLNFFIRuntime sharedRuntime].handle;
  NSString *message;
  if ([[MLNFFIRuntime sharedRuntime]
             call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
               return mln_runtime_set_http_header_transform(runtime, &transform, completion,
                                                            diagnostic);
             }
          consume:nil
          message:&message] != MLN_STATUS_OK) {
    MLNLogError(@"Failed to set HTTP headers: %@", message);
  }
}

+ (NSURLSessionConfiguration *)defaultSessionConfiguration {
  NSURLSessionConfiguration *sessionConfiguration =
      [NSURLSessionConfiguration defaultSessionConfiguration];

  sessionConfiguration.timeoutIntervalForResource = 30;
  sessionConfiguration.HTTPMaximumConnectionsPerHost = 8;
  sessionConfiguration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
  sessionConfiguration.URLCache = nil;

  return sessionConfiguration;
}

// MARK: - MLNNativeNetworkDelegate

- (NSURLSession *)sessionForNetworkManager:(id)networkManager {
  // Note: this method is NOT called on the main thread.
  NSURLSession *session;
  if ([self.delegate respondsToSelector:@selector(sessionForNetworkConfiguration:)]) {
    session = [self.delegate sessionForNetworkConfiguration:self];
  }

  // Check for a background session; string checking is fragile, but this is not
  // a deal breaker as we're only doing this to provide more clarity to the
  // developer
  NSAssert(![session isKindOfClass:NSClassFromString(@"__NSURLBackgroundSession")],
           @"Background NSURLSessions are not yet supported");

  if (session.delegate) {
    NSAssert(![session.delegate conformsToProtocol:@protocol(NSURLSessionDataDelegate)],
             @"Session delegates conforming to NSURLSessionDataDelegate are not yet supported");
  }

  return session;
}

- (NSMutableURLRequest *)willSendRequest:(NSMutableURLRequest *)request {
  if ([self.delegate respondsToSelector:@selector(willSendRequest:)]) {
    return [self.delegate willSendRequest:request];
  }

  return request;
}

- (id)didReceiveResponse:(id<MLNFFIInternalNetworkResponse>)response {
  if ([self.delegate respondsToSelector:@selector(didReceiveResponse:)]) {
    MLNNetworkResponse *tempResponse = [MLNNetworkResponse responseWithData:response.data
                                                                urlResponse:response.response
                                                                      error:response.error];
    tempResponse = [self.delegate didReceiveResponse:tempResponse];
    if (tempResponse) {
      Class<MLNFFIInternalNetworkResponseClass> responseClass =
          (Class<MLNFFIInternalNetworkResponseClass>)NSClassFromString(
              @"MLNInternalNetworkResponse");
      return [responseClass responseWithData:tempResponse.data
                                 urlResponse:tempResponse.response
                                       error:tempResponse.error];
    } else {
      return nil;
    }
  }

  return response;
}

- (NSURLSessionConfiguration *)sessionConfiguration {
  NSURLSessionConfiguration *sessionConfig = nil;
  @synchronized(self) {
    sessionConfig = _sessionConfig;
  }
  return sessionConfig;
}

- (void)setSessionConfiguration:(NSURLSessionConfiguration *)sessionConfiguration {
  @synchronized(self) {
    if (sessionConfiguration == nil) {
      _sessionConfig = [MLNNetworkConfiguration defaultSessionConfiguration];
    } else {
      _sessionConfig = sessionConfiguration;
    }
  }
}

- (void)startDownloadEvent:(NSString *)urlString type:(NSString *)resourceType {
  if (urlString && resourceType && ![self eventDictionaryForKey:urlString]) {
    NSDate *startDate = [NSDate date];
    [self setEventDictionary:@{MLNStartTime : startDate, MLNResourceType : resourceType}
                      forKey:urlString];
  }
}

- (void)stopDownloadEventForResponse:(NSURLResponse *)response {
  [self sendEventForURLResponse:response withAction:nil];
}

- (void)cancelDownloadEventForResponse:(NSURLResponse *)response {
  [self sendEventForURLResponse:response withAction:@"cancel"];
}

- (void)debugLog:(NSString *)message {
  MLNLogDebug(message);
}

- (void)errorLog:(NSString *)message {
  MLNLogError(message);
}

// MARK: - Event management

- (void)sendEventForURLResponse:(NSURLResponse *)response withAction:(NSString *)action {
  if ([response isKindOfClass:[NSURLResponse class]]) {
    NSString *urlString = response.URL.relativePath;
    if (urlString && [self eventDictionaryForKey:urlString]) {
      NSDictionary *eventAttributes = [self eventAttributesForURL:response withAction:action];
      [self removeEventDictionaryForKey:urlString];

      dispatch_async(dispatch_get_main_queue(), ^{
        [self.metricsDelegate networkConfiguration:self didGenerateMetricEvent:eventAttributes];
      });
    }
  }
}

- (NSDictionary *)eventAttributesForURL:(NSURLResponse *)response withAction:(NSString *)action {
  NSString *urlString = response.URL.relativePath;
  NSDictionary *parameters = [self eventDictionaryForKey:urlString];
  NSDate *startDate = [parameters objectForKey:MLNStartTime];
  NSDate *endDate = [NSDate date];
  NSTimeInterval elapsedTime = [endDate timeIntervalSinceDate:startDate];
  NSDateFormatter *iso8601Formatter = [[NSDateFormatter alloc] init];
  iso8601Formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
  NSString *createdDate = [iso8601Formatter stringFromDate:[NSDate date]];

  NSMutableArray *attributes = [NSMutableArray array];
  [attributes addObject:@{@"name" : @"requestUrl", @"value" : urlString}];
  [attributes
      addObject:@{@"name" : MLNResourceType, @"value" : [parameters objectForKey:MLNResourceType]}];

  if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
    NSInteger responseCode = [(NSHTTPURLResponse *)response statusCode];
    [attributes addObject:@{@"name" : @"responseCode", @"value" : @(responseCode)}];
  }

  BOOL isWIFIOn = [[MLNReachability reachabilityWithHostName:response.URL.host] isReachableViaWiFi];
  [attributes addObject:@{@"name" : @"wifiOn", @"value" : @(isWIFIOn)}];

  if (action) {
    [attributes addObject:@{@"name" : @"action", @"value" : action}];
  }

  double elapsedTimeInMS = elapsedTime * 1000.0;

  return @{
    @"event" : kMLNDownloadPerformanceEvent,
    @"created" : createdDate,
    @"sessionId" : [NSUUID UUID].UUIDString,
    @"counters" : @[ @{@"name" : @"elapsedMS", @"value" : @(elapsedTimeInMS)} ],
    @"attributes" : attributes
  };
}

// MARK: - Events dictionary access

- (nullable NSDictionary *)eventDictionaryForKey:(nonnull NSString *)key {
  __block NSDictionary *dictionary;

  dispatch_sync(self.eventsQueue, ^{
    dictionary = [self.events objectForKey:key];
  });

  return dictionary;
}

- (void)setEventDictionary:(nonnull NSDictionary *)dictionary forKey:(nonnull NSString *)key {
  dispatch_barrier_async(self.eventsQueue, ^{
    [self.events setObject:dictionary forKey:key];
  });
}

- (void)removeEventDictionaryForKey:(nonnull NSString *)key {
  dispatch_barrier_async(self.eventsQueue, ^{
    [self.events removeObjectForKey:key];
  });
}

@end

@implementation MLNNetworkConfiguration (ForTesting)

+ (void)testing_clearNativeNetworkManagerDelegate {
  MLNFFINativeNetworkManager().delegate = nil;
}

+ (id)testing_nativeNetworkManagerDelegate {
  return MLNFFINativeNetworkManager().delegate;
}

@end
