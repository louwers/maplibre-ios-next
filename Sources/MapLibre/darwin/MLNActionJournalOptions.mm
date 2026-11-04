// Based on platform/darwin/src/MLNActionJournalOptions.mm at ios-v7.0.0
//
// mbgl::util::ActionJournalOptions held these values; its defaults
// (include/mln/util/action_journal_options.hpp) are reproduced here.

#import "MLNActionJournalOptions.h"

@implementation MLNActionJournalOptions {
  BOOL _enabled;
  NSString *_path;
  NSInteger _logFileSize;
  NSInteger _logFileCount;
  NSInteger _renderingStatsReportInterval;
}

- (instancetype)init {
  if (self = [super init]) {
    _enabled = NO;
    _logFileSize = 1024 * 1024;
    _logFileCount = 5;
    _renderingStatsReportInterval = 60;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    _path = [paths.firstObject stringByAppendingPathComponent:@""] ?: @"";
  }
  return self;
}

- (void)setEnabled:(BOOL)value {
  _enabled = value;
}

- (BOOL)enabled {
  return _enabled;
}

- (void)setPath:(NSString *)value {
  _path = [value copy] ?: @"";
}

- (NSString *)path {
  return _path;
}

- (void)setLogFileSize:(NSInteger)value {
  _logFileSize = static_cast<uint32_t>(value);
}

- (NSInteger)logFileSize {
  return _logFileSize;
}

- (void)setLogFileCount:(NSInteger)value {
  _logFileCount = static_cast<uint32_t>(value);
}

- (NSInteger)logFileCount {
  return _logFileCount;
}

- (void)setRenderingStatsReportInterval:(NSInteger)value {
  _renderingStatsReportInterval = static_cast<uint32_t>(value);
}

- (NSInteger)renderingStatsReportInterval {
  return _renderingStatsReportInterval;
}

@end
