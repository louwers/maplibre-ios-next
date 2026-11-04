// Copied from platform/darwin/test/MLNTestAssertionHandler.h at ios-v7.0.0 by Parity/Tests/Upstream/import-upstream.py.
// See ADAPTATIONS.md before editing.

@import MapLibre;
#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

// Use to catch or log assertions that occur in dispatch blocks, timers or
// other asynchronous operations.
@interface MLNTestAssertionHandler : NSAssertionHandler

- (instancetype)initWithTestCase:(XCTestCase *)testCase;
@property (nonatomic, weak) XCTestCase *testCase;

// If YES, use `_XCTPreformattedFailureHandler` to "fail" the test,
// otherwise log the assert.
@property (nonatomic) BOOL shouldFail;
@end

NS_ASSUME_NONNULL_END
