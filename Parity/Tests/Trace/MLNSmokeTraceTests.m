#import <XCTest/XCTest.h>

@import MapLibre;

#import "ParityRecorder.h"

/// Records basic facts about the implementation under test.
@interface MLNSmokeTraceTests : XCTestCase
@end

@implementation MLNSmokeTraceTests

- (void)testFramework {
  ParityRecorder *recorder = [ParityRecorder recorderForTest:self];
  [recorder record:@"mapViewClass" value:NSStringFromClass([MLNMapView class])];
  [recorder record:@"defaultStyleURL" block:^id {
    return [MLNStyle defaultStyleURL];
  }];
}

@end
