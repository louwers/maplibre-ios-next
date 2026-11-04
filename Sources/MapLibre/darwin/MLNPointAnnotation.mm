// Based on platform/darwin/src/MLNPointAnnotation.mm at ios-v7.0.0

#import "MLNPointAnnotation.h"

#import "MLNLoggingConfiguration_Private.h"
#import "MLNShape_Private.h"
#import "NSCoder+MLNAdditions.h"


@implementation MLNPointAnnotation

@synthesize coordinate;

+ (BOOL)supportsSecureCoding {
  return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  MLNLogInfo(@"Initializing with coder.");
  if (self = [super initWithCoder:coder]) {
    self.coordinate = [coder decodeMLNCoordinateForKey:@"coordinate"];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  [coder encodeMLNCoordinate:coordinate forKey:@"coordinate"];
}

- (BOOL)isEqual:(id)other {
  if (other == self) return YES;
  if (![other isKindOfClass:[MLNPointAnnotation class]]) return NO;

  MLNPointAnnotation *otherAnnotation = other;
  return ([super isEqual:other] &&
          self.coordinate.latitude == otherAnnotation.coordinate.latitude &&
          self.coordinate.longitude == otherAnnotation.coordinate.longitude);
}

- (NSUInteger)hash {
  return [super hash] + @(self.coordinate.latitude).hash + @(self.coordinate.longitude).hash;
}

- (NSString *)description {
  return [NSString
      stringWithFormat:@"<%@: %p; title = %@; subtitle = %@; coordinate = %f, %f>",
                       NSStringFromClass([self class]), (void *)self,
                       self.title ? [NSString stringWithFormat:@"\"%@\"", self.title] : self.title,
                       self.subtitle ? [NSString stringWithFormat:@"\"%@\"", self.subtitle]
                                     : self.subtitle,
                       coordinate.latitude, coordinate.longitude];
}

- (NSDictionary *)geoJSONDictionary {
  return @{
    @"type" : @"Point",
    @"coordinates" : @[ @(self.coordinate.longitude), @(self.coordinate.latitude) ]
  };
}

- (id)geometryObject {
  return @{
    @"type" : @"Point",
    @"coordinates" : @[ @(self.coordinate.longitude), @(self.coordinate.latitude) ]
  };
}

@end
