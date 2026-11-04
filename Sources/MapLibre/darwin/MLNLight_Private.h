// Based on platform/darwin/src/MLNLight_Private.h at ios-v7.0.0

#import <Foundation/Foundation.h>

#import "MLNLight.h"

NS_ASSUME_NONNULL_BEGIN

@interface MLNLight (Private)

/**
 Initializes and returns a ``MLNLight`` from a style's light, whose properties
 `provider` returns as style-spec JSON (nil for undefined properties).
 */
- (instancetype)initWithLightJSONProvider:(id _Nullable (^)(NSString *name))provider;

/**
 The light as a style-spec light object.
 */
- (NSDictionary *)mgl_lightJSON;

@end

NS_ASSUME_NONNULL_END
