// Based on platform/darwin/src/MLNStyleValue.mm at ios-v7.0.0

#import "MLNStyleValue_Private.h"

#import "MLNLight.h"
#import "MLNSymbolStyleLayer.h"
#import "MLNStyleSpec.h"
#import "NSValue+MLNStyleAttributeAdditions.h"

#include <array>

const MLNStyleFunctionOption MLNStyleFunctionOptionInterpolationBase =
    @"MLNStyleFunctionOptionInterpolationBase";
const MLNStyleFunctionOption MLNStyleFunctionOptionDefaultValue =
    @"MLNStyleFunctionOptionDefaultValue";

// MARK: - Helpers

BOOL MLNStyleJSONIsExpression(id json) {
  if (![json isKindOfClass:[NSArray class]] || ![(NSArray *)json count]) {
    return NO;
  }
  id op = [(NSArray *)json firstObject];
  return [op isKindOfClass:[NSString class]] && [MLNStyleExpressionOperators() containsObject:op];
}

static NSString *MLNEnumNameForValue(NSUInteger value, const MLNStylePropertyDescriptor *descriptor) {
  for (NSUInteger i = 0; i < descriptor->enumValueCount; i++) {
    if (descriptor->enumValues[i].value == value) {
      return @(descriptor->enumValues[i].name);
    }
  }
  [NSException raise:NSInvalidArgumentException
              format:@"Invalid value %lu for %s", (unsigned long)value, descriptor->name];
  return nil;
}

static id MLNUnwrapConstant(id object) {
  if ([object isKindOfClass:[NSExpression class]] &&
      [(NSExpression *)object expressionType] == NSConstantValueExpressionType) {
    return [(NSExpression *)object constantValue];
  }
  return object;
}

// The style-spec string for an enum constant: an NSString passes through, an
// NSValue holds the MLN enum value.
static NSString *MLNEnumJSON(id object, const MLNStylePropertyDescriptor *descriptor) {
  object = MLNUnwrapConstant(object);
  if ([object isKindOfClass:[NSString class]]) {
    return object;
  }
  if ([object isKindOfClass:[NSValue class]]) {
    NSUInteger value = 0;
    [(NSValue *)object getValue:&value];
    return MLNEnumNameForValue(value, descriptor);
  }
  [NSException raise:NSInvalidArgumentException
              format:@"Invalid value %@ for %s: expected an enumeration value", object,
                     descriptor->name];
  return nil;
}

static NSArray *MLNOffsetJSON(id object) {
  object = MLNUnwrapConstant(object);
  if ([object isKindOfClass:[NSValue class]] &&
      strcmp([(NSValue *)object objCType], @encode(CGVector)) == 0) {
    std::array<float, 2> offset = [(NSValue *)object mgl_offsetArrayValue];
    return @[ @(offset[0]), @(offset[1]) ];
  }
  if ([object isKindOfClass:[NSArray class]]) {
    NSMutableArray *array = [NSMutableArray array];
    for (id element in (NSArray *)object) {
      [array addObject:@([MLNUnwrapConstant(element) floatValue])];
    }
    return array;
  }
  return object;
}

static NSArray *MLNPaddingArrayJSON(id object) {
  object = MLNUnwrapConstant(object);
  if ([object isKindOfClass:[NSValue class]] && ![object isKindOfClass:[NSNumber class]]) {
    std::array<float, 4> padding = [(NSValue *)object mgl_paddingArrayValue];
    return @[ @(padding[0]), @(padding[1]), @(padding[2]), @(padding[3]) ];
  }
  return object;
}

static id MLNPaddingJSON(id object) {
  object = MLNUnwrapConstant(object);
  if ([object isKindOfClass:[NSNumber class]]) {
    return @([(NSNumber *)object floatValue]);
  }
  if ([object isKindOfClass:[NSArray class]]) {
    NSArray *array = object;
    if (array.count < 1 || array.count > 4) {
      [NSException raise:NSInvalidArgumentException
                  format:@"Padding array should have from 1 to 4 elements."];
    }
    NSMutableArray *values = [NSMutableArray array];
    for (id element in array) {
      [values addObject:@([MLNUnwrapConstant(element) floatValue])];
    }
    return values;
  }
  return MLNPaddingArrayJSON(object);
}

static id MLNPositionJSON(id object) {
  object = MLNUnwrapConstant(object);
  if ([object isKindOfClass:[NSValue class]] &&
      strcmp([(NSValue *)object objCType], @encode(MLNSphericalPosition)) == 0) {
    std::array<float, 3> position = [(NSValue *)object mgl_lightPositionArrayValue];
    return @[ @(position[0]), @(position[1]), @(position[2]) ];
  }
  return object;
}

/// mln::Color::stringify(): the CSS rgba() form of a color.
static NSString *MLNCSSStringFromColor(MLNColor *color) {
  MLNColorComponents premultiplied = color.mgl_color;
  if (premultiplied.a == 0) {
    return @"rgba(0,0,0,0)";
  }
  return [NSString stringWithFormat:@"rgba(%.17g,%.17g,%.17g,%.17g)",
                                    premultiplied.r / premultiplied.a * 255,
                                    premultiplied.g / premultiplied.a * 255,
                                    premultiplied.b / premultiplied.a * 255, premultiplied.a];
}

// A constant of the property's type as JSON, as getMBGLValue() converted it.
static id MLNConstantJSON(id value, const MLNStylePropertyDescriptor *descriptor) {
  value = MLNUnwrapConstant(value);
  switch (descriptor->type) {
    case MLNStyleValueTypeBoolean:
      return @([value boolValue]);
    case MLNStyleValueTypeNumber:
      return [value isKindOfClass:[NSNumber class]] ? @([(NSNumber *)value floatValue]) : value;
    case MLNStyleValueTypeString:
    case MLNStyleValueTypeFormatted:
    case MLNStyleValueTypeResolvedImage:
      return value;
    case MLNStyleValueTypeEnum:
      return MLNEnumJSON(value, descriptor);
    case MLNStyleValueTypeColor:
    case MLNStyleValueTypeColorRamp:
      return [value isKindOfClass:[MLNColor class]] ? MLNStyleJSONFromColor(value) : value;
    case MLNStyleValueTypeOffset:
      return MLNOffsetJSON(value);
    case MLNStyleValueTypePaddingArray:
      return MLNPaddingArrayJSON(value);
    case MLNStyleValueTypePadding:
      return MLNPaddingJSON(value);
    case MLNStyleValueTypePosition:
      return MLNPositionJSON(value);
    case MLNStyleValueTypeNumberArray:
    case MLNStyleValueTypeColorArray:
    case MLNStyleValueTypeStringArray:
    case MLNStyleValueTypeEnumArray: {
      if (![value isKindOfClass:[NSArray class]]) {
        // A single value where the spec allows it, e.g. a number for numberArray.
        if (descriptor->type == MLNStyleValueTypeColorArray && [value isKindOfClass:[MLNColor class]]) {
          return MLNCSSStringFromColor(value);
        }
        return [value isKindOfClass:[NSNumber class]] ? @([(NSNumber *)value floatValue]) : value;
      }
      NSMutableArray *array = [NSMutableArray array];
      for (id element in (NSArray *)value) {
        id constant = MLNUnwrapConstant(element);
        switch (descriptor->type) {
          case MLNStyleValueTypeNumberArray:
            [array addObject:@([constant floatValue])];
            break;
          case MLNStyleValueTypeColorArray:
            // The core reads color arrays as CSS color strings, as
            // getMBGLValue() wrote them through Color::stringify().
            [array addObject:[constant isKindOfClass:[MLNColor class]] ? MLNCSSStringFromColor(constant)
                                                                       : constant];
            break;
          case MLNStyleValueTypeEnumArray:
            [array addObject:MLNEnumJSON(constant, descriptor)];
            break;
          default:
            [array addObject:constant];
            break;
        }
      }
      return array;
    }
    case MLNStyleValueTypeVariableAnchorOffsetCollection: {
      if (![value isKindOfClass:[NSArray class]]) {
        return value;
      }
      NSArray *array = value;
      if (array.count % 2 != 0) {
        [NSException
             raise:NSInvalidArgumentException
            format:@"VariableTextAnchorOffset array should have an even number of elements."];
      }
      NSMutableArray *json = [NSMutableArray array];
      for (NSUInteger i = 0; i < array.count; i += 2) {
        [json addObject:MLNEnumJSON(array[i], descriptor)];
        [json addObject:MLNOffsetJSON(array[i + 1])];
      }
      return json;
    }
  }
  return value;
}

id MLNStyleJSONFromExpression(NSExpression *expression, const MLNStylePropertyDescriptor *descriptor) {
  if (!expression) {
    return [NSNull null];
  }
  if (descriptor->type != MLNStyleValueTypeColorRamp) {
    if (expression.expressionType == NSConstantValueExpressionType) {
      return MLNConstantJSON(expression.constantValue, descriptor);
    }
    if (expression.expressionType == NSAggregateExpressionType) {
      return MLNConstantJSON(expression.collection, descriptor);
    }
  }
  return expression.mgl_jsonExpressionObject;
}

// MARK: - Getters

id MLNStyleJSONFromColor(MLNColor *color) { return color.mgl_jsonExpressionObject; }

MLNColor *MLNColorFromStyleJSON(id json) {
  if (![json isKindOfClass:[NSArray class]]) {
    return nil;
  }
  NSArray *array = json;
  if (array.count != 5 || ![array[0] isEqual:@"rgba"]) {
    return nil;
  }
  for (NSUInteger i = 1; i < 5; i++) {
    if (![array[i] isKindOfClass:[NSNumber class]]) {
      return nil;
    }
  }
  // mbgl serializes premultiplied components divided by alpha; reproduce the
  // float arithmetic of +[MLNColor mgl_colorWithColor:].
  float a = [array[4] floatValue];
  float r = static_cast<float>([array[1] doubleValue] / 255.0 * a);
  float g = static_cast<float>([array[2] doubleValue] / 255.0 * a);
  float b = static_cast<float>([array[3] doubleValue] / 255.0 * a);
  return [MLNColor mgl_colorWithPremultipliedRed:r green:g blue:b alpha:a];
}

static NSString *MLNEnumStringFromJSON(id json) {
  return [json isKindOfClass:[NSString class]] ? json : [json description];
}

static NSValue *MLNOffsetValueFromJSON(NSArray *json) {
  return [NSValue mgl_valueWithOffsetArray:{[json[0] floatValue], [json[1] floatValue]}];
}

static NSValue *MLNPaddingValueFromJSON(NSArray *json) {
  return [NSValue mgl_valueWithPaddingArray:{[json[0] floatValue], [json[1] floatValue],
                                             [json[2] floatValue], [json[3] floatValue]}];
}

// The constant classic returned for a value of this type
// (MLNStyleValueTransformer::toMLNRawStyleValue), or nil if the JSON is not a
// constant of the type.
static id MLNConstantFromJSON(id json, const MLNStylePropertyDescriptor *descriptor) {
  switch (descriptor->type) {
    case MLNStyleValueTypeBoolean:
      return [json isKindOfClass:[NSNumber class]] ? @([json boolValue]) : nil;
    case MLNStyleValueTypeNumber:
      return [json isKindOfClass:[NSNumber class]] ? @([json floatValue]) : nil;
    case MLNStyleValueTypeString:
    case MLNStyleValueTypeEnum:
      return [json isKindOfClass:[NSString class]] ? json : nil;
    case MLNStyleValueTypeFormatted: {
      if ([json isKindOfClass:[NSString class]]) {
        return json;
      }
      // Formatted serializes as {"sections": [{"text": ...}, ...]}.
      if ([json isKindOfClass:[NSDictionary class]] && json[@"sections"]) {
        NSMutableString *text = [NSMutableString string];
        for (NSDictionary *section in json[@"sections"]) {
          if ([section[@"text"] isKindOfClass:[NSString class]]) {
            [text appendString:section[@"text"]];
          }
        }
        return text;
      }
      return nil;
    }
    case MLNStyleValueTypeResolvedImage: {
      if ([json isKindOfClass:[NSString class]]) {
        return json;
      }
      // Image serializes as {"name": ..., "available": ...}.
      if ([json isKindOfClass:[NSDictionary class]] && [json[@"name"] isKindOfClass:[NSString class]]) {
        return json[@"name"];
      }
      return nil;
    }
    case MLNStyleValueTypeColor:
      return MLNColorFromStyleJSON(json);
    case MLNStyleValueTypeColorRamp:
      return nil;
    case MLNStyleValueTypeOffset:
      if ([json isKindOfClass:[NSArray class]] && [json count] == 2 && !MLNStyleJSONIsExpression(json)) {
        return MLNOffsetValueFromJSON(json);
      }
      return nil;
    case MLNStyleValueTypePaddingArray:
    case MLNStyleValueTypePadding:
      if ([json isKindOfClass:[NSArray class]] && [json count] == 4 && !MLNStyleJSONIsExpression(json)) {
        return MLNPaddingValueFromJSON(json);
      }
      if ([json isKindOfClass:[NSNumber class]]) {
        float value = [json floatValue];
        return [NSValue mgl_valueWithPaddingArray:{value, value, value, value}];
      }
      return nil;
    case MLNStyleValueTypePosition:
      if ([json isKindOfClass:[NSArray class]] && [json count] == 3 && !MLNStyleJSONIsExpression(json)) {
        MLNSphericalPosition position =
            MLNSphericalPositionMake([json[0] floatValue], [json[1] floatValue], [json[2] floatValue]);
        return [NSValue valueWithMLNSphericalPosition:position];
      }
      return nil;
    case MLNStyleValueTypeNumberArray:
    case MLNStyleValueTypeColorArray:
    case MLNStyleValueTypeStringArray:
    case MLNStyleValueTypeEnumArray: {
      if ([json isKindOfClass:[NSNumber class]] && descriptor->type == MLNStyleValueTypeNumberArray) {
        json = @[ json ];
      } else if (descriptor->type == MLNStyleValueTypeColorArray && MLNColorFromStyleJSON(json)) {
        json = @[ json ];
      }
      if (![json isKindOfClass:[NSArray class]] || MLNStyleJSONIsExpression(json)) {
        return nil;
      }
      NSMutableArray *elements = [NSMutableArray array];
      for (id element in (NSArray *)json) {
        id constant;
        switch (descriptor->type) {
          case MLNStyleValueTypeNumberArray:
            constant = @([element floatValue]);
            break;
          case MLNStyleValueTypeColorArray:
            constant = MLNColorFromStyleJSON(element);
            break;
          case MLNStyleValueTypeEnumArray:
            constant = MLNEnumStringFromJSON(element);
            break;
          default:
            constant = element;
            break;
        }
        if (!constant) {
          return nil;
        }
        [elements addObject:[NSExpression expressionForConstantValue:constant]];
      }
      return elements;
    }
    case MLNStyleValueTypeVariableAnchorOffsetCollection: {
      if (![json isKindOfClass:[NSArray class]] || MLNStyleJSONIsExpression(json) ||
          [json count] % 2 != 0) {
        return nil;
      }
      NSArray *array = json;
      NSMutableArray *elements = [NSMutableArray array];
      for (NSUInteger i = 0; i < array.count; i += 2) {
        if (![array[i + 1] isKindOfClass:[NSArray class]]) {
          return nil;
        }
        [elements addObject:[NSExpression expressionForConstantValue:MLNEnumStringFromJSON(array[i])]];
        [elements addObject:[NSExpression expressionForConstantValue:MLNOffsetValueFromJSON(array[i + 1])]];
      }
      return elements;
    }
  }
  return nil;
}

NSExpression *MLNExpressionFromStyleJSON(id json, const MLNStylePropertyDescriptor *descriptor) {
  if (!json || json == [NSNull null]) {
    return nil;
  }
  id constant = MLNConstantFromJSON(json, descriptor);
  if ([constant isKindOfClass:[NSArray class]]) {
    return [NSExpression expressionForAggregate:constant];
  }
  if (constant) {
    return [NSExpression expressionForConstantValue:constant];
  }
  return [NSExpression expressionWithMLNJSONObject:json];
}

// MARK: - Foundation values

id MLNJSONObjectFromFoundationValue(id object) {
  if (!object || object == [NSNull null]) {
    return [NSNull null];
  }
  if ([object isKindOfClass:[NSString class]] || [object isKindOfClass:[NSNumber class]]) {
    return object;
  }
  if ([object isKindOfClass:[NSArray class]]) {
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:[(NSArray *)object count]];
    for (id element in (NSArray *)object) {
      [array addObject:MLNJSONObjectFromFoundationValue(element)];
    }
    return array;
  }
  if ([object isKindOfClass:[NSDictionary class]]) {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    [(NSDictionary *)object enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
      dictionary[[key description]] = MLNJSONObjectFromFoundationValue(value);
    }];
    return dictionary;
  }
  [NSException raise:NSInvalidArgumentException format:@"Can’t convert %@ to mln::Value", object];
  return nil;
}

// MARK: - Transitions

NSDictionary *MLNStyleJSONFromTransition(MLNTransition transition) {
  return @{
    @"duration" : @(transition.duration * 1000),
    @"delay" : @(transition.delay * 1000),
  };
}

MLNTransition MLNTransitionFromStyleJSON(id json) {
  MLNTransition transition = {0, 0};
  if ([json isKindOfClass:[NSDictionary class]]) {
    transition.duration = [json[@"duration"] doubleValue] / 1000;
    transition.delay = [json[@"delay"] doubleValue] / 1000;
  }
  return transition;
}
