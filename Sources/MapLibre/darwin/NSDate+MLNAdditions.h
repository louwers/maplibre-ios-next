// Based on platform/darwin/src/NSDate+MLNAdditions.h at ios-v7.0.0
//
// The C API takes durations in milliseconds, where the core took
// std::chrono durations.

#import <Foundation/Foundation.h>

#import "MLNFoundation.h"

NS_ASSUME_NONNULL_BEGIN

/// Converts from a duration in seconds to a duration in milliseconds.
MLN_EXPORT
double MLNMillisecondsFromTimeInterval(NSTimeInterval duration);

/// Converts from a duration in milliseconds to a duration in seconds.
MLN_EXPORT
NSTimeInterval MLNTimeIntervalFromMilliseconds(double milliseconds);

NS_ASSUME_NONNULL_END
