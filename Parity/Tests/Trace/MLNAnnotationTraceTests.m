// Point and shape annotations: adding, selecting, hit testing, removing.

#import "ParityMapTestCase.h"

@interface MLNAnnotationTraceTests : ParityMapTestCase
@end

@implementation MLNAnnotationTraceTests

- (NSArray *)describe:(NSArray<id<MLNAnnotation>> *)annotations {
  NSMutableArray *result = [NSMutableArray array];
  for (id<MLNAnnotation> annotation in annotations) {
    [result addObject:@{
      @"class" : NSStringFromClass([(NSObject *)annotation class]),
      @"title" : annotation.title ?: [NSNull null],
      @"coordinate" : [ParityRecorder normalize:[NSValue valueWithMLNCoordinate:annotation.coordinate]],
    }];
  }
  return [result sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
    return [[a description] compare:[b description]];
  }];
}

- (void)testAnnotations {
  [self.mapView setCenterCoordinate:CLLocationCoordinate2DMake(52.2, 4.8) zoomLevel:7 animated:NO];
  MLNPointAnnotation *point = [[MLNPointAnnotation alloc] init];
  point.coordinate = CLLocationCoordinate2DMake(52.37, 4.9);
  point.title = @"Amsterdam";
  MLNPointAnnotation *far = [[MLNPointAnnotation alloc] init];
  far.coordinate = CLLocationCoordinate2DMake(-30, 100);
  far.title = @"Far";
  CLLocationCoordinate2D lineCoordinates[] = {{52, 4}, {52.5, 5}};
  MLNPolyline *line = [MLNPolyline polylineWithCoordinates:lineCoordinates count:2];
  line.title = @"Line";
  CLLocationCoordinate2D polygonCoordinates[] = {{52, 4}, {52, 5}, {52.5, 5}, {52.5, 4}};
  MLNPolygon *polygon = [MLNPolygon polygonWithCoordinates:polygonCoordinates count:4];
  polygon.title = @"Polygon";
  [self.mapView addAnnotations:@[ point, far, line, polygon ]];
  [self waitForFullRender];
  [self.recorder record:@"annotations" value:[self describe:self.mapView.annotations]];
  [self.recorder record:@"visibleAnnotations" value:[self describe:self.mapView.visibleAnnotations]];
  [self.recorder record:@"visibleInRect" value:[self describe:[self.mapView visibleAnnotationsInRect:CGRectMake(0, 0, 128, 128)]]];
  [self.recorder record:@"style.layers.afterAnnotations" value:self.mapView.style.layers];
  [self.recorder record:@"style.sources.afterAnnotations" value:self.mapView.style.sources];

  [self.mapView selectAnnotation:point animated:NO completionHandler:nil];
  [self.recorder record:@"selected" value:[self describe:self.mapView.selectedAnnotations]];
  [self.mapView deselectAnnotation:point animated:NO];
  [self.recorder record:@"deselected" value:[self describe:self.mapView.selectedAnnotations]];
  [self.recorder record:@"viewForAnnotation" value:[self.mapView viewForAnnotation:point] ? @"view" : @"nil"];
  [self.recorder record:@"annotationImage" value:[self.mapView dequeueReusableAnnotationImageWithIdentifier:@"default_marker"] ? @"image" : @"nil"];

  [self.mapView showAnnotations:@[ point, far ] animated:NO];
  [self recordViewport:@"showAnnotations"];

  [self.mapView removeAnnotations:@[ far, line ]];
  [self.recorder record:@"afterRemove" value:[self describe:self.mapView.annotations]];
  [self.mapView removeAnnotations:self.mapView.annotations];
  [self.recorder record:@"afterRemoveAll" value:[self describe:self.mapView.annotations ?: @[]]];
}

@end
