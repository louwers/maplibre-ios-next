// Style specification knowledge the C API does not expose.

#import <Foundation/Foundation.h>

#import "MLNStyleValue_Private.h"

NS_ASSUME_NONNULL_BEGIN

/// The names of the style-spec expression operators (generated).
FOUNDATION_EXTERN NSSet<NSString *> *MLNStyleExpressionOperators(void);

/**
 The value the core uses for a property that is not set, as the core
 serializes it.

 Classic layer getters fell back to the core's getDefault…() values. The C API
 reports nothing for an unset property, so this sets the style-spec default on
 a layer of the same type in the scratch map and reads the core's normalized
 value back, once per property. `layerType` is a style-spec layer type, or
 "light" for light properties. Returns nil if the spec has no default.
 */
FOUNDATION_EXTERN id _Nullable MLNStyleDefaultValueJSON(NSString *_Nullable layerType,
                                                        const MLNStylePropertyDescriptor *descriptor);

NS_ASSUME_NONNULL_END
