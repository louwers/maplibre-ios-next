// Based on platform/darwin/src/NSDictionary+MLNAdditions.h at ios-v7.0.0

#import <Foundation/Foundation.h>


NS_ASSUME_NONNULL_BEGIN

@interface NSDictionary (MLNAdditions)

/**
 The dictionary as a GeoJSON properties object, as classic's mln::PropertyMap
 held it: nested dictionaries and arrays are converted recursively, and other
 values as `-[NSExpression mgl_constantJSONValue]` converts constants.
 */
- (NSDictionary<NSString *, id> *)mgl_propertyMap;

@end

NS_ASSUME_NONNULL_END
