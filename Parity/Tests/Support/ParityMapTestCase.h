// A test case with an MLNMapView in the host app's window that shows a local
// style (Fixtures/styles/trace.json by default), and a recorder.

#import <XCTest/XCTest.h>

@import MapLibre;

#import "ParityRecorder.h"

NS_ASSUME_NONNULL_BEGIN

@interface ParityMapTestCase : XCTestCase <MLNMapViewDelegate>

@property (nonatomic, nullable) MLNMapView *mapView;
@property (nonatomic) ParityRecorder *recorder;
/// Delegate callbacks in order, as "name" or "name:argument".
@property (nonatomic) NSMutableArray<NSString *> *callbacks;

/// The size of the map view; 256×256 by default.
@property (class, nonatomic, readonly) CGSize mapSize;

/// Whether setUp waits for a full render after loading the style; YES by default.
@property (class, nonatomic, readonly) BOOL waitsForFullRenderInSetUp;

/// The URL of a style in the Fixtures/styles folder of the test bundle.
+ (NSURL *)styleURLNamed:(NSString *)name;

/// Loads a style and waits until it finished loading.
- (void)loadStyleURL:(NSURL *)styleURL;

/// Waits until the map rendered fully, or 10 s. A timeout is recorded, not a
/// failure: rendering is compared separately.
- (void)waitForFullRender;

/// Runs the main run loop for the given time.
- (void)spin:(NSTimeInterval)seconds;

/// Records the camera-related state of the map view under a key prefix.
- (void)recordViewport:(NSString *)prefix;

@end

NS_ASSUME_NONNULL_END
