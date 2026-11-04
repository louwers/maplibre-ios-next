// Copied from platform/darwin/test/MLNImageTests.mm at ios-v7.0.0 by Parity/Tests/Upstream/import-upstream.py.
// See ADAPTATIONS.md before editing.

@import MapLibre;
#import <XCTest/XCTest.h>

#if TARGET_OS_IPHONE
#define MLNImageResizingModeTile UIImageResizingModeTile
#define MLNImageResizingModeStretch UIImageResizingModeStretch
#else
#define MLNImageResizingModeTile NSImageResizingModeTile
#define MLNImageResizingModeStretch NSImageResizingModeStretch
#endif

@interface MLNImageTests : XCTestCase

@end

@implementation MLNImageTests


@end
