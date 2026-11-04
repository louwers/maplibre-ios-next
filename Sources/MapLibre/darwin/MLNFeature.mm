// Based on platform/darwin/src/MLNFeature.mm at ios-v7.0.0

#import "MLNCluster.h"
#import "MLNFeature_Private.h"
#import "MLNFoundation_Private.h"

#import "MLNPointAnnotation.h"
#import "MLNPolygon.h"
#import "MLNPolyline.h"

#import "MLNPointCollection_Private.h"
#import "MLNPolygon_Private.h"
#import "MLNPolyline_Private.h"
#import "MLNShape_Private.h"

#import "MLNLoggingConfiguration_Private.h"
#import "NSArray+MLNAdditions.h"
#import "NSDictionary+MLNAdditions.h"
#import "NSExpression+MLNPrivateAdditions.h"

// Cluster constants
static NSString *const MLNClusterIdentifierKey = @"cluster_id";
static NSString *const MLNClusterCountKey = @"point_count";
const NSUInteger MLNClusterIdentifierInvalid = NSUIntegerMax;

@interface MLNEmptyFeature ()
@end

@implementation MLNEmptyFeature

@synthesize identifier;
@synthesize attributes = _attributes;

MLN_DEFINE_FEATURE_INIT_WITH_CODER();
MLN_DEFINE_FEATURE_ENCODE();
MLN_DEFINE_FEATURE_IS_EQUAL();
MLN_DEFINE_FEATURE_ATTRIBUTES_GETTER();

- (id)attributeForKey:(NSString *)key {
  MLNLogDebug(@"Retrieving attributeForKey: %@", key);
  return self.attributes[key];
}

- (NSDictionary *)geoJSONDictionary {
  return NSDictionaryFeatureForGeometry(@{@"type" : @"Empty"}, self.attributes, self.identifier);
}

- (id)geoJSONObject {
  return MLNGeoJSONFeatureObject([self geometryObject], identifier, self.attributes);
}

- (id)geometryObject {
  return [NSNull null];
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<%@: %p; identifier = %@, attributes = %@>",
                                    NSStringFromClass([self class]), (void *)self,
                                    self.identifier
                                        ? [NSString stringWithFormat:@"\"%@\"", self.identifier]
                                        : self.identifier,
                                    self.attributes.count ? self.attributes : @"none"];
}

@end

@interface MLNPointFeature ()
@end

@implementation MLNPointFeature

@synthesize identifier;
@synthesize attributes = _attributes;

MLN_DEFINE_FEATURE_INIT_WITH_CODER();
MLN_DEFINE_FEATURE_ENCODE();
MLN_DEFINE_FEATURE_IS_EQUAL();
MLN_DEFINE_FEATURE_ATTRIBUTES_GETTER();

- (id)attributeForKey:(NSString *)key {
  MLNLogDebug(@"Retrieving attributeForKey: %@", key);
  return self.attributes[key];
}

- (NSDictionary *)geoJSONDictionary {
  return NSDictionaryFeatureForGeometry([super geoJSONDictionary], self.attributes,
                                        self.identifier);
}

- (id)geoJSONObject {
  return MLNGeoJSONFeatureObject([self geometryObject], identifier, self.attributes);
}

- (NSString *)description {
  return [NSString
      stringWithFormat:@"<%@: %p; identifier = %@, coordinate = %f, %f, attributes = %@>",
                       NSStringFromClass([self class]), (void *)self,
                       self.identifier ? [NSString stringWithFormat:@"\"%@\"", self.identifier]
                                       : self.identifier,
                       self.coordinate.latitude, self.coordinate.longitude,
                       self.attributes.count ? self.attributes : @"none"];
}

@end

@implementation MLNPointFeatureCluster

- (NSUInteger)clusterIdentifier {
  NSNumber *clusterNumber =
      MLN_OBJC_DYNAMIC_CAST([self attributeForKey:MLNClusterIdentifierKey], NSNumber);
  MLNAssert(clusterNumber, @"Clusters should have a cluster_id");

  if (!clusterNumber) {
    return MLNClusterIdentifierInvalid;
  }

  NSUInteger clusterIdentifier = [clusterNumber unsignedIntegerValue];
  MLNAssert(clusterIdentifier <= UINT32_MAX, @"Cluster identifiers are 32bit");

  return clusterIdentifier;
}

- (NSUInteger)clusterPointCount {
  NSNumber *count = MLN_OBJC_DYNAMIC_CAST([self attributeForKey:MLNClusterCountKey], NSNumber);
  MLNAssert(count, @"Clusters should have a point_count");

  return [count unsignedIntegerValue];
}
@end

@interface MLNPolylineFeature ()
@end

@implementation MLNPolylineFeature

@synthesize identifier;
@synthesize attributes = _attributes;

MLN_DEFINE_FEATURE_INIT_WITH_CODER();
MLN_DEFINE_FEATURE_ENCODE();
MLN_DEFINE_FEATURE_IS_EQUAL();
MLN_DEFINE_FEATURE_ATTRIBUTES_GETTER();

- (id)attributeForKey:(NSString *)key {
  MLNLogDebug(@"Retrieving attributeForKey: %@", key);
  return self.attributes[key];
}

- (NSDictionary *)geoJSONDictionary {
  return NSDictionaryFeatureForGeometry([super geoJSONDictionary], self.attributes,
                                        self.identifier);
}

- (id)geoJSONObject {
  return MLNGeoJSONFeatureObject([self geometryObject], identifier, self.attributes);
}

- (NSString *)description {
  return [NSString
      stringWithFormat:@"<%@: %p; identifier = %@, count = %lu, bounds = %@, attributes = %@>",
                       NSStringFromClass([self class]), (void *)self,
                       self.identifier ? [NSString stringWithFormat:@"\"%@\"", self.identifier]
                                       : self.identifier,
                       (unsigned long)[self pointCount],
                       MLNStringFromCoordinateBounds(self.overlayBounds),
                       self.attributes.count ? self.attributes : @"none"];
}

@end

@interface MLNPolygonFeature ()
@end

@implementation MLNPolygonFeature

@synthesize identifier;
@synthesize attributes = _attributes;

MLN_DEFINE_FEATURE_INIT_WITH_CODER();
MLN_DEFINE_FEATURE_ENCODE();
MLN_DEFINE_FEATURE_IS_EQUAL();
MLN_DEFINE_FEATURE_ATTRIBUTES_GETTER();

- (id)attributeForKey:(NSString *)key {
  MLNLogDebug(@"Retrieving attributeForKey: %@", key);
  return self.attributes[key];
}

- (NSDictionary *)geoJSONDictionary {
  return NSDictionaryFeatureForGeometry([super geoJSONDictionary], self.attributes,
                                        self.identifier);
}

- (id)geoJSONObject {
  return MLNGeoJSONFeatureObject([self geometryObject], identifier, self.attributes);
}

- (NSString *)description {
  return [NSString
      stringWithFormat:@"<%@: %p; identifier = %@, count = %lu, bounds = %@, attributes = %@>",
                       NSStringFromClass([self class]), (void *)self,
                       self.identifier ? [NSString stringWithFormat:@"\"%@\"", self.identifier]
                                       : self.identifier,
                       (unsigned long)[self pointCount],
                       MLNStringFromCoordinateBounds(self.overlayBounds),
                       self.attributes.count ? self.attributes : @"none"];
}

@end

@interface MLNPointCollectionFeature ()
@end

@implementation MLNPointCollectionFeature

@synthesize identifier;
@synthesize attributes = _attributes;

MLN_DEFINE_FEATURE_INIT_WITH_CODER();
MLN_DEFINE_FEATURE_ENCODE();
MLN_DEFINE_FEATURE_IS_EQUAL();
MLN_DEFINE_FEATURE_ATTRIBUTES_GETTER();

- (id)attributeForKey:(NSString *)key {
  MLNLogDebug(@"Retrieving attributeForKey: %@", key);
  return self.attributes[key];
}

- (NSDictionary *)geoJSONDictionary {
  return NSDictionaryFeatureForGeometry([super geoJSONDictionary], self.attributes,
                                        self.identifier);
}

- (id)geoJSONObject {
  return MLNGeoJSONFeatureObject([self geometryObject], identifier, self.attributes);
}

@end

@interface MLNMultiPolylineFeature ()
@end

@implementation MLNMultiPolylineFeature

@synthesize identifier;
@synthesize attributes = _attributes;

MLN_DEFINE_FEATURE_INIT_WITH_CODER();
MLN_DEFINE_FEATURE_ENCODE();
MLN_DEFINE_FEATURE_IS_EQUAL();
MLN_DEFINE_FEATURE_ATTRIBUTES_GETTER();

- (id)attributeForKey:(NSString *)key {
  MLNLogDebug(@"Retrieving attributeForKey: %@", key);
  return self.attributes[key];
}

- (NSDictionary *)geoJSONDictionary {
  return NSDictionaryFeatureForGeometry([super geoJSONDictionary], self.attributes,
                                        self.identifier);
}

- (id)geoJSONObject {
  return MLNGeoJSONFeatureObject([self geometryObject], identifier, self.attributes);
}

- (NSString *)description {
  return [NSString
      stringWithFormat:@"<%@: %p; identifier = %@, count = %lu, bounds = %@, attributes = %@>",
                       NSStringFromClass([self class]), (void *)self,
                       self.identifier ? [NSString stringWithFormat:@"\"%@\"", self.identifier]
                                       : self.identifier,
                       (unsigned long)self.polylines.count,
                       MLNStringFromCoordinateBounds(self.overlayBounds),
                       self.attributes.count ? self.attributes : @"none"];
}

@end

@interface MLNMultiPolygonFeature ()
@end

@implementation MLNMultiPolygonFeature

@synthesize identifier;
@synthesize attributes = _attributes;

MLN_DEFINE_FEATURE_INIT_WITH_CODER();
MLN_DEFINE_FEATURE_ENCODE();
MLN_DEFINE_FEATURE_IS_EQUAL();
MLN_DEFINE_FEATURE_ATTRIBUTES_GETTER();

- (id)attributeForKey:(NSString *)key {
  MLNLogDebug(@"Retrieving attributeForKey: %@", key);
  return self.attributes[key];
}

- (NSDictionary *)geoJSONDictionary {
  return NSDictionaryFeatureForGeometry([super geoJSONDictionary], self.attributes,
                                        self.identifier);
}

- (id)geoJSONObject {
  return MLNGeoJSONFeatureObject([self geometryObject], identifier, self.attributes);
}

- (NSString *)description {
  return [NSString
      stringWithFormat:@"<%@: %p; identifier = %@, count = %lu, bounds = %@, attributes = %@>",
                       NSStringFromClass([self class]), (void *)self,
                       self.identifier ? [NSString stringWithFormat:@"\"%@\"", self.identifier]
                                       : self.identifier,
                       (unsigned long)self.polygons.count,
                       MLNStringFromCoordinateBounds(self.overlayBounds),
                       self.attributes.count ? self.attributes : @"none"];
}

@end

@interface MLNShapeCollectionFeature ()
@end

@implementation MLNShapeCollectionFeature

@synthesize identifier;
@synthesize attributes = _attributes;

@dynamic shapes;

+ (instancetype)shapeCollectionWithShapes:(NSArray<MLNShape<MLNFeature> *> *)shapes {
  return [super shapeCollectionWithShapes:shapes];
}

MLN_DEFINE_FEATURE_INIT_WITH_CODER();
MLN_DEFINE_FEATURE_ENCODE();
MLN_DEFINE_FEATURE_IS_EQUAL();
MLN_DEFINE_FEATURE_ATTRIBUTES_GETTER();

- (id)attributeForKey:(NSString *)key {
  return self.attributes[key];
}

- (NSDictionary *)geoJSONDictionary {
  return NSDictionaryFeatureForGeometry([super geoJSONDictionary], self.attributes,
                                        self.identifier);
}

- (id)geoJSONObject {
  NSMutableArray *featureCollection = [NSMutableArray arrayWithCapacity:self.shapes.count];
  for (MLNShape<MLNFeature> *feature in self.shapes) {
    NSDictionary *geoJSONObject = feature.geoJSONObject;
    MLNAssert([geoJSONObject isKindOfClass:[NSDictionary class]] &&
                  [geoJSONObject[@"type"] isEqual:@"Feature"],
              @"Feature collection must only contain features.");
    [featureCollection addObject:geoJSONObject];
  }
  return @{@"type" : @"FeatureCollection", @"features" : featureCollection};
}

@end

NSDictionary<NSString *, id> *MLNGeoJSONFeatureObject(id geometry, id identifier,
                                                      NSDictionary *attributes) {
  NSMutableDictionary *feature = [@{
    @"type" : @"Feature",
    @"geometry" : geometry ?: [NSNull null],
    @"properties" : [attributes mgl_propertyMap],
  } mutableCopy];
  if (identifier) {
    NSExpression *identifierExpression = [NSExpression expressionForConstantValue:identifier];
    id featureIdentifier = [identifierExpression mgl_featureIdentifierJSONValue];
    if (featureIdentifier) {
      feature[@"id"] = featureIdentifier;
    }
  }
  return feature;
}

NSDictionary<NSString *, id> *NSDictionaryFeatureForGeometry(NSDictionary *geometry,
                                                             NSDictionary *attributes,
                                                             id identifier) {
  NSMutableDictionary *feature =
      [@{@"type" : @"Feature", @"properties" : attributes, @"geometry" : geometry} mutableCopy];
  feature[@"id"] = identifier;
  return [feature copy];
}
