// Camera, viewport and projection behaviour of MLNMapView.

#import "ParityMapTestCase.h"

@interface MLNCameraTraceTests : ParityMapTestCase
@end

@implementation MLNCameraTraceTests

- (void)testInitialViewport {
  [self recordViewport:@"initial"];
  [self.recorder record:@"minimumZoomLevel" value:@(self.mapView.minimumZoomLevel)];
  [self.recorder record:@"maximumZoomLevel" value:@(self.mapView.maximumZoomLevel)];
  [self.recorder record:@"minimumPitch" value:@(self.mapView.minimumPitch)];
  [self.recorder record:@"maximumPitch" value:@(self.mapView.maximumPitch)];
}

- (void)testNonAnimatedSetters {
  [self.mapView setCenterCoordinate:CLLocationCoordinate2DMake(40.7, -74.0) animated:NO];
  [self recordViewport:@"center"];
  [self.mapView setZoomLevel:7.5 animated:NO];
  [self recordViewport:@"zoom"];
  [self.mapView setDirection:45 animated:NO];
  [self recordViewport:@"direction"];
  [self.mapView setCenterCoordinate:CLLocationCoordinate2DMake(-33.9, 151.2) zoomLevel:4 direction:270 animated:NO];
  [self recordViewport:@"combined"];
  self.mapView.zoomLevel = 30;
  [self recordViewport:@"zoomBeyondMaximum"];
  self.mapView.zoomLevel = -5;
  [self recordViewport:@"zoomBelowMinimum"];
  self.mapView.direction = 721;
  [self recordViewport:@"directionWrapped"];
  [self.recorder record:@"invalidCenter" block:^id {
    [self.mapView setCenterCoordinate:CLLocationCoordinate2DMake(91, 0) animated:NO];
    return [NSValue valueWithMLNCoordinate:self.mapView.centerCoordinate];
  }];
}

- (void)testCameras {
  MLNMapCamera *camera = [MLNMapCamera cameraLookingAtCenterCoordinate:CLLocationCoordinate2DMake(48.85, 2.35)
                                                              altitude:20000
                                                                 pitch:30
                                                               heading:90];
  [self.recorder record:@"cameraInput" value:camera];
  [self.mapView setCamera:camera animated:NO];
  [self recordViewport:@"setCamera"];
  MLNMapCamera *distance = [MLNMapCamera cameraLookingAtCenterCoordinate:CLLocationCoordinate2DMake(0, 0)
                                                     acrossDistance:100000
                                                              pitch:0
                                                            heading:0];
  [self.recorder record:@"cameraAcrossDistance" value:distance];
  MLNMapCamera *fromEye = [MLNMapCamera cameraLookingAtCenterCoordinate:CLLocationCoordinate2DMake(10, 10)
                                                    fromEyeCoordinate:CLLocationCoordinate2DMake(9.9, 10)
                                                          eyeAltitude:5000];
  [self.recorder record:@"cameraFromEye" value:fromEye];
  self.mapView.camera = fromEye;
  [self recordViewport:@"cameraFromEyeApplied"];
  [self.recorder record:@"pitchClamped" block:^id {
    MLNMapCamera *steep = [self.mapView.camera copy];
    steep.pitch = 89;
    self.mapView.camera = steep;
    return @(self.mapView.camera.pitch);
  }];
}

- (void)testFitting {
  MLNCoordinateBounds bounds = MLNCoordinateBoundsMake(CLLocationCoordinate2DMake(51, 3), CLLocationCoordinate2DMake(54, 7));
  MLNMapCamera *fit = [self.mapView cameraThatFitsCoordinateBounds:bounds];
  [self.recorder record:@"cameraThatFitsBounds" value:fit];
  MLNMapCamera *padded = [self.mapView cameraThatFitsCoordinateBounds:bounds edgePadding:UIEdgeInsetsMake(10, 20, 30, 40)];
  [self.recorder record:@"cameraThatFitsBoundsPadded" value:padded];
  [self.mapView setVisibleCoordinateBounds:bounds animated:NO];
  [self recordViewport:@"setVisibleBounds"];
  [self.mapView setVisibleCoordinateBounds:bounds edgePadding:UIEdgeInsetsMake(20, 20, 20, 20) animated:NO completionHandler:nil];
  [self recordViewport:@"setVisibleBoundsPadded"];
  CLLocationCoordinate2D coordinates[] = {{50, 0}, {55, 10}, {52, 5}};
  [self.mapView setVisibleCoordinates:coordinates count:3 edgePadding:UIEdgeInsetsZero animated:NO];
  [self recordViewport:@"setVisibleCoordinates"];
  MLNPolygon *shape = [MLNPolygon polygonWithCoordinates:coordinates count:3];
  [self.recorder record:@"cameraThatFitsShape" value:[self.mapView cameraThatFitsShape:shape direction:30 edgePadding:UIEdgeInsetsZero]];
  [self.recorder record:@"cameraFittingCamera" value:[self.mapView camera:self.mapView.camera fittingCoordinateBounds:bounds edgePadding:UIEdgeInsetsZero]];
}

- (void)testProjection {
  [self.mapView setCenterCoordinate:CLLocationCoordinate2DMake(52.37, 4.9) zoomLevel:6 direction:20 animated:NO];
  NSArray<NSValue *> *points = @[
    [NSValue valueWithCGPoint:CGPointMake(0, 0)], [NSValue valueWithCGPoint:CGPointMake(128, 128)],
    [NSValue valueWithCGPoint:CGPointMake(256, 256)], [NSValue valueWithCGPoint:CGPointMake(10, 200)],
  ];
  for (NSValue *point in points) {
    CLLocationCoordinate2D coordinate = [self.mapView convertPoint:point.CGPointValue toCoordinateFromView:self.mapView];
    [self.recorder record:[NSString stringWithFormat:@"coordinateForPoint%@", NSStringFromCGPoint(point.CGPointValue)]
                    value:[NSValue valueWithMLNCoordinate:coordinate]];
  }
  NSArray *coordinates = @[ @[ @52.37, @4.9 ], @[ @51, @3 ], @[ @-10, @170 ], @[ @85, @-179 ] ];
  for (NSArray *c in coordinates) {
    CGPoint point = [self.mapView convertCoordinate:CLLocationCoordinate2DMake([c[0] doubleValue], [c[1] doubleValue])
                                      toPointToView:self.mapView];
    [self.recorder record:[NSString stringWithFormat:@"pointForCoordinate%@", c] value:[NSValue valueWithCGPoint:point]];
  }
  MLNCoordinateBounds rectBounds = [self.mapView convertRect:CGRectMake(50, 50, 100, 80) toCoordinateBoundsFromView:self.mapView];
  [self.recorder record:@"boundsForRect" value:[NSValue valueWithMLNCoordinateBounds:rectBounds]];
  CGRect rect = [self.mapView convertCoordinateBounds:rectBounds toRectToView:self.mapView];
  [self.recorder record:@"rectForBounds" value:[NSValue valueWithCGRect:rect]];
  [self.recorder record:@"metersPerPoint" value:@([self.mapView metersPerPointAtLatitude:52.37])];
  MLNMapProjection *projection = self.mapView.mapProjection;
  [self.recorder record:@"projectionMetersPerPoint" value:@(projection.metersPerPoint)];
  [self.recorder record:@"projectionPoint" value:[NSValue valueWithCGPoint:[projection convertCoordinate:CLLocationCoordinate2DMake(52, 5)]]];
  [self.recorder record:@"projectionCoordinate" value:[NSValue valueWithMLNCoordinate:[projection convertPoint:CGPointMake(30, 40)]]];
}

- (void)testInsetsAndBounds {
  self.mapView.contentInset = UIEdgeInsetsMake(40, 10, 20, 30);
  [self recordViewport:@"contentInset"];
  [self.recorder record:@"contentInset" value:[NSValue valueWithUIEdgeInsets:self.mapView.contentInset]];
  self.mapView.minimumZoomLevel = 2;
  self.mapView.maximumZoomLevel = 9;
  self.mapView.zoomLevel = 12;
  [self recordViewport:@"zoomClampedToMaximum"];
  self.mapView.maximumPitch = 40;
  MLNMapCamera *camera = [self.mapView.camera copy];
  camera.pitch = 60;
  self.mapView.camera = camera;
  [self recordViewport:@"pitchClampedToMaximum"];
}

- (void)testAnimatedTransitions {
  XCTestExpectation *done = [self expectationWithDescription:@"fly"];
  MLNMapCamera *camera = [MLNMapCamera cameraLookingAtCenterCoordinate:CLLocationCoordinate2DMake(35.68, 139.69)
                                                              altitude:100000 pitch:0 heading:0];
  [self.mapView flyToCamera:camera withDuration:0.3 completionHandler:^{
    [done fulfill];
  }];
  [self waitForExpectations:@[ done ] timeout:10];
  [self recordViewport:@"afterFly"];
  XCTestExpectation *eased = [self expectationWithDescription:@"ease"];
  [self.mapView setCenterCoordinate:CLLocationCoordinate2DMake(0, 0) zoomLevel:2 direction:0 animated:YES completionHandler:^{
    [eased fulfill];
  }];
  [self waitForExpectations:@[ eased ] timeout:10];
  [self recordViewport:@"afterEase"];
  [self.recorder record:@"callbacks" value:self.callbacks];
}

@end
