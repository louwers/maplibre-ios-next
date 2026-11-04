// The order of MLNMapViewDelegate callbacks.

#import "ParityMapTestCase.h"

@interface MLNDelegateTraceTests : ParityMapTestCase
@end

@implementation MLNDelegateTraceTests

- (void)testStyleLoadSequence {
  [self waitForFullRender];
  [self.recorder record:@"initialLoad" value:self.callbacks];
  [self.callbacks removeAllObjects];
  [self loadStyleURL:[self.class styleURLNamed:@"trace"]];
  [self waitForFullRender];
  [self.recorder record:@"reload" value:self.callbacks];
}

- (void)testCameraChangeSequence {
  [self waitForFullRender];
  [self.callbacks removeAllObjects];
  [self.mapView setCenterCoordinate:CLLocationCoordinate2DMake(10, 10) animated:NO];
  [self.recorder record:@"duringNonAnimatedSetter" value:[self.callbacks copy]];
  [self spin:0.5];
  [self.recorder record:@"afterNonAnimatedSetter" value:[self.callbacks copy]];
  [self.callbacks removeAllObjects];
  XCTestExpectation *done = [self expectationWithDescription:@"animation"];
  [self.mapView setZoomLevel:5 animated:YES];
  [self.mapView setCenterCoordinate:CLLocationCoordinate2DMake(11, 11) zoomLevel:5 direction:0 animated:YES completionHandler:^{
    [done fulfill];
  }];
  [self waitForExpectations:@[ done ] timeout:10];
  [self spin:0.5];
  [self.recorder record:@"animated" value:self.callbacks];
}

- (void)testFailedStyleLoad {
  XCTestExpectation *failed = [self expectationWithDescription:@"failure"];
  [self.callbacks removeAllObjects];
  self.mapView.styleURL = [NSURL fileURLWithPath:@"/nonexistent/style.json"];
  [self spin:3];
  [failed fulfill];
  [self waitForExpectations:@[ failed ] timeout:1];
  [self.recorder record:@"callbacks" value:self.callbacks];
  [self.recorder record:@"style" value:self.mapView.style ? @"present" : @"nil"];
}

@end
