// Based on platform/darwin/src/NSExpression+MLNPrivateAdditions.h at ios-v7.0.0

#import <Foundation/Foundation.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

#import "NSExpression+MLNAdditions.h"


NS_ASSUME_NONNULL_BEGIN

@interface NSObject (MLNExpressionAdditions)

- (nullable NSNumber *)mgl_number;
- (nullable NSNumber *)mgl_numberWithFallbackValues:(id)fallbackValue,
                                                    ... NS_REQUIRES_NIL_TERMINATION;

@end

@interface NSExpression (MLNPrivateAdditions)

/**
 The constant value as the JSON object mln::Value would serialize to, as
 mgl_constantMBGLValue converted it: strings and numbers pass through,
 booleans stay booleans, colors become CSS color strings, and nil or NSNull
 becomes NSNull. Raises for other values.
 */
@property (nonatomic, readonly) id mgl_constantJSONValue;
@property (nonatomic, readonly) NSArray *mgl_aggregateJSONValue;

/**
 The feature identifier the constant represents (a string or number), as
 mgl_featureIdentifier converted it.
 */
@property (nonatomic, readonly, nullable) id mgl_featureIdentifierJSONValue;

@end

@interface NSNull (MLNExpressionAdditions)

@property (nonatomic, readonly) id mgl_jsonExpressionObject;

@end

@interface NSString (MLNExpressionAdditions)

@property (nonatomic, readonly) id mgl_jsonExpressionObject;

@end

@interface NSNumber (MLNExpressionAdditions)

- (id)mgl_interpolateWithCurveType:(NSString *)curveType
                        parameters:(NSArray *)parameters
                             stops:(NSDictionary<NSNumber *, id> *)stops;
- (id)mgl_stepWithMinimum:(id)minimum stops:(NSDictionary<NSNumber *, id> *)stops;

@property (nonatomic, readonly) id mgl_jsonExpressionObject;

@end

@interface NSArray (MLNExpressionAdditions)

@property (nonatomic, readonly) id mgl_jsonExpressionObject;

@end

@interface NSDictionary (MLNExpressionAdditions)

@property (nonatomic, readonly) id mgl_jsonExpressionObject;

- (id)mgl_has:(id)element;

@end

@interface MLNColor (MLNExpressionAdditions)

@property (nonatomic, readonly) id mgl_jsonExpressionObject;

@end

@interface NSExpression (MLNExpressionAdditions)

- (NSExpression *)mgl_expressionWithContext:(NSDictionary<NSString *, NSExpression *> *)context;

- (id)mgl_has:(id)element;

@end

FOUNDATION_EXTERN NSArray *MLNSubexpressionsWithJSONObjects(NSArray *objects);

NS_ASSUME_NONNULL_END
