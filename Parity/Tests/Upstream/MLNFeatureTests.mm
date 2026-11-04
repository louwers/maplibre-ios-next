// Copied from platform/darwin/test/MLNFeatureTests.mm at ios-v7.0.0 by Parity/Tests/Upstream/import-upstream.py.
// See ADAPTATIONS.md before editing.

@import MapLibre;
#import <XCTest/XCTest.h>

#import "ParityShims.h"

@interface MLNFeatureTests : XCTestCase

@end

@implementation MLNFeatureTests




- (void)testPointFeatureGeoJSONDictionary {
  MLNPointFeature *pointFeature = [[MLNPointFeature alloc] init];
  CLLocationCoordinate2D coordinate = {10, 10};
  pointFeature.coordinate = coordinate;

  // A GeoJSON feature
  // when there are no identifier or properties
  NSDictionary *geoJSONFeature = [pointFeature geoJSONDictionary];

  // it has the correct type
  XCTAssertEqualObjects(geoJSONFeature[@"type"], @"Feature");
  // it has the correct geometry
  NSDictionary *expectedGeometry =
      @{@"type" : @"Point", @"coordinates" : @[ @(coordinate.longitude), @(coordinate.latitude) ]};
  XCTAssertEqualObjects(geoJSONFeature[@"geometry"], expectedGeometry);
  // it has no "id" key (or value)
  XCTAssertNil(geoJSONFeature[@"id"]);
  // it has a null representation of the properties object
  XCTAssertEqualObjects(geoJSONFeature[@"properties"], @{});

  // when there is a string identifier
  pointFeature.identifier = @"string-id";

  // it has the identifier in the result
  geoJSONFeature = [pointFeature geoJSONDictionary];
  XCTAssertEqualObjects(geoJSONFeature[@"id"], pointFeature.identifier);

  // when there are properties
  pointFeature.attributes = @{@"name" : @"name-value"};

  // it has the properties value in the result
  geoJSONFeature = [pointFeature geoJSONDictionary];
  XCTAssertEqualObjects(geoJSONFeature[@"properties"], pointFeature.attributes);
}

- (void)testPolylineFeatureGeoJSONDictionary {
  CLLocationCoordinate2D coord1 = {0, 0};
  CLLocationCoordinate2D coord2 = {10, 10};
  CLLocationCoordinate2D coords[] = {coord1, coord2};
  MLNPolylineFeature *polyLineFeature = [MLNPolylineFeature polylineWithCoordinates:coords count:2];

  // A GeoJSON feature
  NSDictionary *geoJSONFeature = [polyLineFeature geoJSONDictionary];

  // it has the correct geometry
  NSDictionary *expectedGeometry = @{
    @"type" : @"LineString",
    @"coordinates" : @[
      @[ @(coord1.longitude), @(coord1.latitude) ], @[ @(coord2.longitude), @(coord2.latitude) ]
    ]
  };
  XCTAssertEqualObjects(geoJSONFeature[@"geometry"], expectedGeometry);
}

- (void)testPolygonFeatureGeoJSONDictionary {
  CLLocationCoordinate2D coord1 = {0, 0};
  CLLocationCoordinate2D coord2 = {10, 10};
  CLLocationCoordinate2D coord3 = {0, 0};
  CLLocationCoordinate2D coords[] = {coord1, coord2, coord3};
  MLNPolygonFeature *polygonFeature = [MLNPolygonFeature polygonWithCoordinates:coords count:3];

  // A GeoJSON feature
  NSDictionary *geoJSONFeature = [polygonFeature geoJSONDictionary];

  // it has the correct geometry
  NSDictionary *expectedGeometry = @{
    @"type" : @"Polygon",
    @"coordinates" : @[ @[
      @[ @(coord1.longitude), @(coord1.latitude) ], @[ @(coord2.longitude), @(coord2.latitude) ],
      @[ @(coord3.longitude), @(coord3.latitude) ]
    ] ]
  };
  XCTAssertEqualObjects(geoJSONFeature[@"geometry"], expectedGeometry);
}

- (void)testMultiPolylineFeatureGeoJSONDictionary {
  CLLocationCoordinate2D coord1 = {0, 0};
  CLLocationCoordinate2D coord2 = {10, 10};
  CLLocationCoordinate2D coord3 = {0, 0};
  CLLocationCoordinate2D coords[] = {coord1, coord2, coord3};

  MLNPolyline *polyLine1 = [MLNPolyline polylineWithCoordinates:coords count:3];
  MLNPolyline *polyLine2 = [MLNPolyline polylineWithCoordinates:coords count:3];

  MLNMultiPolylineFeature *multiPolylineFeature =
      [MLNMultiPolylineFeature multiPolylineWithPolylines:@[ polyLine1, polyLine2 ]];

  // A GeoJSON feature
  NSDictionary *geoJSONFeature = [multiPolylineFeature geoJSONDictionary];

  // it has the correct geometry
  NSDictionary *expectedGeometry = @{
    @"type" : @"MultiLineString",
    @"coordinates" : @[
      @[
        @[ @(coord1.longitude), @(coord1.latitude) ], @[ @(coord2.longitude), @(coord2.latitude) ],
        @[ @(coord3.longitude), @(coord3.latitude) ]
      ],
      @[
        @[ @(coord1.longitude), @(coord1.latitude) ], @[ @(coord2.longitude), @(coord2.latitude) ],
        @[ @(coord3.longitude), @(coord3.latitude) ]
      ]
    ]
  };
  XCTAssertEqualObjects(geoJSONFeature[@"geometry"], expectedGeometry);
}

- (void)testMultiPolygonFeatureGeoJSONDictionary {
  CLLocationCoordinate2D coord1 = {0, 0};
  CLLocationCoordinate2D coord2 = {10, 10};
  CLLocationCoordinate2D coord3 = {0, 0};
  CLLocationCoordinate2D coords[] = {coord1, coord2, coord3};

  MLNPolygon *polygon1 = [MLNPolygon polygonWithCoordinates:coords count:3];
  MLNPolygon *polygon2 = [MLNPolygon polygonWithCoordinates:coords count:3];

  MLNMultiPolygonFeature *multiPolylineFeature =
      [MLNMultiPolygonFeature multiPolygonWithPolygons:@[ polygon1, polygon2 ]];

  // A GeoJSON feature
  NSDictionary *geoJSONFeature = [multiPolylineFeature geoJSONDictionary];

  // it has the correct geometry
  NSDictionary *expectedGeometry = @{
    @"type" : @"MultiPolygon",
    @"coordinates" : @[
      @[ @[
        @[ @(coord1.longitude), @(coord1.latitude) ], @[ @(coord2.longitude), @(coord2.latitude) ],
        @[ @(coord3.longitude), @(coord3.latitude) ]
      ] ],
      @[ @[
        @[ @(coord1.longitude), @(coord1.latitude) ], @[ @(coord2.longitude), @(coord2.latitude) ],
        @[ @(coord3.longitude), @(coord3.latitude) ]
      ] ]
    ]
  };
  XCTAssertEqualObjects(geoJSONFeature[@"geometry"], expectedGeometry);
}

- (void)testPointCollectionFeatureGeoJSONDictionary {
  CLLocationCoordinate2D coord1 = {0, 0};
  CLLocationCoordinate2D coord2 = {10, 10};
  CLLocationCoordinate2D coord3 = {0, 0};
  CLLocationCoordinate2D coords[] = {coord1, coord2, coord3};
  MLNPointCollectionFeature *pointCollectionFeature =
      [MLNPointCollectionFeature pointCollectionWithCoordinates:coords count:3];

  // A GeoJSON feature
  NSDictionary *geoJSONFeature = [pointCollectionFeature geoJSONDictionary];

  // it has the correct geometry
  NSDictionary *expectedGeometry = @{
    @"type" : @"MultiPoint",
    @"coordinates" : @[
      @[ @(coord1.longitude), @(coord1.latitude) ], @[ @(coord2.longitude), @(coord2.latitude) ],
      @[ @(coord3.longitude), @(coord3.latitude) ]
    ]
  };
  XCTAssertEqualObjects(geoJSONFeature[@"geometry"], expectedGeometry);
}

- (void)testShapeCollectionFeatureGeoJSONDictionary {
  MLNPointFeature *pointFeature = [[MLNPointFeature alloc] init];
  CLLocationCoordinate2D pointCoordinate = {10, 10};
  pointFeature.coordinate = pointCoordinate;

  CLLocationCoordinate2D coord1 = {0, 0};
  CLLocationCoordinate2D coord2 = {10, 10};
  CLLocationCoordinate2D coords[] = {coord1, coord2};
  MLNPolylineFeature *polylineFeature = [MLNPolylineFeature polylineWithCoordinates:coords count:2];

  MLNShapeCollectionFeature *shapeCollectionFeature =
      [MLNShapeCollectionFeature shapeCollectionWithShapes:@[ pointFeature, polylineFeature ]];

  // A GeoJSON feature
  NSDictionary *geoJSONFeature = [shapeCollectionFeature geoJSONDictionary];

  // it has the correct geometry
  NSDictionary *expectedGeometry = @{
    @"type" : @"GeometryCollection",
    @"geometries" : @[
      @{
        @"geometry" : @{
          @"type" : @"Point",
          @"coordinates" : @[ @(pointCoordinate.longitude), @(pointCoordinate.latitude) ]
        },
        @"properties" : @{},
        @"type" : @"Feature",
      },
      @{
        @"geometry" : @{
          @"type" : @"LineString",
          @"coordinates" : @[
            @[ @(coord1.longitude), @(coord1.latitude) ],
            @[ @(coord2.longitude), @(coord2.latitude) ]
          ]
        },
        @"properties" : @{},
        @"type" : @"Feature",
      }
    ]
  };
  XCTAssertEqualObjects(geoJSONFeature[@"geometry"], expectedGeometry);

  // When the shape collection is created with an empty array of shapes
  shapeCollectionFeature = [MLNShapeCollectionFeature shapeCollectionWithShapes:@[]];

  // it has the correct (empty) geometry
  geoJSONFeature = [shapeCollectionFeature geoJSONDictionary];
  expectedGeometry = @{@"type" : @"GeometryCollection", @"geometries" : @[]};
  XCTAssertEqualObjects(geoJSONFeature[@"geometry"], expectedGeometry);
}

@end
