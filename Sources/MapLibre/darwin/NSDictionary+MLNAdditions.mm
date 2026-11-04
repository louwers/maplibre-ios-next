// Based on platform/darwin/src/NSDictionary+MLNAdditions.mm at ios-v7.0.0

#import "NSDictionary+MLNAdditions.h"

#import "NSArray+MLNAdditions.h"
#import "NSExpression+MLNPrivateAdditions.h"

@implementation NSDictionary (MLNAdditions)

- (NSDictionary<NSString *, id> *)mgl_propertyMap {
  NSMutableDictionary<NSString *, id> *propertyMap =
      [NSMutableDictionary dictionaryWithCapacity:self.count];
  for (NSString *key in self.allKeys) {
    if ([self[key] isKindOfClass:[NSDictionary class]]) {
      propertyMap[key] = [self[key] mgl_propertyMap];
    } else if ([self[key] isKindOfClass:[NSArray class]]) {
      NSArray *array = self[key];
      propertyMap[key] = [array mgl_vector];
    } else {
      NSExpression *expression = [NSExpression expressionForConstantValue:self[key]];
      propertyMap[key] = expression.mgl_constantJSONValue;
    }
  }
  return propertyMap;
}

@end
