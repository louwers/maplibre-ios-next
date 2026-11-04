// Based on platform/darwin/src/NSArray+MLNAdditions.mm at ios-v7.0.0

#import "NSArray+MLNAdditions.h"

#import "MLNLoggingConfiguration_Private.h"
#import "NSDictionary+MLNAdditions.h"
#import "NSExpression+MLNPrivateAdditions.h"

@implementation NSArray (MLNAdditions)

- (NSArray *)mgl_vector {
  NSMutableArray *vector = [NSMutableArray arrayWithCapacity:self.count];
  for (id value in self) {
    if ([value isKindOfClass:[NSArray class]]) {
      [vector addObject:[value mgl_vector]];
    } else if ([value isKindOfClass:[NSDictionary class]]) {
      [vector addObject:[value mgl_propertyMap]];
    } else {
      NSExpression *expression = [NSExpression expressionForConstantValue:value];
      [vector addObject:expression.mgl_constantJSONValue];
    }
  }
  return vector;
}

- (NSAttributedString *)mgl_attributedComponentsJoinedByString:(NSString *)separator {
  NSAttributedString *attributedSeparator = [[NSAttributedString alloc] initWithString:separator];
  NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] init];
  BOOL isSubsequentItem = NO;
  for (NSAttributedString *component in self) {
    MLNAssert([component isKindOfClass:[NSAttributedString class]],
              @"Items in array must be attributed strings.");
    if (isSubsequentItem) {
      [attributedString appendAttributedString:attributedSeparator];
    }
    isSubsequentItem = YES;
    [attributedString appendAttributedString:component];
  }
  return attributedString;
}

+ (NSArray *)mgl_coordinatesFromCoordinates:(std::vector<CLLocationCoordinate2D>)coords {
  NSMutableArray *coordinates = [NSMutableArray array];
  for (auto coord : coords) {
    [coordinates addObject:@{@"latitude" : @(coord.latitude), @"longitude" : @(coord.longitude)}];
  }
  return coordinates;
}

- (std::vector<CLLocationCoordinate2D>)mgl_coordinates {
  NSUInteger numberOfCoordinates = [self count];
  CLLocationCoordinate2D *coords =
      (CLLocationCoordinate2D *)malloc(numberOfCoordinates * sizeof(CLLocationCoordinate2D));

  for (NSUInteger i = 0; i < numberOfCoordinates; i++) {
    coords[i] = CLLocationCoordinate2DMake([self[i][@"latitude"] doubleValue],
                                           [self[i][@"longitude"] doubleValue]);
  }

  std::vector<CLLocationCoordinate2D> coordinates = {coords, coords + numberOfCoordinates};
  free(coords);

  return coordinates;
}

@end
