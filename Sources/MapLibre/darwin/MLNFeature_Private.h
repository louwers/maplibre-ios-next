// Based on platform/darwin/src/MLNFeature_Private.h at ios-v7.0.0
//
// Classic converted features to and from mln::GeoJSONFeature. Conversion from
// GeoJSON now lives in MLNGeoJSON.h (MLNFeatureFromGeoJSONFeature,
// MLNFeaturesFromGeoJSONFeatures, MLNShapeFromGeoJSONObject); the functions
// here build the Foundation GeoJSON objects that replace mln::GeoJSONFeature.

#import "MLNFeature.h"
#import "MLNFoundation.h"
#import "MLNShape.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Returns the GeoJSON Feature object for a feature with the given geometry
 object, identifier and attributes, as classic's mbglFeature() built the
 mln::GeoJSONFeature: the identifier as `mgl_featureIdentifier` converted it
 (omitted if it is not a string or number) and the attributes as
 `mgl_propertyMap` converted them.
 */
NSDictionary<NSString *, id> *MLNGeoJSONFeatureObject(id geometry, id _Nullable identifier,
                                                      NSDictionary *attributes);

/**
 Returns an `NSDictionary` representation of an ``MLNFeature``.
 */
NSDictionary<NSString *, id> *NSDictionaryFeatureForGeometry(NSDictionary *geometry,
                                                             NSDictionary *attributes,
                                                             id identifier);

NS_ASSUME_NONNULL_END

#define MLN_DEFINE_FEATURE_INIT_WITH_CODER()                                                \
  -(instancetype)initWithCoder : (NSCoder *)decoder {                                       \
    if (self = [super initWithCoder:decoder]) {                                             \
      NSSet<Class> *identifierClasses =                                                     \
          [NSSet setWithArray:@[ [NSString class], [NSNumber class] ]];                     \
      identifier = [decoder decodeObjectOfClasses:identifierClasses forKey:@"identifier"];  \
      NSSet<Class> *attributesClasses =                                                     \
          [NSSet setWithArray:@[ [NSDictionary class], [NSArray class] ]];                  \
      _attributes = [decoder decodeObjectOfClasses:attributesClasses forKey:@"attributes"]; \
    }                                                                                       \
    return self;                                                                            \
  }                                                                                         \
  +(BOOL)supportsSecureCoding {                                                             \
    return YES;                                                                             \
  }

#define MLN_DEFINE_FEATURE_ENCODE()                        \
  -(void)encodeWithCoder : (NSCoder *)coder {              \
    [super encodeWithCoder:coder];                         \
    [coder encodeObject:identifier forKey:@"identifier"];  \
    [coder encodeObject:_attributes forKey:@"attributes"]; \
  }

// Classic compared the mln::GeoJSON objects; this compares the GeoJSON objects
// that replace them.
#define MLN_DEFINE_FEATURE_IS_EQUAL()                                                       \
  -(BOOL)isEqual : (id)other {                                                              \
    if (other == self) return YES;                                                          \
    if (![other isKindOfClass:[self class]]) return NO;                                     \
    __typeof(self) otherFeature = other;                                                    \
    return [super isEqual:other] && [[self geoJSONObject] isEqual:[otherFeature geoJSONObject]]; \
  }                                                                                         \
  -(NSUInteger)hash {                                                                       \
    return [super hash] + [[self geoJSONDictionary] hash];                                  \
  }

#define MLN_DEFINE_FEATURE_ATTRIBUTES_GETTER() \
  -(NSDictionary *)attributes {                \
    if (!_attributes) {                        \
      return @{};                              \
    }                                          \
    return _attributes;                        \
  }
