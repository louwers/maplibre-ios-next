// Based on platform/darwin/src/NSPredicate+MLNPrivateAdditions.h at ios-v7.0.0

#import <Foundation/Foundation.h>

#import "NSPredicate+MLNAdditions.h"

NS_ASSUME_NONNULL_BEGIN

@interface NSPredicate (MLNPrivateAdditions)

/**
 The predicate as a style-spec filter expression, validated as classic's
 `mgl_filter` validated it by converting it to an mln::style::Filter: raises
 NSInvalidArgumentException ("Invalid filter value: …") if the core cannot
 parse it as a boolean expression. Pass the result to the C API's query and
 layer filter parameters.
 */
- (id)mgl_filterJSONObject;

@end

@interface NSPredicate (MLNExpressionAdditions)

- (nullable id)mgl_if:(id)firstValue, ...;

- (nullable id)mgl_match:(NSExpression *)firstCase, ...;

@end

NS_ASSUME_NONNULL_END
