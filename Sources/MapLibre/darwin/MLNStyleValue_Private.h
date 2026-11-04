// Based on platform/darwin/src/MLNStyleValue_Private.h at ios-v7.0.0
//
// Classic MapLibre iOS converted style values between NSExpression and typed
// mbgl property values (MLNStyleValueTransformer). The C API takes and returns
// style-spec JSON, so this converts between NSExpression and JSON instead,
// keeping classic's typed results: constants come back as MLNColor, NSValue,
// NSString and NSNumber objects, everything else as an expression.

#import <Foundation/Foundation.h>

#import "MLNStyleValue.h"
#import "MLNTypes.h"
#import "NSDate+MLNAdditions.h"
#import "NSExpression+MLNPrivateAdditions.h"
#import "NSValue+MLNAdditions.h"

#if TARGET_OS_IPHONE
#import "UIColor+MLNAdditions.h"
#else
#import "NSColor+MLNAdditions.h"
#endif

NS_ASSUME_NONNULL_BEGIN

/// The value type of a style property, as the core's C++ types distinguish them.
typedef NS_ENUM(NSUInteger, MLNStyleValueType) {
  MLNStyleValueTypeBoolean,
  MLNStyleValueTypeNumber,
  MLNStyleValueTypeString,
  MLNStyleValueTypeFormatted,
  MLNStyleValueTypeResolvedImage,
  MLNStyleValueTypeEnum,
  MLNStyleValueTypeColor,
  /// heatmap-color, line-gradient, color-relief-color: always an expression.
  MLNStyleValueTypeColorRamp,
  /// std::vector<float>: aggregate of numbers.
  MLNStyleValueTypeNumberArray,
  /// std::vector<mln::Color>: aggregate of colors.
  MLNStyleValueTypeColorArray,
  /// std::vector<std::string>: aggregate of strings.
  MLNStyleValueTypeStringArray,
  /// std::vector<enum>: aggregate of enum strings.
  MLNStyleValueTypeEnumArray,
  /// std::array<float, 2>: an offset NSValue (CGVector).
  MLNStyleValueTypeOffset,
  /// std::array<float, 4>: an edge insets NSValue.
  MLNStyleValueTypePaddingArray,
  /// mln::Padding: an edge insets NSValue.
  MLNStyleValueTypePadding,
  /// mln::VariableAnchorOffsetCollection: anchors and offsets.
  MLNStyleValueTypeVariableAnchorOffsetCollection,
  /// mln::style::Position: an MLNSphericalPosition NSValue.
  MLNStyleValueTypePosition,
};

/// One enumeration value and its style-spec name.
typedef struct MLNStyleEnumValue {
  NSUInteger value;
  const char *name;
} MLNStyleEnumValue;

/// What the generated style code knows about one property.
typedef struct MLNStylePropertyDescriptor {
  /// The style-spec name, e.g. "fill-color".
  const char *name;
  MLNStyleValueType type;
  BOOL isLayout;
  BOOL isDataDriven;
  /// The spec default as JSON text, or NULL if the spec has none.
  const char *_Nullable defaultJSON;
  /// For enum and enum-array properties.
  const MLNStyleEnumValue *_Nullable enumValues;
  NSUInteger enumValueCount;
} MLNStylePropertyDescriptor;

/// The JSON value to send for an expression assigned to a property, as
/// MLNStyleValueTransformer::toPropertyValue produced it: constants are
/// converted by type, other expressions by `mgl_jsonExpressionObject`. nil
/// becomes NSNull, which resets the property.
FOUNDATION_EXTERN id MLNStyleJSONFromExpression(NSExpression *_Nullable expression,
                                                const MLNStylePropertyDescriptor *descriptor);

/// The expression a getter returns for the property's JSON value, as
/// MLNStyleValueTransformer::toExpression produced it. `json` nil means the
/// property is undefined; callers pass the core's default instead.
FOUNDATION_EXTERN NSExpression *_Nullable MLNExpressionFromStyleJSON(
    id _Nullable json, const MLNStylePropertyDescriptor *descriptor);

/// Whether a JSON array is an expression (its first element names an
/// expression operator), as mbgl's isExpression() decides.
FOUNDATION_EXTERN BOOL MLNStyleJSONIsExpression(id _Nullable json);

/// `{"duration": ms, "delay": ms}` for a transition.
FOUNDATION_EXTERN NSDictionary *MLNStyleJSONFromTransition(MLNTransition transition);
FOUNDATION_EXTERN MLNTransition MLNTransitionFromStyleJSON(id _Nullable json);

/// The JSON value for a Foundation object, as MLNValueFromJSONObject()
/// converted it to an mln::Value: strings, numbers, arrays, dictionaries and
/// NSNull. Raises NSInvalidArgumentException for anything else.
FOUNDATION_EXTERN id MLNJSONObjectFromFoundationValue(id _Nullable object);

/// `["rgba", r, g, b, a]` for a color, as mgl_jsonExpressionObject writes it.
FOUNDATION_EXTERN id MLNStyleJSONFromColor(MLNColor *color);
/// The color for `["rgba", r, g, b, a]` with numeric components, or nil.
FOUNDATION_EXTERN MLNColor *_Nullable MLNColorFromStyleJSON(id _Nullable json);

NS_ASSUME_NONNULL_END
