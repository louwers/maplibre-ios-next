// Copied from platform/darwin/test/MLNComputedShapeSourceTests.m at ios-v7.0.0 by Parity/Tests/Upstream/import-upstream.py.
// See ADAPTATIONS.md before editing.

#import <XCTest/XCTest.h>

@import MapLibre;


@interface MLNComputedShapeSourceTests : XCTestCase
@end

@implementation MLNComputedShapeSourceTests

- (void)testInitializer {
    MLNComputedShapeSource *source = [[MLNComputedShapeSource alloc] initWithIdentifier:@"id" options:@{}];
    XCTAssertNotNil(source);
    XCTAssertNotNil(source.requestQueue);
    XCTAssertNil(source.dataSource);
}

- (void)testNilOptions {
    MLNComputedShapeSource *source = [[MLNComputedShapeSource alloc] initWithIdentifier:@"id" options:nil];
    XCTAssertNotNil(source);
}


@end
