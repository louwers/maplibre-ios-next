#import "ParityMapTestCase.h"

@implementation ParityMapTestCase {
  XCTestExpectation *_styleLoaded;
  XCTestExpectation *_fullyRendered;
}

+ (CGSize)mapSize {
  return CGSizeMake(256, 256);
}

+ (BOOL)waitsForFullRenderInSetUp {
  return YES;
}

+ (NSURL *)styleURLNamed:(NSString *)name {
  NSURL *styles = [[NSBundle bundleForClass:[ParityMapTestCase class]] URLForResource:@"Fixtures"
                                                                        withExtension:nil];
  return [[styles URLByAppendingPathComponent:@"styles"]
      URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"json"]];
}

- (void)setUp {
  [super setUp];
  self.callbacks = [NSMutableArray array];
  self.recorder = [ParityRecorder recorderForTest:self];
  CGSize size = [self.class mapSize];
  UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
  self.mapView = [[MLNMapView alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height)];
  self.mapView.delegate = self;
  [window.rootViewController.view addSubview:self.mapView];
  [self loadStyleURL:[self.class styleURLNamed:@"trace"]];
  // Start every test from a settled map.
  if ([self.class waitsForFullRenderInSetUp]) {
    [self waitForFullRender];
  }
}

- (void)tearDown {
  [self.mapView removeFromSuperview];
  self.mapView.delegate = nil;
  self.mapView = nil;
  [super tearDown];
}

- (void)loadStyleURL:(NSURL *)styleURL {
  _styleLoaded = [self expectationWithDescription:@"style loaded"];
  self.mapView.styleURL = styleURL;
  [self waitForExpectations:@[ _styleLoaded ] timeout:15];
  _styleLoaded = nil;
}

- (void)waitForFullRender {
  _fullyRendered = [self expectationWithDescription:@"fully rendered"];
  [self.mapView setNeedsLayout];
  XCTWaiterResult result = [XCTWaiter waitForExpectations:@[ _fullyRendered ] timeout:10];
  if (result != XCTWaiterResultCompleted) {
    [self.recorder record:@"waitForFullRender.timedOut" value:@YES];
  }
  _fullyRendered = nil;
}

- (void)spin:(NSTimeInterval)seconds {
  [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

- (void)recordViewport:(NSString *)prefix {
  MLNMapView *mapView = self.mapView;
  [self.recorder record:[prefix stringByAppendingString:@".center"]
                  value:[NSValue valueWithMLNCoordinate:mapView.centerCoordinate]];
  [self.recorder record:[prefix stringByAppendingString:@".zoomLevel"] value:@(mapView.zoomLevel)];
  [self.recorder record:[prefix stringByAppendingString:@".direction"] value:@(mapView.direction)];
  [self.recorder record:[prefix stringByAppendingString:@".pitch"] value:@(mapView.camera.pitch)];
  [self.recorder record:[prefix stringByAppendingString:@".camera"] value:mapView.camera];
  [self.recorder record:[prefix stringByAppendingString:@".visibleBounds"]
                  value:[NSValue valueWithMLNCoordinateBounds:mapView.visibleCoordinateBounds]];
}

// MARK: - MLNMapViewDelegate

- (void)note:(NSString *)name {
  // Frames and animation steps vary in number; record runs of them once.
  if ([self.callbacks.lastObject isEqualToString:name]) {
    return;
  }
  [self.callbacks addObject:name];
}

- (void)mapView:(MLNMapView *)mapView didFinishLoadingStyle:(MLNStyle *)style {
  [self note:@"didFinishLoadingStyle"];
  [_styleLoaded fulfill];
}

- (void)mapViewWillStartLoadingMap:(MLNMapView *)mapView {
  [self note:@"willStartLoadingMap"];
}

- (void)mapViewDidFinishLoadingMap:(MLNMapView *)mapView {
  [self note:@"didFinishLoadingMap"];
}

- (void)mapViewDidFailLoadingMap:(MLNMapView *)mapView withError:(NSError *)error {
  [self note:[NSString stringWithFormat:@"didFailLoadingMap:%@/%ld", error.domain, (long)error.code]];
}

- (void)mapView:(MLNMapView *)mapView regionWillChangeWithReason:(MLNCameraChangeReason)reason animated:(BOOL)animated {
  [self note:[NSString stringWithFormat:@"regionWillChange:%lu:%d", (unsigned long)reason, animated]];
}

- (void)mapView:(MLNMapView *)mapView regionIsChangingWithReason:(MLNCameraChangeReason)reason {
  [self note:[NSString stringWithFormat:@"regionIsChanging:%lu", (unsigned long)reason]];
}

- (void)mapView:(MLNMapView *)mapView regionDidChangeWithReason:(MLNCameraChangeReason)reason animated:(BOOL)animated {
  [self note:[NSString stringWithFormat:@"regionDidChange:%lu:%d", (unsigned long)reason, animated]];
}

- (void)mapViewWillStartRenderingMap:(MLNMapView *)mapView {
  [self note:@"willStartRenderingMap"];
}

- (void)mapViewDidFinishRenderingMap:(MLNMapView *)mapView fullyRendered:(BOOL)fullyRendered {
  [self note:[NSString stringWithFormat:@"didFinishRenderingMap:%d", fullyRendered]];
  if (fullyRendered) {
    [_fullyRendered fulfill];
    _fullyRendered = nil;
  }
}

- (void)mapViewDidBecomeIdle:(MLNMapView *)mapView {
  [self note:@"didBecomeIdle"];
}

@end
