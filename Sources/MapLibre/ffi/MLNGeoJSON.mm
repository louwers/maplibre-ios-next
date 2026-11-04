// The GeoJSON conversion of platform/darwin/src/MLNFeature.mm at ios-v7.0.0
// (GeometryEvaluator, GeoJSONEvaluator, MLNFeatureFromMBGLFeature,
// MLNShapeFromGeoJSON), combined with the parser it relied on,
// mapbox::geojson::parse (geojson.hpp's geojson_impl.hpp, vendored by
// maplibre-native-base), so that parsed GeoJSON objects become the same shapes
// with the same errors.

#import "MLNGeoJSON.h"

#import "MLNCluster.h"
#import "MLNFFI.h"
#import "MLNFeature_Private.h"
#import "MLNLoggingConfiguration_Private.h"
#import "MLNPointAnnotation.h"
#import "MLNPointCollection_Private.h"
#import "MLNPolygon.h"
#import "MLNPolyline.h"
#import "MLNShapeCollection.h"
#import "MLNShape_Private.h"

#include <stdexcept>
#include <string>
#include <vector>

namespace {

using GeoJSONError = std::runtime_error;

std::string MLNStdString(id object) {
  NSString *string = [object isKindOfClass:[NSString class]] ? object : [object description];
  return string.UTF8String ?: "";
}

bool MLNIsNumber(id object) {
  return [object isKindOfClass:[NSNumber class]] &&
         CFGetTypeID((__bridge CFTypeRef)object) != CFBooleanGetTypeID();
}

bool MLNTypeIs(id type, NSString *name) {
  return [type isKindOfClass:[NSString class]] && [type isEqualToString:name];
}

// A JSON number as mapbox::geojson::convert<value> typed it: unsigned 64-bit
// if it fits, else signed 64-bit, else double.
NSNumber *MLNNumberValue(NSNumber *number) {
  const char *type = number.objCType;
  if (strcmp(type, @encode(double)) == 0 || strcmp(type, @encode(float)) == 0) {
    return @(number.doubleValue);
  }
  if (strcmp(type, @encode(unsigned long long)) == 0 || [number compare:@0] != NSOrderedAscending) {
    return @(number.unsignedLongLongValue);
  }
  return @(number.longLongValue);
}

// convert<value>, as ValueEvaluator converted the result to Foundation.
id MLNConvertValue(id json) {
  if (!json || json == [NSNull null]) {
    return [NSNull null];
  }
  if ([json isKindOfClass:[NSNumber class]]) {
    if (CFGetTypeID((__bridge CFTypeRef)json) == CFBooleanGetTypeID()) {
      return [json boolValue] ? @YES : @NO;
    }
    return MLNNumberValue(json);
  }
  if ([json isKindOfClass:[NSString class]]) {
    return json;
  }
  if ([json isKindOfClass:[NSArray class]]) {
    NSMutableArray *objects = [NSMutableArray arrayWithCapacity:[json count]];
    for (id element in (NSArray *)json) {
      [objects addObject:MLNConvertValue(element)];
    }
    return objects;
  }
  if ([json isKindOfClass:[NSDictionary class]]) {
    NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithCapacity:[json count]];
    [(NSDictionary *)json enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
      attributes[key] = MLNConvertValue(value);
    }];
    return attributes;
  }
  return [NSNull null];
}

// convert<prop_map>
NSDictionary *MLNConvertProperties(id json) {
  if (![json isKindOfClass:[NSDictionary class]]) {
    throw GeoJSONError("properties must be an object");
  }
  return MLNConvertValue(json);
}

// convert<point>
CLLocationCoordinate2D MLNConvertPoint(id json) {
  if (![json isKindOfClass:[NSArray class]]) {
    throw GeoJSONError("coordinates must be an array.");
  }
  NSArray *array = json;
  if (array.count < 2) throw GeoJSONError("coordinates array must have at least 2 numbers");
  if (!MLNIsNumber(array[0]) || !MLNIsNumber(array[1])) {
    throw GeoJSONError("coordinates must be numbers");
  }
  return CLLocationCoordinate2DMake([array[1] doubleValue], [array[0] doubleValue]);
}

// convert<Cont> for containers of points.
std::vector<CLLocationCoordinate2D> MLNConvertPoints(id json) {
  if (![json isKindOfClass:[NSArray class]]) {
    throw GeoJSONError(
        "coordinates must be an array of points describing linestring or an array of "
        "arrays describing polygons and line strings.");
  }
  std::vector<CLLocationCoordinate2D> points;
  points.reserve([json count]);
  for (id element in (NSArray *)json) {
    points.push_back(MLNConvertPoint(element));
  }
  return points;
}

// convert<Cont> for containers of point containers (polygon rings, line strings).
std::vector<std::vector<CLLocationCoordinate2D>> MLNConvertPointLists(id json) {
  if (![json isKindOfClass:[NSArray class]]) {
    throw GeoJSONError(
        "coordinates must be an array of points describing linestring or an array of "
        "arrays describing polygons and line strings.");
  }
  std::vector<std::vector<CLLocationCoordinate2D>> lists;
  lists.reserve([json count]);
  for (id element in (NSArray *)json) {
    lists.push_back(MLNConvertPoints(element));
  }
  return lists;
}

void MLNValidatePolygon(id json) {
  // this check is required incase case of multipolygon validation
  if (![json isKindOfClass:[NSArray class]]) {
    throw GeoJSONError("Coordinates must be nested more deeply.");
  }
  for (id element in (NSArray *)json) {
    if (![element isKindOfClass:[NSArray class]]) {
      throw GeoJSONError("Coordinates must be an array of arrays, each describing a polygon.");
    }
    if ([element count] < 4) {
      throw GeoJSONError(
          "Polygon must be described by 4 or more coordinate points. Improper "
          "nesting can also lead to this error. Double check that the coordinates "
          "are properly nested and there are 4 or more coordinates.");
    }
  }
}

void MLNValidateLineString(id json) {
  if (![json isKindOfClass:[NSArray class]] || [json count] < 2) {
    throw GeoJSONError("A line string must have two or more coordinate points.");
  }
}

/**
 GeometryEvaluator: builds the Objective-C class for a geometry, a feature class
 if the geometry belongs to a feature, a cluster class if the feature's
 properties mark it as one.
 */
struct GeometryEvaluator {
  NSDictionary *sharedProperties = nil;
  bool isInFeature = false;

  MLNShape *empty() const {
    return isInFeature ? [[MLNEmptyFeature alloc] init] : [[MLNShape alloc] init];
  }

  MLNShape *point(CLLocationCoordinate2D coordinate) const {
    Class shapeClass = isInFeature ? [MLNPointFeature class] : [MLNPointAnnotation class];

    // If we're dealing with a cluster, we should change the class type.
    // This could be generic and build the subclass at runtime if it turns
    // out we need to support more than point clusters.
    id clusterValue = sharedProperties[@"cluster"];
    if (clusterValue && CFGetTypeID((__bridge CFTypeRef)clusterValue) == CFBooleanGetTypeID() &&
        [clusterValue boolValue]) {
      shapeClass = [MLNPointFeatureCluster class];
    }

    MLNPointAnnotation *shape = [[shapeClass alloc] init];
    shape.coordinate = coordinate;
    return shape;
  }

  MLNShape *lineString(std::vector<CLLocationCoordinate2D> &coordinates) const {
    Class shapeClass = isInFeature ? [MLNPolylineFeature class] : [MLNPolyline class];
    return [shapeClass polylineWithCoordinates:coordinates.data() count:coordinates.size()];
  }

  MLNShape *polygon(std::vector<std::vector<CLLocationCoordinate2D>> &rings) const {
    return toShape(rings, isInFeature);
  }

  MLNShape *multiPoint(std::vector<CLLocationCoordinate2D> &coordinates) const {
    Class shapeClass =
        isInFeature ? [MLNPointCollectionFeature class] : [MLNPointCollection class];
    return [[shapeClass alloc] initWithCoordinates:coordinates.data() count:coordinates.size()];
  }

  MLNShape *multiLineString(std::vector<std::vector<CLLocationCoordinate2D>> &lineStrings) const {
    NSMutableArray *polylines = [NSMutableArray arrayWithCapacity:lineStrings.size()];
    for (auto &coordinates : lineStrings) {
      MLNPolyline *polyline = [MLNPolyline polylineWithCoordinates:coordinates.data()
                                                             count:coordinates.size()];
      [polylines addObject:polyline];
    }

    Class shapeClass = isInFeature ? [MLNMultiPolylineFeature class] : [MLNMultiPolyline class];
    return [shapeClass multiPolylineWithPolylines:polylines];
  }

  MLNShape *multiPolygon(std::vector<std::vector<std::vector<CLLocationCoordinate2D>>> &polygons) const {
    NSMutableArray *shapes = [NSMutableArray arrayWithCapacity:polygons.size()];
    for (auto &polygon : polygons) {
      [shapes addObject:toShape(polygon, false)];
    }

    Class shapeClass = isInFeature ? [MLNMultiPolygonFeature class] : [MLNMultiPolygon class];
    return [shapeClass multiPolygonWithPolygons:shapes];
  }

  MLNShape *geometryCollection(NSArray<MLNShape *> *shapes) const {
    Class shapeClass =
        isInFeature ? [MLNShapeCollectionFeature class] : [MLNShapeCollection class];
    return [shapeClass shapeCollectionWithShapes:shapes];
  }

  static MLNPolygon *toShape(std::vector<std::vector<CLLocationCoordinate2D>> &rings,
                             bool isInFeature) {
    // Classic took rings.front() of an empty polygon; initializing the
    // polygon with no coordinates raises instead.
    std::vector<CLLocationCoordinate2D> noCoordinates;
    std::vector<CLLocationCoordinate2D> &coordinates = rings.empty() ? noCoordinates : rings.front();
    NSMutableArray *innerPolygons;
    if (rings.size() > 1) {
      innerPolygons = [NSMutableArray arrayWithCapacity:rings.size() - 1];
      for (auto iter = rings.begin() + 1; iter != rings.end(); iter++) {
        auto &innerCoordinates = *iter;
        MLNPolygon *innerPolygon = [MLNPolygon polygonWithCoordinates:innerCoordinates.data()
                                                                count:innerCoordinates.size()];
        [innerPolygons addObject:innerPolygon];
      }
    }

    Class shapeClass = isInFeature ? [MLNPolygonFeature class] : [MLNPolygon class];
    return [shapeClass polygonWithCoordinates:coordinates.data()
                                        count:coordinates.size()
                             interiorPolygons:innerPolygons];
  }
};

// convert<geometry>, evaluated by the given GeometryEvaluator.
MLNShape *MLNConvertGeometry(id json, const GeometryEvaluator &evaluator) {
  if (!json || json == [NSNull null]) return evaluator.empty();
  if (![json isKindOfClass:[NSDictionary class]]) throw GeoJSONError("Geometry must be an object");
  NSDictionary *dictionary = json;
  id type = dictionary[@"type"];
  if (!type) throw GeoJSONError("Geometry must have a type property");

  if (MLNTypeIs(type, @"GeometryCollection")) {
    id geometries = dictionary[@"geometries"];
    if (!geometries) throw GeoJSONError("GeometryCollection must have a geometries property");
    if (![geometries isKindOfClass:[NSArray class]])
      throw GeoJSONError("GeometryCollection geometries property must be an array");
    // This is very much like the transformation that happens in MLNFeaturesFromMBGLFeatures(),
    // but these are raw geometries with no associated feature IDs or attributes.
    NSMutableArray *shapes = [NSMutableArray arrayWithCapacity:[geometries count]];
    for (id geometry in (NSArray *)geometries) {
      [shapes addObject:MLNConvertGeometry(geometry, evaluator)];
    }
    return evaluator.geometryCollection(shapes);
  }

  id coordinates = dictionary[@"coordinates"];
  if (!coordinates)
    throw GeoJSONError(MLNStdString(type) + " geometry must have a coordinates property");
  if (![coordinates isKindOfClass:[NSArray class]])
    throw GeoJSONError("coordinates property must be an array");

  if (MLNTypeIs(type, @"Point")) return evaluator.point(MLNConvertPoint(coordinates));
  if (MLNTypeIs(type, @"MultiPoint")) {
    auto points = MLNConvertPoints(coordinates);
    return evaluator.multiPoint(points);
  }
  if (MLNTypeIs(type, @"LineString")) {
    MLNValidateLineString(coordinates);
    auto points = MLNConvertPoints(coordinates);
    return evaluator.lineString(points);
  }
  if (MLNTypeIs(type, @"MultiLineString")) {
    for (id element in (NSArray *)coordinates) {
      MLNValidateLineString(element);
    }
    auto lineStrings = MLNConvertPointLists(coordinates);
    return evaluator.multiLineString(lineStrings);
  }
  if (MLNTypeIs(type, @"Polygon")) {
    MLNValidatePolygon(coordinates);
    auto rings = MLNConvertPointLists(coordinates);
    return evaluator.polygon(rings);
  }
  if (MLNTypeIs(type, @"MultiPolygon")) {
    for (id element in (NSArray *)coordinates) {
      MLNValidatePolygon(element);
    }
    std::vector<std::vector<std::vector<CLLocationCoordinate2D>>> polygons;
    for (id element in (NSArray *)coordinates) {
      polygons.push_back(MLNConvertPointLists(element));
    }
    return evaluator.multiPolygon(polygons);
  }
  throw GeoJSONError(MLNStdString(type) + " not yet implemented");
}

// convert<identifier>, as ValueEvaluator converted it.
id MLNConvertIdentifier(id json) {
  if ([json isKindOfClass:[NSString class]]) {
    return json;
  }
  if (MLNIsNumber(json)) {
    return MLNNumberValue(json);
  }
  throw GeoJSONError("Feature id must be a string or number");
}

// convert<feature> followed by MLNFeatureFromMBGLFeature().
MLNShape<MLNFeature> *MLNConvertFeature(id json) {
  if (![json isKindOfClass:[NSDictionary class]]) throw GeoJSONError("Feature must be an object");
  NSDictionary *dictionary = json;
  id type = dictionary[@"type"];
  if (!type) throw GeoJSONError("Feature must have a type property");
  if (!MLNTypeIs(type, @"Feature")) throw GeoJSONError("Feature type must be Feature");
  id geometry = dictionary[@"geometry"];
  if (!geometry) throw GeoJSONError("Feature must have a geometry property");

  id properties = dictionary[@"properties"];

  // The parser converted the geometry, then the identifier, then the
  // properties; the evaluator only reads the cluster property.
  GeometryEvaluator evaluator;
  evaluator.sharedProperties = [properties isKindOfClass:[NSDictionary class]] ? properties : nil;
  evaluator.isInFeature = true;
  MLNShape<MLNFeature> *shape = (MLNShape<MLNFeature> *)MLNConvertGeometry(geometry, evaluator);

  id identifierJSON = dictionary[@"id"];
  if (identifierJSON) {
    shape.identifier = MLNConvertIdentifier(identifierJSON);
  }
  NSDictionary *attributes = @{};
  if (properties && properties != [NSNull null]) {
    attributes = MLNConvertProperties(properties);
  }
  shape.attributes = [attributes mutableCopy];
  return shape;
}

// convert<geojson> followed by GeoJSONEvaluator.
MLNShape *MLNConvertGeoJSON(id json) {
  if (![json isKindOfClass:[NSDictionary class]]) throw GeoJSONError("GeoJSON must be an object");
  NSDictionary *dictionary = json;
  id type = dictionary[@"type"];
  if (!type) throw GeoJSONError("GeoJSON must have a type property");
  if (MLNTypeIs(type, @"FeatureCollection")) {
    id features = dictionary[@"features"];
    if (!features) throw GeoJSONError("FeatureCollection must have features property");
    if (![features isKindOfClass:[NSArray class]])
      throw GeoJSONError("FeatureCollection features property must be an array");
    NSMutableArray *shapes = [NSMutableArray arrayWithCapacity:[features count]];
    for (id feature in (NSArray *)features) {
      [shapes addObject:MLNConvertFeature(feature)];
    }
    return [MLNShapeCollectionFeature shapeCollectionWithShapes:shapes];
  }
  if (MLNTypeIs(type, @"Feature")) return MLNConvertFeature(json);
  return MLNConvertGeometry(json, GeometryEvaluator());
}

}  // namespace

MLNShape *MLNShapeFromGeoJSONObject(id object, NSError **error) {
  try {
    return MLNConvertGeoJSON(object);
  } catch (const std::runtime_error &err) {
    if (error) {
      *error = [NSError errorWithDomain:MLNErrorDomain
                                   code:MLNErrorCodeUnknown
                               userInfo:@{
                                 NSLocalizedFailureReasonErrorKey : @(err.what()),
                               }];
    }
    return nil;
  }
}

id<MLNFeature> MLNFeatureFromGeoJSONFeature(NSDictionary *feature) {
  try {
    return MLNConvertFeature(feature);
  } catch (const std::runtime_error &err) {
    // The C API produced the feature, so this should not happen.
    MLNLogError(@"Invalid feature from the C API: %s", err.what());
    MLNEmptyFeature *empty = [[MLNEmptyFeature alloc] init];
    return empty;
  }
}

NSArray<MLNShape<MLNFeature> *> *MLNFeaturesFromGeoJSONFeatures(NSArray<NSDictionary *> *features) {
  NSMutableArray *shapes = [NSMutableArray arrayWithCapacity:features.count];
  for (NSDictionary *feature in features) {
    [shapes addObject:MLNFeatureFromGeoJSONFeature(feature)];
  }
  return shapes;
}

NSDictionary *MLNGeoJSONObjectFromShape(MLNShape *shape) { return [shape geoJSONObject]; }

NSString *MLNGeoJSONStringFromShape(MLNShape *shape) {
  return MLNFFIJSONStringFromObject([shape geoJSONObject]);
}
