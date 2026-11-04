// Based on platform/darwin/src/MLNNetworkConfiguration_Private.h at ios-v7.0.0
//
// Classic included the core's native_apple_interface.h to implement
// MLNNativeNetworkDelegate. The C API exports no Objective-C, but its Apple
// build still compiles that interface; see MLNNetworkConfiguration.mm.

#import "MLNNetworkConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

@class MLNNetworkConfiguration;
@protocol MLNNetworkConfigurationMetricsDelegate <NSObject>

- (void)networkConfiguration:(MLNNetworkConfiguration *)networkConfiguration
      didGenerateMetricEvent:(NSDictionary *)metricEvent;

@end

extern NSString *const kMLNDownloadPerformanceEvent;

@interface MLNNetworkConfiguration (Private)

@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *events;
@property (nonatomic, weak) id<MLNNetworkConfigurationMetricsDelegate> metricsDelegate;

- (void)resetNativeNetworkManagerDelegate;
- (void)startDownloadEvent:(NSString *)urlString type:(NSString *)resourceType;
- (void)stopDownloadEventForResponse:(NSURLResponse *)response;
- (void)cancelDownloadEventForResponse:(NSURLResponse *)response;
@end

NS_ASSUME_NONNULL_END
