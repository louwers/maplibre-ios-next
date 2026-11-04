// Shapes, features, expressions and predicates, which need no map.

#import <XCTest/XCTest.h>

@import MapLibre;

#import "ParityRecorder.h"

@interface MLNModelTraceTests : XCTestCase
@property (nonatomic) ParityRecorder *recorder;
@end

@implementation MLNModelTraceTests

- (void)setUp {
  [super setUp];
  self.recorder = [ParityRecorder recorderForTest:self];
}

- (void)testGeoJSONParsing {
  NSArray<NSString *> *inputs = @[
    @"{\"type\":\"Point\",\"coordinates\":[1,2]}",
    @"{\"type\":\"Feature\",\"id\":7,\"properties\":{\"a\":1,\"b\":\"x\",\"c\":true,\"d\":null,\"e\":[1,2],\"f\":{\"g\":1.5}},\"geometry\":{\"type\":\"LineString\",\"coordinates\":[[0,0],[1,1]]}}",
    @"{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"id\":\"a\",\"properties\":{},\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[[[0,0],[1,0],[1,1],[0,0]],[[0.2,0.2],[0.4,0.2],[0.4,0.4],[0.2,0.2]]]}}]}",
    @"{\"type\":\"MultiPoint\",\"coordinates\":[[0,0],[1,1]]}",
    @"{\"type\":\"MultiLineString\",\"coordinates\":[[[0,0],[1,1]],[[2,2],[3,3]]]}",
    @"{\"type\":\"MultiPolygon\",\"coordinates\":[[[[0,0],[1,0],[1,1],[0,0]]]]}",
    @"{\"type\":\"GeometryCollection\",\"geometries\":[{\"type\":\"Point\",\"coordinates\":[1,2]}]}",
    @"{\"type\":\"Feature\",\"id\":-3,\"properties\":{\"big\":18446744073709551615,\"neg\":-5,\"float\":0.1},\"geometry\":null}",
    @"{\"type\":\"Bogus\"}",
    @"not json",
  ];
  for (NSString *input in inputs) {
    [self.recorder record:input block:^id {
      NSError *error;
      MLNShape *shape = [MLNShape shapeWithData:[input dataUsingEncoding:NSUTF8StringEncoding]
                                       encoding:NSUTF8StringEncoding
                                          error:&error];
      return shape ?: (id)error;
    }];
  }
}

- (void)testGeoJSONSerialization {
  CLLocationCoordinate2D coordinates[] = {{1, 2}, {3, 4}};
  MLNPolylineFeature *feature = [MLNPolylineFeature polylineWithCoordinates:coordinates count:2];
  feature.identifier = @42;
  feature.attributes = @{@"name" : @"x", @"n" : @1.5, @"flag" : @YES};
  NSData *data = [feature geoJSONDataUsingEncoding:NSUTF8StringEncoding];
  [self.recorder record:@"featureGeoJSON" value:[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]];
  [self.recorder record:@"featureDictionary" value:feature.geoJSONDictionary];
  MLNPointCollection *collection = [MLNPointCollection pointCollectionWithCoordinates:coordinates count:2];
  [self.recorder record:@"pointCollection" value:collection];
  [self.recorder record:@"overlayBounds" value:[NSValue valueWithMLNCoordinateBounds:collection.overlayBounds]];
  CLLocationCoordinate2D ring[] = {{0, 0}, {0, 10}, {10, 10}, {10, 0}};
  MLNPolygon *polygon = [MLNPolygon polygonWithCoordinates:ring count:4];
  [self.recorder record:@"polygonCoordinate" value:[NSValue valueWithMLNCoordinate:polygon.coordinate]];
  MLNPolyline *polyline = [MLNPolyline polylineWithCoordinates:ring count:4];
  [self.recorder record:@"polylineCoordinate" value:[NSValue valueWithMLNCoordinate:polyline.coordinate]];
}

- (void)testExpressionsAndPredicates {
  NSArray *expressions = @[
    [NSExpression expressionWithFormat:@"mgl_interpolate:withCurveType:parameters:stops:($zoomLevel, 'linear', nil, %@)", @{@0 : @1, @10 : @5}],
    [NSExpression expressionWithFormat:@"MLN_MATCH(kind, 'a', 1, 'b', 2, 0)"],
    [NSExpression expressionWithFormat:@"mgl_join({'a', name})"],
    [NSExpression expressionForConstantValue:UIColor.redColor],
    [NSExpression expressionForConstantValue:[NSValue valueWithCGVector:CGVectorMake(1, 2)]],
    [NSExpression expressionWithFormat:@"TERNARY(rank > 1, 'big', 'small')"],
  ];
  for (NSExpression *expression in expressions) {
    [self.recorder record:expression.description block:^id {
      id json = expression.mgl_jsonExpressionObject;
      return @{@"json" : json, @"roundTrip" : [NSExpression expressionWithMLNJSONObject:json]};
    }];
  }
  NSArray *predicates = @[
    [NSPredicate predicateWithFormat:@"kind == 'city'"],
    [NSPredicate predicateWithFormat:@"rank BETWEEN {1, 3}"],
    [NSPredicate predicateWithFormat:@"kind IN {'a', 'b'} AND NOT (rank < 2)"],
    [NSPredicate predicateWithFormat:@"$featureIdentifier == 1"],
    [NSPredicate predicateWithFormat:@"$geometryType == 'Point'"],
  ];
  for (NSPredicate *predicate in predicates) {
    [self.recorder record:predicate.predicateFormat block:^id {
      id json = predicate.mgl_jsonExpressionObject;
      return @{@"json" : json, @"roundTrip" : [NSPredicate predicateWithMLNJSONObject:json]};
    }];
  }
  NSArray *jsonObjects = @[
    @[ @"get", @"name" ], @[ @"step", @[ @"zoom" ], @0, @5, @1 ], @[ @"rgba", @1, @2, @3, @0.5 ],
    @[ @"format", @"a", @{@"font-scale" : @1.2} ], @[ @"image", @"x" ], @[ @"literal", @[ @1, @2 ] ],
  ];
  for (id object in jsonObjects) {
    [self.recorder record:[ParityRecorder normalize:object] ? [object description] : @"?" block:^id {
      return [NSExpression expressionWithMLNJSONObject:object];
    }];
  }
}

@end
