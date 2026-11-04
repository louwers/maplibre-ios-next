// Based on platform/darwin/src/MLNPolygon.mm at ios-v7.0.0

#import "MLNPolygon_Private.h"

#import "MLNGeometry_Private.h"
#import "MLNLoggingConfiguration_Private.h"
#import "MLNMultiPoint_Private.h"

#import "MLNFeature.h"
#import "MLNLatLngBounds.h"
#import "MLNShape_Private.h"

#include <polylabel.hpp>

@implementation MLNPolygon

@dynamic overlayBounds;

+ (BOOL)supportsSecureCoding {
  return YES;
}

+ (instancetype)polygonWithCoordinates:(const CLLocationCoordinate2D *)coords
                                 count:(NSUInteger)count {
  return [self polygonWithCoordinates:coords count:count interiorPolygons:nil];
}

+ (instancetype)polygonWithCoordinates:(const CLLocationCoordinate2D *)coords
                                 count:(NSUInteger)count
                      interiorPolygons:(NSArray<MLNPolygon *> *)interiorPolygons {
  return [[self alloc] initWithCoordinates:coords count:count interiorPolygons:interiorPolygons];
}

- (instancetype)initWithCoordinates:(const CLLocationCoordinate2D *)coords
                              count:(NSUInteger)count
                   interiorPolygons:(NSArray<MLNPolygon *> *)interiorPolygons {
  MLNLogDebug(@"Initializing with %lu coordinates and %lu interiorPolygons.", (unsigned long)count,
              (unsigned long)interiorPolygons);
  if (self = [super initWithCoordinates:coords count:count]) {
    if (interiorPolygons.count) {
      _interiorPolygons = interiorPolygons;
    }
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)decoder {
  MLNLogInfo(@"Initializng with coder.");
  self = [super initWithCoder:decoder];
  if (self) {
    NSSet<Class> *polygonClasses =
        [NSSet setWithArray:@[ [NSDictionary class], [NSArray class], [MLNPolygon class] ]];
    _interiorPolygons = [decoder decodeObjectOfClasses:polygonClasses forKey:@"interiorPolygons"];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  [coder encodeObject:self.interiorPolygons forKey:@"interiorPolygons"];
}

- (BOOL)isEqual:(id)other {
  if (self == other) return YES;
  if (![other isKindOfClass:[MLNPolygon class]]) return NO;

  MLNPolygon *otherPolygon = (MLNPolygon *)other;
  return ([super isEqual:otherPolygon] &&
          [[self geoJSONDictionary] isEqualToDictionary:[otherPolygon geoJSONDictionary]]);
}

- (NSUInteger)hash {
  return [super hash] + [[self geoJSONDictionary] hash];
}

- (CLLocationCoordinate2D)coordinate {
  // pole of inaccessibility
  auto poi = mapbox::polylabel([self polygon]);

  return CLLocationCoordinate2DMake(poi.y, poi.x);
}

- (mapbox::polylabel_detail::Ring)ring {
  NSUInteger count = self.pointCount;
  CLLocationCoordinate2D *coordinates = self.coordinates;

  mapbox::polylabel_detail::Ring result;
  result.reserve(self.pointCount);
  for (NSUInteger i = 0; i < count; i++) {
    result.push_back({coordinates[i].longitude, coordinates[i].latitude});
  }
  return result;
}

- (mapbox::polylabel_detail::Polygon)polygon {
  mapbox::polylabel_detail::Polygon geometry;
  geometry.push_back(self.ring);
  for (MLNPolygon *polygon in self.interiorPolygons) {
    geometry.push_back(polygon.ring);
  }
  return geometry;
}

- (id)geometryObject {
  return @{@"type" : @"Polygon", @"coordinates" : self.mgl_coordinates};
}

- (NSDictionary *)geoJSONDictionary {
  return @{@"type" : @"Polygon", @"coordinates" : self.mgl_coordinates};
}

- (NSArray<id> *)mgl_coordinates {
  NSMutableArray *coordinates = [NSMutableArray array];

  NSMutableArray *exteriorRing = [NSMutableArray array];
  for (NSUInteger index = 0; index < self.pointCount; index++) {
    CLLocationCoordinate2D coordinate = self.coordinates[index];
    [exteriorRing addObject:@[ @(coordinate.longitude), @(coordinate.latitude) ]];
  }
  [coordinates addObject:exteriorRing];

  for (MLNPolygon *interiorPolygon in self.interiorPolygons) {
    NSMutableArray *interiorRing = [NSMutableArray array];
    for (NSUInteger index = 0; index < interiorPolygon.pointCount; index++) {
      CLLocationCoordinate2D coordinate = interiorPolygon.coordinates[index];
      [interiorRing addObject:@[ @(coordinate.longitude), @(coordinate.latitude) ]];
    }
    [coordinates addObject:interiorRing];
  }

  return [coordinates copy];
}

@end

@interface MLNMultiPolygon ()

@property (nonatomic, copy, readwrite) NSArray<MLNPolygon *> *polygons;

@end

@implementation MLNMultiPolygon {
  MLNCoordinateBounds _overlayBounds;
}

@synthesize overlayBounds = _overlayBounds;

+ (BOOL)supportsSecureCoding {
  return YES;
}

+ (instancetype)multiPolygonWithPolygons:(NSArray<MLNPolygon *> *)polygons {
  return [[self alloc] initWithPolygons:polygons];
}

- (instancetype)initWithPolygons:(NSArray<MLNPolygon *> *)polygons {
  MLNLogDebug(@"Initializing with %lu polygons.", (unsigned long)polygons.count);
  if (self = [super init]) {
    _polygons = polygons;

    mln_lat_lng_bounds bounds = MLNLatLngBoundsEmpty();

    for (MLNPolygon *polygon in _polygons) {
      MLNLatLngBoundsExtendBounds(bounds, MLNLatLngBoundsFromCoordinateBounds(polygon.overlayBounds));
    }
    _overlayBounds = MLNCoordinateBoundsFromLatLngBounds(bounds);
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)decoder {
  MLNLogInfo(@"Initializing with coder.");
  if (self = [super initWithCoder:decoder]) {
    NSSet<Class> *polygonsClasses =
        [NSSet setWithArray:@[ [NSDictionary class], [NSArray class], [MLNPolygon class] ]];
    _polygons = [decoder decodeObjectOfClasses:polygonsClasses forKey:@"polygons"];

    mln_lat_lng_bounds bounds = MLNLatLngBoundsEmpty();

    for (MLNPolygon *polygon in _polygons) {
      MLNLatLngBoundsExtendBounds(bounds, MLNLatLngBoundsFromCoordinateBounds(polygon.overlayBounds));
    }
    _overlayBounds = MLNCoordinateBoundsFromLatLngBounds(bounds);
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  [coder encodeObject:_polygons forKey:@"polygons"];
}

- (BOOL)isEqual:(id)other {
  if (self == other) return YES;
  if (![other isKindOfClass:[MLNMultiPolygon class]]) return NO;

  MLNMultiPolygon *otherMultiPolygon = other;
  return [super isEqual:other] && [self.polygons isEqualToArray:otherMultiPolygon.polygons];
}

- (NSUInteger)hash {
  NSUInteger hash = [super hash];
  for (MLNPolygon *polygon in self.polygons) {
    hash += [polygon hash];
  }
  return hash;
}

- (CLLocationCoordinate2D)coordinate {
  MLNPolygon *firstPolygon = self.polygons.firstObject;

  return firstPolygon.coordinate;
}

- (BOOL)intersectsOverlayBounds:(MLNCoordinateBounds)overlayBounds {
  return MLNCoordinateBoundsIntersectsCoordinateBounds(_overlayBounds, overlayBounds);
}

- (id)geometryObject {
  NSMutableArray *coordinates = [[NSMutableArray alloc] initWithCapacity:self.polygons.count];
  for (MLNPolygon *polygon in self.polygons) {
    [coordinates addObject:polygon.mgl_coordinates];
  }
  return @{@"type" : @"MultiPolygon", @"coordinates" : coordinates};
}

- (NSDictionary *)geoJSONDictionary {
  NSMutableArray *coordinates = [[NSMutableArray alloc] initWithCapacity:self.polygons.count];
  for (MLNPolygonFeature *feature in self.polygons) {
    [coordinates addObject:feature.mgl_coordinates];
  }
  return @{@"type" : @"MultiPolygon", @"coordinates" : coordinates};
}

- (NSString *)description {
  return [NSString
      stringWithFormat:@"<%@: %p; title = %@, subtitle: = %@, count = %lu; bounds = %@>",
                       NSStringFromClass([self class]), (void *)self,
                       self.title ? [NSString stringWithFormat:@"\"%@\"", self.title] : self.title,
                       self.subtitle ? [NSString stringWithFormat:@"\"%@\"", self.subtitle]
                                     : self.subtitle,
                       (unsigned long)self.polygons.count,
                       MLNStringFromCoordinateBounds(self.overlayBounds)];
}

@end
