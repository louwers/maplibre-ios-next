// Based on platform/darwin/src/MLNShape.mm at ios-v7.0.0

#import "MLNShape_Private.h"

#import "MLNFeature_Private.h"

#import "MLNGeoJSON.h"
#import "MLNTypes.h"
#import "NSString+MLNAdditions.h"

bool operator==(const CLLocationCoordinate2D lhs, const CLLocationCoordinate2D rhs) {
  return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude;
}

@implementation MLNShape

+ (nullable MLNShape *)shapeWithData:(NSData *)data
                            encoding:(NSStringEncoding)encoding
                               error:(NSError *_Nullable *)outError {
  NSString *string = [[NSString alloc] initWithData:data encoding:encoding];
  if (!string) {
    if (outError) {
      *outError = [NSError errorWithDomain:MLNErrorDomain code:MLNErrorCodeUnknown userInfo:nil];
    }
    return nil;
  }

  // mapbox::geojson::parse() read the string as UTF-8.
  NSData *utf8Data = [string dataUsingEncoding:NSUTF8StringEncoding];
  NSError *parseError;
  id object = [NSJSONSerialization JSONObjectWithData:utf8Data
                                              options:NSJSONReadingFragmentsAllowed
                                                error:&parseError];
  if (!object) {
    if (outError) {
      NSString *reason = parseError.userInfo[NSDebugDescriptionErrorKey]
                             ?: parseError.localizedDescription;
      *outError = [NSError errorWithDomain:MLNErrorDomain
                                      code:MLNErrorCodeUnknown
                                  userInfo:@{
                                    NSLocalizedFailureReasonErrorKey : reason,
                                  }];
    }
    return nil;
  }
  return MLNShapeFromGeoJSONObject(object, outError);
}

- (id)geoJSONObject {
  return self.geometryObject;
}

- (id)geometryObject {
  [NSException raise:MLNAbstractClassException format:@"MLNShape is an abstract class"];
  return nil;
}

- (NSData *)geoJSONDataUsingEncoding:(NSStringEncoding)encoding {
  return [MLNGeoJSONStringFromShape(self) dataUsingEncoding:NSUTF8StringEncoding];
}

+ (BOOL)supportsSecureCoding {
  return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  if (self = [super init]) {
    _title = [coder decodeObjectOfClass:[NSString class] forKey:@"title"];
    _subtitle = [coder decodeObjectOfClass:[NSString class] forKey:@"subtitle"];
#if !TARGET_OS_IPHONE
    _toolTip = [coder decodeObjectOfClass:[NSString class] forKey:@"toolTip"];
#endif
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:_title forKey:@"title"];
  [coder encodeObject:_subtitle forKey:@"subtitle"];
#if !TARGET_OS_IPHONE
  [coder encodeObject:_toolTip forKey:@"toolTip"];
#endif
}

- (BOOL)isEqual:(id)other {
  if (other == self) {
    return YES;
  }
  id<MLNAnnotation> annotation = other;

#if TARGET_OS_IPHONE
  return ((!_title && ![annotation title]) || [_title isEqualToString:[annotation title]]) &&
         ((!_subtitle && ![annotation subtitle]) ||
          [_subtitle isEqualToString:[annotation subtitle]]);
#else
  return ((!_title && ![annotation title]) || [_title isEqualToString:[annotation title]]) &&
         ((!_subtitle && ![annotation subtitle]) ||
          [_subtitle isEqualToString:[annotation subtitle]]) &&
         ((!_toolTip && ![annotation toolTip]) || [_toolTip isEqualToString:[annotation toolTip]]);
#endif
}

- (NSUInteger)hash {
  NSUInteger hash = _title.hash + _subtitle.hash;
#if !TARGET_OS_IPHONE
  hash += _toolTip.hash;
#endif
  return hash;
}

- (CLLocationCoordinate2D)coordinate {
  [NSException raise:MLNAbstractClassException format:@"MLNShape is an abstract class"];
  return kCLLocationCoordinate2DInvalid;
}

@end
