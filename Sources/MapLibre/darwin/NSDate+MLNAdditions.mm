// Based on platform/darwin/src/NSDate+MLNAdditions.mm at ios-v7.0.0

#import "NSDate+MLNAdditions.h"

double MLNMillisecondsFromTimeInterval(NSTimeInterval duration) { return duration * 1000; }

NSTimeInterval MLNTimeIntervalFromMilliseconds(double milliseconds) { return milliseconds / 1000; }
