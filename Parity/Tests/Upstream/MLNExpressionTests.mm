// Copied from platform/darwin/test/MLNExpressionTests.mm at ios-v7.0.0 by Parity/Tests/Upstream/import-upstream.py.
// See ADAPTATIONS.md before editing.

#import <XCTest/XCTest.h>

#import "ParityShims.h"

#import "MLNStyleLayerTests.h"

#import <string>

#if TARGET_OS_IPHONE
#else
#endif

#define MLNAssertEqualValues(actual, expected, ...)                            \
  XCTAssertTrue(actual.is<__typeof__(expected)>());                            \
  if (actual.is<__typeof__(expected)>()) {                                     \
    XCTAssertEqual(actual.get<__typeof__(expected)>(), expected, __VA_ARGS__); \
  }

#define MLNAssertEqualValuesWithAccuracy(actual, expected, accuracy, ...)              \
  XCTAssertTrue(actual.is<__typeof__(expected)>());                                    \
  if (actual.is<__typeof__(expected)>()) {                                             \
    XCTAssertEqualWithAccuracy(actual.get<__typeof__(expected)>(), expected, accuracy, \
                               __VA_ARGS__);                                           \
  }

#define MLNConstantExpression(constant) [NSExpression expressionForConstantValue:constant]

#define MLNAssertConstantEqualsValue(constant, value, ...) \
  MLNAssertEqualValues(MLNConstantExpression(constant).mgl_constantMBGLValue, value, __VA_ARGS__);

#define MLNAssertConstantEqualsValueWithAccuracy(constant, value, accuracy, ...)                 \
  MLNAssertEqualValuesWithAccuracy(MLNConstantExpression(constant).mgl_constantMBGLValue, value, \
                                   accuracy, __VA_ARGS__);

using namespace std::string_literals;

@interface MLNExpressionTests : XCTestCase

@end

@implementation MLNExpressionTests

// MARK: - Utility

- (NSComparisonPredicate *)equalityComparisonPredicateWithRightConstantValue:
    (id)rightConstantValue {
  NSComparisonPredicate *predicate = [NSComparisonPredicate
      predicateWithLeftExpression:[NSExpression expressionForKeyPath:@"foo"]
                  rightExpression:[NSExpression expressionForConstantValue:rightConstantValue]
                         modifier:NSDirectPredicateModifier
                             type:NSEqualToPredicateOperatorType
                          options:0];
  return predicate;
}

// MARK: - Objective-C Example Code for MLN Expressions

- (void)testSteppingExpression {
  // #-example-code
  //  Objective-C sample of how to create a stepping expression with multiple stops.
  NSNumber *initialValue = @4.0f;
  NSDictionary *stops = @{@11.0f : initialValue, @14.0f : @6.0f, @20.0f : @18.0f};

  NSExpression *steppingExpression = [NSExpression
      mgl_expressionForSteppingExpression:NSExpression.zoomLevelVariableExpression
                           fromExpression:[NSExpression expressionForConstantValue:initialValue]
                                    stops:[NSExpression expressionForConstantValue:stops]];
  // #-end-example-code

  XCTAssertNotNil(steppingExpression);
}

- (void)testSteppingExpression_ColorOverZoom {
  // #-example-code
  //  Objective-C sample of how to create a stepping expression with color.
  NSExpression *constantExpression = [NSExpression expressionWithFormat:@"%@", [MLNColor redColor]];
  NSExpression *stops = [NSExpression expressionForConstantValue:@{@18 : constantExpression}];
  NSExpression *functionExpression =
      [NSExpression mgl_expressionForSteppingExpression:NSExpression.zoomLevelVariableExpression
                                         fromExpression:constantExpression
                                                  stops:stops];
  // #-end-example-code

  XCTAssertNotNil(functionExpression);
  NSLog(@"%s %@", __FUNCTION__, functionExpression);
}

- (void)testInterpolatingExpression {
  // #-example-code
  //  Objective-C sample of how to create an interpolating expression with multiple stops.

  NSDictionary *opacityStops = @{@5.0f : @0.0f, @14.0 : @0.7f, @20.0f : @1.0f};
  NSExpression *stops = [NSExpression expressionForConstantValue:opacityStops];
  NSExpression *functionExpression = [NSExpression
      mgl_expressionForInterpolatingExpression:NSExpression.zoomLevelVariableExpression
                                 withCurveType:MLNExpressionInterpolationModeLinear
                                    parameters:nil
                                         stops:stops];
  // #-end-example-code

  XCTAssertNotNil(functionExpression);
  NSLog(@"%s %@", __FUNCTION__, functionExpression);
}

// MARK: - Valuation tests









// MARK: - Feature type tests


// MARK: - JSON expression object tests

- (void)testSemiliteral {
  NSArray *json = @[
    @"semiliteral",
    @[ @"top", @[ @"semiliteral", @[ @[ @"get", @"x" ], @2 ] ], @[ @"literal", @[ @1, @2 ] ] ]
  ];
  NSExpression *expression = [NSExpression expressionWithMLNJSONObject:json];
  XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, json);
  NSExpression *built = [NSExpression mgl_expressionForArray:@[
    [NSExpression expressionForConstantValue:@"top"], [NSExpression mgl_expressionForArray:@[
      [NSExpression expressionForKeyPath:@"x"], [NSExpression expressionForConstantValue:@2]
    ]],
    [NSExpression expressionForConstantValue:@[ @1, @2 ]]
  ]];
  XCTAssertEqualObjects(built.mgl_jsonExpressionObject, json);
  XCTAssertEqualObjects([NSExpression mgl_expressionForArray:@[]].mgl_jsonExpressionObject,
                        (@[ @"semiliteral", @[] ]));
  XCTAssertEqualObjects(
      [NSExpression expressionForAggregate:@[ [NSExpression expressionForConstantValue:@1] ]]
          .mgl_jsonExpressionObject,
      (@[ @"literal", @[ @1 ] ]));
}

- (void)testSemiliteralNonArrays {
  NSDictionary *object = @{@"x" : @[ @"get", @"x" ]};
  NSExpression *expression = [NSExpression expressionWithMLNJSONObject:@[ @"semiliteral", object ]];
  XCTAssertEqualObjects(expression.constantValue, object);
  XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, (@[ @"literal", object ]));
  XCTAssertThrowsSpecificNamed([NSExpression expressionWithMLNJSONObject:@[ @"semiliteral" ]],
                               NSException, NSInvalidArgumentException);
}


- (void)testConstantValueExpressionObject {
  {
    NSExpression *expression = [NSExpression expressionForConstantValue:nil];
    XCTAssert(expression.mgl_jsonExpressionObject == [NSNull null]);
    XCTAssert([NSExpression expressionWithFormat:@"nil"].mgl_jsonExpressionObject == [NSNull null]);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:[NSNull null]], expression);
    XCTAssertNil([expression expressionValueWithObject:nil context:nil]);
  }
  {
    NSExpression *expression = [NSExpression expressionForConstantValue:@1];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, @1);
    XCTAssertEqualObjects([NSExpression expressionWithFormat:@"1"].mgl_jsonExpressionObject, @1);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:@1], expression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @1);
  }
  {
    NSExpression *expression = [NSExpression expressionForConstantValue:@YES];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, @YES);
    XCTAssertEqualObjects([NSExpression expressionWithFormat:@"TRUE"].mgl_jsonExpressionObject,
                          @YES);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:@YES], expression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @YES);
  }
  {
    NSExpression *expression = [NSExpression expressionForConstantValue:nil];
    XCTAssert(expression.mgl_jsonExpressionObject == [NSNull null]);
    XCTAssert([NSExpression expressionWithFormat:@"nil"].mgl_jsonExpressionObject == [NSNull null]);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:[NSNull null]], expression);
    XCTAssertNil([expression expressionValueWithObject:nil context:nil]);
  }
  {
    CGVector vector = CGVectorMake(1, 2);
    NSExpression *expression = [NSExpression expressionForConstantValue:@(vector)];
#if !TARGET_OS_IPHONE
    NSArray *jsonExpression = @[ @"literal", @[ @1, @-2 ] ];
#else
    NSArray *jsonExpression = @[ @"literal", @[ @1, @2 ] ];
#endif
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    // No way to distinguish offsets from ordinary arrays in expressions.
    XCTAssertEqualObjects([[NSExpression expressionWithMLNJSONObject:jsonExpression].collection
                              valueForKeyPath:@"constantValue"],
                          jsonExpression.lastObject);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @(vector));
  }
  {
#if !TARGET_OS_IPHONE
    NSEdgeInsets padding = {1, 2, 3, 4};
    NSValue *value = [NSValue valueWithEdgeInsets:padding];
#else
    UIEdgeInsets padding = {1, 2, 3, 4};
    NSValue *value = [NSValue valueWithUIEdgeInsets:padding];
#endif
    NSExpression *expression = [NSExpression expressionForConstantValue:value];
    NSArray *jsonExpression = @[ @"literal", @[ @1, @4, @3, @2 ] ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    // No way to distinguish offsets from ordinary arrays in expressions.
    XCTAssertEqualObjects([[NSExpression expressionWithMLNJSONObject:jsonExpression].collection
                              valueForKeyPath:@"constantValue"],
                          jsonExpression.lastObject);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], value);
  }
  {
    MLNColor *color =
        ParityColorWithPremultipliedComponents(255.0 / 255, 239.0 / 255, 213.0 / 255, 1);  // papayawhip
    NSExpression *expression = [NSExpression expressionForConstantValue:color];
    NSArray *jsonExpression = @[ @"rgb", @255, @239, @213 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], color);
  }
  {
    // Transform color components to non-premultiplied values
    float alpha = 0.5;
    float red = (255.0 * alpha) / 255;
    float green = (239.0 * alpha) / 255;
    float blue = (213.0 * alpha) / 255;
    MLNColor *color = ParityColorWithPremultipliedComponents(red, green, blue, alpha);  // papayawhip
    NSExpression *expression = [NSExpression expressionForConstantValue:color];
    NSArray *jsonExpression = @[ @"rgba", @255.0, @239.0, @213.0, @0.5 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], color);
  }
  {
    // Transform color components to non-premultiplied values
    NSArray *jsonExpression = @[ @"rgba", @255.0, @239.0, @213.0, @0.5 ];
    NSExpression *papayawhipExpression = [NSExpression expressionWithMLNJSONObject:jsonExpression];
    MLNColor *papayaWhipColor = [papayawhipExpression expressionValueWithObject:nil context:nil];
    CGFloat convertedRed = 0.0, convertedGreen = 0.0, convertedBlue = 0.0, convertedAlpha = 0.0;
    [papayaWhipColor getRed:&convertedRed
                      green:&convertedGreen
                       blue:&convertedBlue
                      alpha:&convertedAlpha];

    XCTAssertEqualWithAccuracy(convertedRed, 255.0 / 255.0, 0.0000001);
    XCTAssertEqualWithAccuracy(convertedGreen, 239.0 / 255.0, 0.0000001);
    XCTAssertEqualWithAccuracy(convertedBlue, 213.0 / 255.0, 0.0000001);
    XCTAssertEqual(convertedAlpha, 0.5);
  }
  {
    NSExpression *expression = [NSExpression expressionWithFormat:@"noindex(513)"];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, @513);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @513);
  }
}

- (void)testKeyPathExpressionObject {
  {
    NSExpression *expression = [NSExpression expressionForKeyPath:@"highway"];
    NSArray *jsonExpression = @[ @"get", @"highway" ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithFormat:@"highway"].mgl_jsonExpressionObject,
                          jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression =
        [NSExpression expressionWithFormat:@"%@.population",
                                           @{@"population" : MLNConstantExpression(@12000)}];
    NSArray *jsonExpression =
        @[ @"get", @"population", @[ @"literal",
                                     @{@"population" : @12000} ] ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression =
        [NSExpression expressionWithFormat:@"%@.uppercase('population')",
                                           @{@"POPULATION" : MLNConstantExpression(@12000)}];
    NSArray *jsonExpression =
        @[ @"get", @[ @"upcase", @"population" ], @[ @"literal",
                                                     @{@"POPULATION" : @12000} ] ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionForKeyPath:@"lineStyle.color"];
    NSArray *jsonExpression = @[ @"get", @"color", @[ @"get", @"lineStyle" ] ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionForKeyPath:@"map.box.gl"];
    NSArray *jsonExpression = @[ @"get", @"gl", @[ @"get", @"box", @[ @"get", @"map" ] ] ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
}

- (void)testStatisticalExpressionObject {
  {
    NSExpression *expression =
        [NSExpression expressionWithFormat:@"average({1, 2, 2, 3, 4, 7, 9})"];
    NSArray *jsonExpression = @[
      @"/", @[ @"+", @1, @2, @2, @3, @4, @7, @9 ],
      @[ @"length", @[ @"literal", @[ @1, @2, @2, @3, @4, @7, @9 ] ] ]
    ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @4);
  }
  {
    NSExpression *expression = [NSExpression expressionWithFormat:@"sum({1, 2, 2, 3, 4, 7, 9})"];
    NSArray *jsonExpression = @[ @"+", @1, @2, @2, @3, @4, @7, @9 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @28);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionWithFormat:@"count({1, 2, 2, 3, 4, 7, 9})"];
    NSArray *jsonExpression = @[ @"length", @[ @"literal", @[ @1, @2, @2, @3, @4, @7, @9 ] ] ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @7);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionWithFormat:@"min({1, 2, 2, 3, 4, 7, 9})"];
    NSArray *jsonExpression = @[ @"min", @1, @2, @2, @3, @4, @7, @9 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @1);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionWithFormat:@"max({1, 2, 2, 3, 4, 7, 9})"];
    NSArray *jsonExpression = @[ @"max", @1, @2, @2, @3, @4, @7, @9 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @9);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
}

- (void)testArithmeticExpressionObject {
  NSArray *arguments = @[ MLNConstantExpression(@1), MLNConstantExpression(@1) ];
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"add:to:" arguments:arguments];
    NSArray *jsonExpression = @[ @"+", @1, @1 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithFormat:@"1 + 1"].mgl_jsonExpressionObject,
                          jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *testExpression = [NSExpression expressionWithFormat:@"sum:({1, 1, 2})"];
    NSExpression *expression =
        [NSExpression expressionForFunction:@"sum:"
                                  arguments:@[ [NSExpression expressionForAggregate:@[
                                    MLNConstantExpression(@1), MLNConstantExpression(@1),
                                    MLNConstantExpression(@2)
                                  ]] ]];

    NSArray *jsonExpression = @[ @"+", @1, @1, @2 ];

    XCTAssertEqualObjects(testExpression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects(expression, testExpression);
  }
  {
    NSExpression *expression =
        [NSExpression expressionForFunction:@"sum:"
                                  arguments:@[
                                    MLNConstantExpression(@1), MLNConstantExpression(@1),
                                    MLNConstantExpression(@2)
                                  ]];
    NSArray *jsonExpression = @[ @"+", @1, @1, @2 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);

    // - [NSExpression expressionWithMLNJSONObject:] creates an expression with an aggregate
    // expression as an argument. This is not equal to an expression with an array of expressions as
    // an argument. For testing purposes, we will compare their operands and arrays of expressions.
    NSExpression *aggregateExpression = [NSExpression expressionWithMLNJSONObject:jsonExpression];
    XCTAssertEqualObjects(aggregateExpression.operand, expression.operand);
    XCTAssertEqualObjects(aggregateExpression.arguments.firstObject.collection,
                          expression.arguments);
  }
  {
    NSArray *threeArguments =
        @[ MLNConstantExpression(@1), MLNConstantExpression(@1), MLNConstantExpression(@1) ];
    NSExpression *expression = [NSExpression expressionForFunction:@"add:to:"
                                                         arguments:threeArguments];
    NSArray *jsonExpression = @[ @"+", @1, @1, @1 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    jsonExpression = @[ @"+", @[ @"+", @1, @1 ], @1 ];
    XCTAssertEqualObjects([NSExpression expressionWithFormat:@"1 + 1 + 1"].mgl_jsonExpressionObject,
                          jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression],
                          [NSExpression expressionWithFormat:@"1 + 1 + 1"]);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"from:subtract:"
                                                         arguments:arguments];
    NSArray *jsonExpression = @[ @"-", @1, @1 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithFormat:@"1 - 1"].mgl_jsonExpressionObject,
                          jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"multiply:by:"
                                                         arguments:arguments];
    NSArray *jsonExpression = @[ @"*", @1, @1 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithFormat:@"1 * 1"].mgl_jsonExpressionObject,
                          jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"divide:by:"
                                                         arguments:arguments];
    NSArray *jsonExpression = @[ @"/", @1, @1 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithFormat:@"1 / 1"].mgl_jsonExpressionObject,
                          jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"modulus:by:"
                                                         arguments:arguments];
    NSArray *jsonExpression = @[ @"%", @1, @1 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    // NSExpression lacks a shorthand operator for modulus.
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"max:" arguments:arguments];
    NSArray *jsonExpression = @[ @"max", @1, @1 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);

    NSExpression *aggregateExpression = [NSExpression expressionWithMLNJSONObject:jsonExpression];
    XCTAssertEqualObjects(aggregateExpression.operand, expression.operand);
    XCTAssertEqualObjects(aggregateExpression.arguments.firstObject.collection,
                          expression.arguments);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"min:" arguments:arguments];
    NSArray *jsonExpression = @[ @"min", @1, @1 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);

    NSExpression *aggregateExpression = [NSExpression expressionWithMLNJSONObject:jsonExpression];
    XCTAssertEqualObjects(aggregateExpression.operand, expression.operand);
    XCTAssertEqualObjects(aggregateExpression.arguments.firstObject.collection,
                          expression.arguments);
  }
  {
    NSExpression *expression =
        [NSExpression expressionForFunction:@"ceiling:" arguments:@[ MLNConstantExpression(@1.5) ]];
    NSArray *jsonExpression = @[ @"ceil", @1.5 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @2);
  }
  {
    NSExpression *expression =
        [NSExpression expressionForFunction:@"ceiling:"
                                  arguments:@[ MLNConstantExpression(@-1.5) ]];
    NSArray *jsonExpression = @[ @"ceil", @-1.5 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @-1);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"ceiling:"
                                                         arguments:@[ MLNConstantExpression(@2) ]];
    NSArray *jsonExpression = @[ @"ceil", @2 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @2);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"ceiling:"
                                                         arguments:@[ MLNConstantExpression(@-2) ]];
    NSArray *jsonExpression = @[ @"ceil", @-2 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @-2);
  }
  {
    NSExpression *expression =
        [NSExpression expressionForFunction:@"trunc:" arguments:@[ MLNConstantExpression(@1.5) ]];
    NSArray *jsonExpression = @[ @"-", @1.5, @[ @"%", @1.5, @1 ] ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @1);
  }
  {
    NSExpression *expression =
        [NSExpression expressionForFunction:@"trunc:" arguments:@[ MLNConstantExpression(@-1.5) ]];
    NSArray *jsonExpression = @[ @"-", @-1.5, @[ @"%", @-1.5, @1 ] ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @-1);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"abs:"
                                                         arguments:@[ MLNConstantExpression(@2) ]];
    NSArray *jsonExpression = @[ @"abs", @2 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @2);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"abs:"
                                                         arguments:@[ MLNConstantExpression(@-2) ]];
    NSArray *jsonExpression = @[ @"abs", @-2 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @2);
  }
  {
    NSExpression *expression =
        [NSExpression expressionForFunction:@"floor:" arguments:@[ MLNConstantExpression(@1.5) ]];
    NSArray *jsonExpression = @[ @"floor", @1.5 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @1);
  }
  {
    NSExpression *expression =
        [NSExpression expressionForFunction:@"floor:" arguments:@[ MLNConstantExpression(@-1.5) ]];
    NSArray *jsonExpression = @[ @"floor", @-1.5 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @-2);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"floor:"
                                                         arguments:@[ MLNConstantExpression(@2) ]];
    NSArray *jsonExpression = @[ @"floor", @2 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @2);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"floor:"
                                                         arguments:@[ MLNConstantExpression(@-2) ]];
    NSArray *jsonExpression = @[ @"floor", @-2 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @-2);
  }
  {
#if TARGET_OS_IPHONE
    XCTExpectFailureWithOptions(@"Awaiting unit test refactoring for "
                     @"https://github.com/maplibre/maplibre-native/issues/331", [XCTExpectedFailureOptions nonStrictOptions]);
#endif
    NSExpression *expression =
        [NSExpression expressionForFunction:@"mgl_round:"
                                  arguments:@[ MLNConstantExpression(@1.5) ]];
    NSArray *jsonExpression = @[ @"round", @1.5 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @2);
  }
  {
    NSExpression *expression =
        [NSExpression expressionForFunction:@"mgl_round:"
                                  arguments:@[ MLNConstantExpression(@-1.5) ]];
    NSArray *jsonExpression = @[ @"round", @-1.5 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @-2);
  }
  {
    NSExpression *expression =
        [NSExpression expressionForFunction:@"mgl_round:"
                                  arguments:@[ MLNConstantExpression(@2.5) ]];
    NSArray *jsonExpression = @[ @"round", @2.5 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @3);
  }
  {
    NSExpression *expression =
        [NSExpression expressionForFunction:@"mgl_round:"
                                  arguments:@[ MLNConstantExpression(@-2.5) ]];
    NSArray *jsonExpression = @[ @"round", @-2.5 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @-3);
  }
}

- (void)testTrigonometricExpressionObject {
  NSArray *arguments = @[ MLNConstantExpression(@1), MLNConstantExpression(@1) ];
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"sqrt:" arguments:arguments];
    NSArray *jsonExpression = @[ @"sqrt", @1, @1 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"ln:" arguments:arguments];
    NSArray *jsonExpression = @[ @"ln", @1, @1 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
#if TARGET_OS_IPHONE
    XCTExpectFailureWithOptions(@"Awaiting unit test refactoring for "
                     @"https://github.com/maplibre/maplibre-native/issues/331", [XCTExpectedFailureOptions nonStrictOptions]);
#endif
    NSExpression *expression =
        [NSExpression expressionForFunction:@"mgl_log2:"
                                  arguments:@[ MLNConstantExpression(@1024) ]];
    NSArray *jsonExpression = @[ @"log2", @1024 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @10);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"raise:toPower:"
                                                         arguments:arguments];
    NSArray *jsonExpression = @[ @"^", @1, @1 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithFormat:@"1 ** 1"].mgl_jsonExpressionObject,
                          jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"exp:"
                                                         arguments:@[ MLNConstantExpression(@0) ]];
    NSArray *jsonExpression = @[ @"^", @[ @"e" ], @0 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @1);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionForConstantValue:@(M_E)];
    NSArray *jsonExpression = @[ @"e" ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @(M_E));
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionForConstantValue:@(M_PI)];
    NSArray *jsonExpression = @[ @"pi" ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @(M_PI));
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"mgl_acos:"
                                                         arguments:@[ MLNConstantExpression(@1) ]];
    NSArray *jsonExpression = @[ @"acos", @1 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @0);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"mgl_cos:"
                                                         arguments:@[ MLNConstantExpression(@0) ]];
    NSArray *jsonExpression = @[ @"cos", @0 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @1);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"mgl_asin:"
                                                         arguments:@[ MLNConstantExpression(@0) ]];
    NSArray *jsonExpression = @[ @"asin", @0 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @0);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"mgl_sin:"
                                                         arguments:@[ MLNConstantExpression(@0) ]];
    NSArray *jsonExpression = @[ @"sin", @0 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @0);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"mgl_atan:"
                                                         arguments:@[ MLNConstantExpression(@20) ]];
    NSArray *jsonExpression = @[ @"atan", @20 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    NSNumber *value = [expression expressionValueWithObject:nil context:nil];
    XCTAssertEqualWithAccuracy(value.doubleValue, 1.52, 0.001);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"mgl_tan:"
                                                         arguments:@[ MLNConstantExpression(@0) ]];
    NSArray *jsonExpression = @[ @"tan", @0 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @0);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
}

- (void)testShapeDistanceExpressionObject {
  {
    MLNPointAnnotation *point = [[MLNPointAnnotation alloc] init];
    point.coordinate = CLLocationCoordinate2DMake(1, -1);
#if TARGET_OS_IPHONE
    XCTExpectFailureWithOptions(@"Awaiting unit test refactoring for "
                     @"https://github.com/maplibre/maplibre-native/issues/331", [XCTExpectedFailureOptions nonStrictOptions]);
#endif
    NSExpression *expression =
        [NSExpression expressionForFunction:@"mgl_distanceFrom:"
                                  arguments:@[ MLNConstantExpression(point) ]];
    NSArray *jsonExpression =
        @[ @"distance",
           @{@"type" : @"Point",
             @"coordinates" : @[ @-1, @1 ]} ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertThrowsSpecificNamed([expression expressionValueWithObject:nil context:nil],
                                 NSException, NSInvalidArgumentException);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
}

- (void)testGlobalStateExpressionObject {
  {
    NSArray *jsonExpression = @[ @"global-state", @"chargerType" ];
    NSExpression *expression = [NSExpression expressionWithMLNJSONObject:jsonExpression];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertThrowsSpecificNamed([expression expressionValueWithObject:nil context:nil],
                                 NSException, NSInvalidArgumentException);
  }
}

- (void)testStringFormattingExpressionObject {
  NSArray *arguments = @[ MLNConstantExpression(@"MacDonald") ];
  {
    NSExpression *expression = [NSExpression
        expressionWithFormat:@"FUNCTION('Old', 'stringByAppendingString:', 'MacDonald')"];
#if TARGET_OS_IPHONE
    XCTExpectFailureWithOptions(@"Awaiting unit test refactoring for "
                     @"https://github.com/maplibre/maplibre-native/issues/331", [XCTExpectedFailureOptions nonStrictOptions]);
#endif
    NSExpression *aftermarketExpression =
        [NSExpression expressionWithFormat:@"mgl_join({'Old', 'MacDonald'})"];
    NSArray *jsonExpression = @[ @"concat", @"Old", @"MacDonald" ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects(aftermarketExpression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @"OldMacDonald");
    XCTAssertEqualObjects([aftermarketExpression expressionValueWithObject:nil context:nil],
                          @"OldMacDonald");
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression],
                          aftermarketExpression);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"mgl_join:"
                                                         arguments:@[ @"Old", @"MacDonald" ]];
    NSExpression *aftermarketExpression =
        [NSExpression expressionWithFormat:@"mgl_join({'Old', 'MacDonald'})"];
    NSArray *jsonExpression = @[ @"concat", @"Old", @"MacDonald" ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);

    XCTAssertEqualObjects(aftermarketExpression.mgl_jsonExpressionObject,
                          expression.mgl_jsonExpressionObject);
    NSExpression *aggregateExpression = [NSExpression expressionWithMLNJSONObject:jsonExpression];
    XCTAssertEqualObjects(aggregateExpression.operand, expression.operand);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"uppercase:"
                                                         arguments:arguments];
    NSArray *jsonExpression = @[ @"upcase", @"MacDonald" ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"lowercase:"
                                                         arguments:arguments];
    NSArray *jsonExpression = @[ @"downcase", @"MacDonald" ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"length:" arguments:arguments];
    NSArray *jsonExpression = @[ @"length", @"MacDonald" ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
}

- (void)testTypeConversionExpressionObject {
  {
    NSExpression *expression = [NSExpression expressionWithFormat:@"FUNCTION(number, 'boolValue')"];
    NSArray *jsonExpression = @[ @"to-boolean", @[ @"get", @"number" ] ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    // NSExpression is unable to evaluate -[NSNumber boolValue] by itself
    // because it returns a primitive instead of an object.
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression =
        [NSExpression expressionWithFormat:@"FUNCTION(postalCode, 'mgl_number')"];
    NSArray *jsonExpression = @[ @"to-number", @[ @"get", @"postalCode" ] ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithFormat:@"FUNCTION(postalCode, 'doubleValue')"]
                              .mgl_jsonExpressionObject,
                          jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithFormat:@"FUNCTION(postalCode, 'floatValue')"]
                              .mgl_jsonExpressionObject,
                          jsonExpression);
    XCTAssertEqualObjects(
        [NSExpression expressionWithFormat:@"FUNCTION(postalCode, 'decimalValue')"]
            .mgl_jsonExpressionObject,
        jsonExpression);
    // NSExpression is unable to evaluate NSNumber’s -floatValue,
    // -doubleValue, or -decimalValue by themselves because they each return
    // a primitive instead of an object.
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression],
                          [NSExpression expressionWithFormat:@"CAST(postalCode, 'NSNumber')"]);
  }
  {
    NSExpression *expression = [NSExpression
        expressionWithFormat:@"FUNCTION(postalCode, 'mgl_numberWithFallbackValues:', zipCode)"];
    NSArray *jsonExpression =
        @[ @"to-number", @[ @"get", @"postalCode" ], @[ @"get", @"zipCode" ] ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects(
        [NSExpression expressionWithFormat:@"FUNCTION(postalCode, 'doubleValue', zipCode)"]
            .mgl_jsonExpressionObject,
        jsonExpression);
    XCTAssertEqualObjects(
        [NSExpression expressionWithFormat:@"FUNCTION(postalCode, 'floatValue', zipCode)"]
            .mgl_jsonExpressionObject,
        jsonExpression);
    XCTAssertEqualObjects(
        [NSExpression expressionWithFormat:@"FUNCTION(postalCode, 'decimalValue', zipCode)"]
            .mgl_jsonExpressionObject,
        jsonExpression);
    // NSExpression is unable to evaluate NSNumber’s -floatValue,
    // -doubleValue, or -decimalValue by themselves because they each return
    // a primitive instead of an object.
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionWithFormat:@"CAST(postalCode, 'NSNumber')"];
    NSExpression *compatibilityExpression = [NSExpression
        expressionWithFormat:@"FUNCTION(postalCode, 'mgl_numberWithFallbackValues:')"];
    NSArray *jsonExpression = @[ @"to-number", @[ @"get", @"postalCode" ] ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects(compatibilityExpression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects(
        [expression expressionValueWithObject:@{@"postalCode" : @"02134"} context:nil], @02134);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionWithFormat:@"CAST(number, 'NSString')"];
    NSExpression *compatibilityExpression =
        [NSExpression expressionWithFormat:@"FUNCTION(number, 'stringValue')"];
    NSArray *jsonExpression = @[ @"to-string", @[ @"get", @"number" ] ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects(compatibilityExpression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:@{
                            @"number" : @1.5
                          }
                                                        context:nil],
                          @"1.5");
    XCTAssertEqualObjects([compatibilityExpression expressionValueWithObject:@{
                            @"number" : @1.5
                          }
                                                                     context:nil],
                          @"1.5");
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
#if TARGET_OS_IPHONE
    NSExpression *expression = [NSExpression expressionWithFormat:@"CAST(x, 'UIColor')"];
#else
    NSExpression *expression = [NSExpression expressionWithFormat:@"CAST(x, 'NSColor')"];
#endif

    NSArray *jsonExpression = @[ @"to-color", @[ @"get", @"x" ] ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
#if TARGET_OS_IPHONE
    XCTExpectFailureWithOptions(@"Awaiting unit test refactoring for "
                     @"https://github.com/maplibre/maplibre-native/issues/331", [XCTExpectedFailureOptions nonStrictOptions]);
#endif
    NSExpression *expression =
        [NSExpression expressionWithFormat:@"MLN_FUNCTION('to-color', x, y, z)"];
    NSArray *jsonExpression =
        @[ @"to-color", @[ @"get", @"x" ], @[ @"get", @"y" ], @[ @"get", @"z" ] ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
  }
  {
    NSExpression *expression = [NSExpression expressionWithFormat:@"CAST(noindex(x), 'NSArray')"];
    NSArray *jsonExpression = @[ @"to-rgba", @[ @"get", @"x" ] ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression =
        [NSExpression expressionWithFormat:@"CAST(noindex(%@), 'NSArray')",
                                           MLNConstantExpression(MLNColor.blueColor)];
    NSArray *jsonExpression = @[ @"to-rgba", @[ @"rgb", @0, @0, @255 ] ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionWithFormat:@"CAST(noindex('x'), 'NSArray')"];
    XCTAssertThrowsSpecificNamed(expression.mgl_jsonExpressionObject, NSException,
                                 NSInvalidArgumentException);
  }
}

- (void)testInterpolationExpressionObject {
  {
    NSDictionary *stops = @{@0 : MLNConstantExpression(@100), @10 : MLNConstantExpression(@200)};
    XCTExpectFailureWithOptions(@"Awaiting unit test refactoring for "
                     @"https://github.com/maplibre/maplibre-native/issues/331", [XCTExpectedFailureOptions nonStrictOptions]);
    NSExpression *expression = [NSExpression
        expressionWithFormat:
            @"mgl_interpolate:withCurveType:parameters:stops:(x, 'linear', nil, %@)", stops];
    NSExpression *compatibilityExpression = [NSExpression
        expressionWithFormat:
            @"FUNCTION(x, 'mgl_interpolateWithCurveType:parameters:stops:', 'linear', nil, %@)",
            stops];
    NSArray *jsonExpression =
        @[ @"interpolate", @[ @"linear" ], @[ @"get", @"x" ], @0, @100, @10, @200 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects(compatibilityExpression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSDictionary *stops = @{@1 : MLNConstantExpression(@2), @3 : MLNConstantExpression(@6)};
    NSExpression *expression = [NSExpression
        expressionWithFormat:
            @"mgl_interpolate:withCurveType:parameters:stops:(x, 'exponential', 2, %@)", stops];
    NSArray *jsonExpression =
        @[ @"interpolate", @[ @"exponential", @2 ], @[ @"get", @"x" ], @1, @2, @3, @6 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSDictionary *stops = @{@0 : MLNConstantExpression(@0), @100 : MLNConstantExpression(@100)};
    NSExpression *expression =
        [NSExpression expressionWithFormat:@"mgl_interpolate:withCurveType:parameters:stops:(x, "
                                           @"'cubic-bezier', { 0.42, 0, 0.58, 1 }, %@)",
                                           stops];
    NSArray *jsonExpression = @[
      @"interpolate", @[ @"cubic-bezier", @0.42, @0, @0.58, @1 ], @[ @"get", @"x" ], @0, @0, @100,
      @100
    ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSDictionary *stops = @{@0 : MLNConstantExpression(@111), @1 : MLNConstantExpression(@1111)};
    NSExpression *expression =
        [NSExpression expressionWithFormat:@"mgl_step:from:stops:(x, 11, %@)", stops];
    NSExpression *compatibilityExpression = [NSExpression
        expressionWithFormat:@"FUNCTION(x, 'mgl_stepWithMinimum:stops:', 11, %@)", stops];
    NSArray *jsonExpression = @[ @"step", @[ @"get", @"x" ], @11, @0, @111, @1, @1111 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects(compatibilityExpression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSDictionary *stops = @{@0 : MLNConstantExpression(@111), @1 : MLNConstantExpression(@1111)};
    NSExpression *expression =
        [NSExpression expressionWithFormat:@"mgl_step:from:stops:($zoomLevel, 11, %@)", stops];
    NSArray *jsonExpression = @[ @"step", @[ @"zoom" ], @11, @0, @111, @1, @1111 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSDictionary *stops = @{};
    NSExpression *expression =
        [NSExpression expressionWithFormat:@"mgl_interpolate:withCurveType:parameters:stops:(x, "
                                           @"'cubic-bezier', { 0.42, 0, 0.58, 1 }, %@)",
                                           stops];
    XCTAssertThrowsSpecificNamed(expression.mgl_jsonExpressionObject, NSException,
                                 NSInvalidArgumentException);
  }
  {
    NSDictionary *stops = @{};
    NSExpression *expression =
        [NSExpression expressionWithFormat:@"mgl_step:from:stops:($zoomLevel, 11, %@)", stops];
    XCTAssertThrowsSpecificNamed(expression.mgl_jsonExpressionObject, NSException,
                                 NSInvalidArgumentException);
  }
}

- (void)testMatchExpressionObject {
  {
#if TARGET_OS_IPHONE
    XCTExpectFailureWithOptions(@"Awaiting unit test refactoring for "
                     @"https://github.com/maplibre/maplibre-native/issues/331", [XCTExpectedFailureOptions nonStrictOptions]);
#endif
    NSExpression *expression = [NSExpression
        expressionWithFormat:@"MLN_MATCH(2 - 1,  %@, %@, %@, %@, 'default')",
                             MLNConstantExpression(@1), MLNConstantExpression(@"one"),
                             MLNConstantExpression(@0), MLNConstantExpression(@"zero")];
    NSExpression *predicate = [NSExpression expressionWithFormat:@"2 - 1"];
    NSExpression *compatibilityExpression =
        [NSExpression expressionWithFormat:@"FUNCTION(%@, 'mgl_match:', %@)", predicate, @[
          MLNConstantExpression(@1), MLNConstantExpression(@"one"), MLNConstantExpression(@0),
          MLNConstantExpression(@"zero"), MLNConstantExpression(@"default")
        ]];
    NSArray *jsonExpression = @[ @"match", @[ @"-", @2, @1 ], @1, @"one", @0, @"zero", @"default" ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects(compatibilityExpression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression
        expressionWithFormat:@"MLN_MATCH(2 * 1, %@, %@, 'default')", MLNConstantExpression(@1),
                             MLNConstantExpression(@"one")];
    NSArray *jsonExpression = @[ @"match", @[ @"*", @2, @1 ], @1, @"one", @"default" ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression
        expressionWithFormat:@"MLN_MATCH(x, {'a', 'A'}, 'Apple', {'b', 'B'}, 'Banana', 'Kumquat')"];
    NSArray *jsonExpression = @[
      @"match", @[ @"get", @"x" ], @[ @"a", @"A" ], @"Apple", @[ @"b", @"B" ], @"Banana", @"Kumquat"
    ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression =
        [NSExpression expressionWithFormat:@"MLN_MATCH(x, %@, 'Apple', %@, 'Banana', 'Kumquat')",
                                           @[ @"a", @"A" ], @"Bb"];
    NSArray *jsonExpression =
        @[ @"match", @[ @"get", @"x" ], @[ @"a", @"A" ], @"Apple", @"Bb", @"Banana", @"Kumquat" ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression].description,
                          expression.description);
  }
}

- (void)testCoalesceExpressionObject {
  {
#if TARGET_OS_IPHONE
    XCTExpectFailureWithOptions(@"Awaiting unit test refactoring for "
                     @"https://github.com/maplibre/maplibre-native/issues/331", [XCTExpectedFailureOptions nonStrictOptions]);
#endif
    NSExpression *expression = [NSExpression expressionWithFormat:@"mgl_coalesce(%@)", @[
      [NSExpression expressionForKeyPath:@"x"], [NSExpression expressionForKeyPath:@"y"],
      [NSExpression expressionForKeyPath:@"z"], [NSExpression expressionForConstantValue:@0]
    ]];
    NSExpression *compatibilityExpression =
        [NSExpression expressionWithFormat:@"FUNCTION(%@, 'mgl_coalesce')", @[
          [NSExpression expressionForKeyPath:@"x"], [NSExpression expressionForKeyPath:@"y"],
          [NSExpression expressionForKeyPath:@"z"], [NSExpression expressionForConstantValue:@0]
        ]];
    NSArray *jsonExpression =
        @[ @"coalesce", @[ @"get", @"x" ], @[ @"get", @"y" ], @[ @"get", @"z" ], @0 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects(compatibilityExpression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
}

- (void)testConditionalExpressionObject {
  {
    NSPredicate *conditional = [NSPredicate predicateWithFormat:@"1 = 2"];
    NSExpression *trueExpression = [NSExpression expressionForConstantValue:@YES];
    NSExpression *falseExpression = [NSExpression expressionForConstantValue:@NO];
    NSExpression *expression = [NSExpression expressionForConditional:conditional
                                                       trueExpression:trueExpression
                                                      falseExpression:falseExpression];
    NSArray *jsonExpression = @[ @"case", @[ @"==", @1, @2 ], @YES, @NO ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects(
        [NSExpression expressionWithFormat:@"TERNARY(1 = 2, TRUE, FALSE)"].mgl_jsonExpressionObject,
        jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @NO);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression =
        [NSExpression expressionWithFormat:@"TERNARY(0 = 1, TRUE, TERNARY(1 = 2, TRUE, FALSE))"];
    NSArray *jsonExpression =
        @[ @"case", @[ @"==", @0, @1 ], @YES, @[ @"case", @[ @"==", @1, @2 ], @YES, @NO ] ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @NO);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
#if TARGET_OS_IPHONE
    XCTExpectFailureWithOptions(@"Awaiting unit test refactoring for "
                     @"https://github.com/maplibre/maplibre-native/issues/331", [XCTExpectedFailureOptions nonStrictOptions]);
#endif
    NSExpression *expression = [NSExpression
        expressionWithFormat:@"MLN_IF(%@, %@, %@)",
                             [NSExpression
                                 expressionWithFormat:@"%@",
                                                      [NSPredicate predicateWithFormat:@"1 = 2"]],
                             MLNConstantExpression(@YES), MLNConstantExpression(@NO)];
    NSExpression *compatibilityExpression = [NSExpression
        expressionWithFormat:@"FUNCTION(%@, 'mgl_if:', %@)",
                             [NSPredicate predicateWithFormat:@"1 = 2"],
                             @[ MLNConstantExpression(@YES), MLNConstantExpression(@NO) ]];
    NSArray *jsonExpression = @[ @"case", @[ @"==", @1, @2 ], @YES, @NO ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects(compatibilityExpression.mgl_jsonExpressionObject, jsonExpression);
    expression = [NSExpression expressionWithFormat:@"TERNARY(1 = 2, YES, NO)"];
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @NO);
  }
  {
    NSExpression *expression = [NSExpression
        expressionWithFormat:@"MLN_IF(%@, %@, %@, %@, %@)",
                             [NSExpression
                                 expressionWithFormat:@"%@",
                                                      [NSPredicate predicateWithFormat:@"1 = 2"]],
                             MLNConstantExpression(@YES),
                             [NSExpression
                                 expressionWithFormat:@"%@",
                                                      [NSPredicate predicateWithFormat:@"1 = 1"]],
                             MLNConstantExpression(@YES), MLNConstantExpression(@NO)];
    NSArray *jsonExpression = @[ @"case", @[ @"==", @1, @2 ], @YES, @[ @"==", @1, @1 ], @YES, @NO ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @YES);
  }
  {
    NSArray *jsonExpression = @[
      @"case", @[ @"<", @[ @"get", @"area" ], @80000 ], @[ @"get", @"abbr" ],
      @[ @"get", @"name_en" ]
    ];
    NSExpression *expression =
        [NSExpression expressionWithFormat:@"TERNARY(area < 80000, abbr, name_en)"];
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
  }
}

- (void)testLookupExpressionObject {
  {
    NSExpression *array = [NSExpression expressionForAggregate:@[
      MLNConstantExpression(@9), MLNConstantExpression(@8), MLNConstantExpression(@7)
    ]];
    NSExpression *expression =
        [NSExpression expressionForFunction:@"objectFrom:withIndex:"
                                  arguments:@[ array, MLNConstantExpression(@"FIRST") ]];
    NSArray *jsonExpression = @[ @"at", @0, @[ @"literal", @[ @9, @8, @7 ] ] ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
  }
  {
    NSExpression *array = [NSExpression expressionForAggregate:@[
      MLNConstantExpression(@9), MLNConstantExpression(@8), MLNConstantExpression(@7)
    ]];
    NSExpression *expression =
        [NSExpression expressionForFunction:@"objectFrom:withIndex:"
                                  arguments:@[ array, MLNConstantExpression(@"LAST") ]];
    NSArray *jsonExpression = @[
      @"at", @[ @"-", @[ @"length", @[ @"literal", @[ @9, @8, @7 ] ] ], @1 ],
      @[ @"literal", @[ @9, @8, @7 ] ]
    ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
  }
  {
    NSExpression *array = [NSExpression expressionForAggregate:@[
      MLNConstantExpression(@9), MLNConstantExpression(@8), MLNConstantExpression(@7)
    ]];
    NSExpression *expression =
        [NSExpression expressionForFunction:@"objectFrom:withIndex:"
                                  arguments:@[ array, MLNConstantExpression(@"SIZE") ]];
    NSArray *jsonExpression = @[ @"length", @[ @"literal", @[ @9, @8, @7 ] ] ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
  }
  {
    NSExpression *array = [NSExpression expressionForAggregate:@[
      MLNConstantExpression(@9), MLNConstantExpression(@8), MLNConstantExpression(@7)
    ]];
    NSExpression *expression =
        [NSExpression expressionForFunction:@"objectFrom:withIndex:"
                                  arguments:@[ array, MLNConstantExpression(@1) ]];
    NSArray *jsonExpression = @[ @"at", @1, @[ @"literal", @[ @9, @8, @7 ] ] ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *array = [NSExpression expressionForAggregate:@[
      MLNConstantExpression(@9), MLNConstantExpression(@8), MLNConstantExpression(@7)
    ]];
    NSExpression *expression =
        [NSExpression expressionForFunction:@"objectFrom:withIndex:"
                                  arguments:@[ array, [NSExpression expressionForKeyPath:@"x"] ]];
    NSArray *jsonExpression = @[ @"at", @[ @"get", @"x" ], @[ @"literal", @[ @9, @8, @7 ] ] ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
#if TARGET_OS_IPHONE
    XCTExpectFailureWithOptions(@"Awaiting unit test refactoring for "
                     @"https://github.com/maplibre/maplibre-native/issues/331", [XCTExpectedFailureOptions nonStrictOptions]);
#endif
    NSExpression *expression =
        [NSExpression expressionForFunction:@"mgl_does:have:"
                                  arguments:@[
                                    [NSExpression expressionForEvaluatedObject],
                                    [NSExpression expressionForConstantValue:@"x"]
                                  ]];
    NSExpression *compatibilityExpression =
        [NSExpression expressionWithFormat:@"FUNCTION(self, 'mgl_has:', 'x')"];
    NSArray *jsonExpression = @[ @"has", @"x" ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects(compatibilityExpression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [NSExpression expressionForFunction:@"mgl_does:have:"
                                                         arguments:@[
                                                           MLNConstantExpression(
                                                               @{@"x" : MLNConstantExpression(@0)}),
                                                           MLNConstantExpression(@"x")
                                                         ]];
    NSArray *jsonExpression = @[ @"has", @"x", @[ @"literal", @{@"x" : @0} ] ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression =
        [NSExpression expressionForFunction:@"mgl_does:have:"
                                  arguments:@[
                                    [NSExpression expressionForVariable:@"featureAttributes"],
                                    [NSExpression expressionForConstantValue:@"x"]
                                  ]];
    NSArray *jsonExpression = @[ @"has", @"x", @[ @"properties" ] ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression;
    expression = [NSExpression expressionWithFormat:@"TERNARY(key != nil, 1, 0)"];
    NSArray *jsonExpression = @[ @"case", @[ @"!=", @[ @"get", @"key" ], [NSNull null] ], @1, @0 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
    XCTAssertEqualObjects([expression expressionValueWithObject:@{} context:nil], @NO);
    XCTAssertEqualObjects([expression expressionValueWithObject:@{@"key" : @"🗝"} context:nil],
                          @YES);
  }
  {
    NSDictionary *dictionary = @{@"key" : @"🔑"};
    NSExpression *expression;
    expression = [NSExpression expressionWithFormat:@"TERNARY(%@.key != nil, 1, 0)", dictionary];
    NSArray *jsonExpression = @[
      @"case", @[ @"!=", @[ @"get", @"key", @[ @"literal", dictionary ] ], [NSNull null] ], @1, @0
    ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    // The dictionary isn’t equal enough.
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression].description,
                          expression.description);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @YES);
  }
}

- (void)testFormatExpressionObject {
  {
    MLNAttributedExpression *attribute1 = [MLNAttributedExpression
        attributedExpression:[NSExpression expressionForConstantValue:@"foo"]
                   fontNames:nil
                   fontScale:@(1.2)];
    MLNAttributedExpression *attribute2 = [MLNAttributedExpression
        attributedExpression:[NSExpression expressionForConstantValue:@"biz"]
                   fontNames:nil
                   fontScale:@(1.0)];
    MLNAttributedExpression *attribute3 = [MLNAttributedExpression
        attributedExpression:[NSExpression expressionForConstantValue:@"bar"]
                   fontNames:nil
                   fontScale:@(0.8)];
    MLNAttributedExpression *attribute4 = [MLNAttributedExpression
        attributedExpression:[NSExpression expressionForConstantValue:@"\r"]
                   fontNames:@[]
                   fontScale:nil];
#if TARGET_OS_IPHONE
    XCTExpectFailureWithOptions(@"Awaiting unit test refactoring for "
                     @"https://github.com/maplibre/maplibre-native/issues/331", [XCTExpectedFailureOptions nonStrictOptions]);
#endif
    NSExpression *expression = [NSExpression
        expressionWithFormat:@"mgl_attributed:(%@, %@, %@, %@)", MLNConstantExpression(attribute1),
                             MLNConstantExpression(attribute4), MLNConstantExpression(attribute2),
                             MLNConstantExpression(attribute3)];
    NSArray *jsonExpression = @[
      @"format", @"foo",
      @{@"font-scale" : @1.2}, @"\r", @{}, @"biz",
      @{@"font-scale" : @1.0}, @"bar",
      @{@"font-scale" : @0.8}
    ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    MLNAttributedExpression *attribute1 = [MLNAttributedExpression
        attributedExpression:[NSExpression expressionForConstantValue:@"foo"]
                   fontNames:nil
                   fontScale:@(1.2)];
    MLNAttributedExpression *attribute2 = [MLNAttributedExpression
        attributedExpression:[NSExpression expressionForConstantValue:@"biz"]
                   fontNames:nil
                   fontScale:@(1.0)];
    MLNAttributedExpression *attribute3 = [MLNAttributedExpression
        attributedExpression:[NSExpression expressionForConstantValue:@"bar"]
                   fontNames:nil
                   fontScale:@(0.8)];
    MLNAttributedExpression *attribute4 = [MLNAttributedExpression
        attributedExpression:[NSExpression expressionForConstantValue:@"\n"]
                   fontNames:@[]
                   fontScale:nil];
    NSExpression *expression = [NSExpression
        expressionWithFormat:@"mgl_attributed:(%@, %@, %@, %@)", MLNConstantExpression(attribute1),
                             MLNConstantExpression(attribute4), MLNConstantExpression(attribute2),
                             MLNConstantExpression(attribute3)];
    NSArray *jsonExpression = @[
      @"format", @"foo",
      @{@"font-scale" : @1.2}, @"\n", @{}, @"biz",
      @{@"font-scale" : @1.0}, @"bar",
      @{@"font-scale" : @0.8}
    ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    MLNAttributedExpression *attribute1 = [MLNAttributedExpression
        attributedExpression:[NSExpression expressionForConstantValue:@"foo"]
                   fontNames:nil
                   fontScale:@(1.2)];
    NSExpression *expression = [NSExpression
        expressionWithFormat:@"mgl_attributed:(%@)", MLNConstantExpression(attribute1)];

    NSExpression *compatibilityExpression =
        [NSExpression expressionForFunction:@"mgl_attributed:"
                                  arguments:@[ MLNConstantExpression(attribute1) ]];
    NSArray *jsonExpression = @[ @"format", @"foo", @{@"font-scale" : @1.2} ];
    XCTAssertEqualObjects(compatibilityExpression.mgl_jsonExpressionObject,
                          expression.mgl_jsonExpressionObject);
    XCTAssertEqualObjects(compatibilityExpression, expression);
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    MLNAttributedExpression *attribute1 = [[MLNAttributedExpression alloc]
        initWithExpression:[NSExpression expressionForConstantValue:@"foo"]
                attributes:@{
                  MLNFontScaleAttribute : MLNConstantExpression(@(1.2)),
                  MLNFontColorAttribute : MLNConstantExpression(@"yellow")
                }];
    NSExpression *expression = [NSExpression
        expressionWithFormat:@"mgl_attributed:(%@)", MLNConstantExpression(attribute1)];

    NSExpression *compatibilityExpression =
        [NSExpression expressionForFunction:@"mgl_attributed:"
                                  arguments:@[ MLNConstantExpression(attribute1) ]];
    NSArray *jsonExpression =
        @[ @"format", @"foo",
           @{@"font-scale" : @1.2,
             @"text-color" : @"yellow"} ];
    XCTAssertEqualObjects(compatibilityExpression.mgl_jsonExpressionObject,
                          expression.mgl_jsonExpressionObject);
    XCTAssertEqualObjects(compatibilityExpression, expression);
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    MLNAttributedExpression *attribute1 = [[MLNAttributedExpression alloc]
        initWithExpression:[NSExpression expressionForConstantValue:@"foo"]];
    NSExpression *expression = [NSExpression
        expressionWithFormat:@"mgl_attributed:(%@)", MLNConstantExpression(attribute1)];

    NSArray *jsonExpression = @[ @"format", @"foo", @{} ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *fontNames = [NSExpression expressionForAggregate:@[
      MLNConstantExpression(@"DIN Offc Pro Bold"),
      MLNConstantExpression(@"Arial Unicode MS Bold")
    ]];
    MLNAttributedExpression *attribute1 = [[MLNAttributedExpression alloc]
        initWithExpression:[NSExpression expressionForConstantValue:@"foo"]
                attributes:@{
                  MLNFontScaleAttribute : MLNConstantExpression(@(1.2)),
                  MLNFontColorAttribute : MLNConstantExpression(@"yellow"),
                  MLNFontNamesAttribute : fontNames
                }];
    NSExpression *expression = [NSExpression
        expressionWithFormat:@"mgl_attributed:(%@)", MLNConstantExpression(attribute1)];

    NSArray *jsonExpression = @[
      @"format", @"foo", @{
        @"font-scale" : @1.2,
        @"text-color" : @"yellow",
        @"text-font" : @[ @"literal", @[ @"DIN Offc Pro Bold", @"Arial Unicode MS Bold" ] ]
      }
    ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *fontNames = [NSExpression expressionForAggregate:@[
      MLNConstantExpression(@"DIN Offc Pro Bold"),
      MLNConstantExpression(@"Arial Unicode MS Bold")
    ]];
    MLNAttributedExpression *attribute1 = [[MLNAttributedExpression alloc]
        initWithExpression:[NSExpression expressionForConstantValue:@"foo"]
                attributes:@{
                  MLNFontScaleAttribute : MLNConstantExpression(@(1.2)),
                  MLNFontColorAttribute : MLNConstantExpression([MLNColor redColor]),
                  MLNFontNamesAttribute : fontNames
                }];
    NSExpression *expression = [NSExpression
        expressionWithFormat:@"mgl_attributed:(%@)", MLNConstantExpression(attribute1)];

    NSArray *jsonExpression = @[
      @"format", @"foo", @{
        @"font-scale" : @1.2,
        @"text-color" : @[ @"rgb", @255, @0, @0 ],
        @"text-font" : @[ @"literal", @[ @"DIN Offc Pro Bold", @"Arial Unicode MS Bold" ] ]
      }
    ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *fontNames = [NSExpression expressionForAggregate:@[
      MLNConstantExpression(@"DIN Offc Pro Bold"),
      MLNConstantExpression(@"Arial Unicode MS Bold")
    ]];
    MLNAttributedExpression *attribute1 = [[MLNAttributedExpression alloc]
        initWithExpression:[NSExpression expressionWithFormat:@"CAST(x, 'NSString')"]
                attributes:@{
                  MLNFontScaleAttribute : MLNConstantExpression(@(1.2)),
                  MLNFontColorAttribute : MLNConstantExpression([MLNColor redColor]),
                  MLNFontNamesAttribute : fontNames
                }];
    NSExpression *expression = [NSExpression
        expressionWithFormat:@"mgl_attributed:(%@)", MLNConstantExpression(attribute1)];

    NSArray *jsonExpression = @[
      @"format", @[ @"to-string", @[ @"get", @"x" ] ], @{
        @"font-scale" : @1.2,
        @"text-color" : @[ @"rgb", @255, @0, @0 ],
        @"text-font" : @[ @"literal", @[ @"DIN Offc Pro Bold", @"Arial Unicode MS Bold" ] ]
      }
    ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    MLNAttributedExpression *attribute1 = [MLNAttributedExpression
        attributedExpression:[NSExpression expressionForConstantValue:@"foo"]
                   fontNames:nil
                   fontScale:@(1.2)];
    MLNAttributedExpression *attribute2 = [MLNAttributedExpression
        attributedExpression:[NSExpression expressionForConstantValue:@"biz"]
                   fontNames:nil
                   fontScale:@(1.0)];
    MLNAttributedExpression *attribute3 = [MLNAttributedExpression
        attributedExpression:[NSExpression expressionForConstantValue:@"bar"]
                   fontNames:nil
                   fontScale:@(0.8)];
    MLNAttributedExpression *attribute4 = [MLNAttributedExpression
        attributedExpression:[NSExpression expressionForConstantValue:@"\n"]
                   fontNames:@[]
                   fontScale:nil];
    NSExpression *expression = [NSExpression mgl_expressionForAttributedExpressions:@[
      MLNConstantExpression(attribute1), MLNConstantExpression(attribute4),
      MLNConstantExpression(attribute2), MLNConstantExpression(attribute3)
    ]];
    NSArray *jsonExpression = @[
      @"format", @"foo",
      @{@"font-scale" : @1.2}, @"\n", @{}, @"biz",
      @{@"font-scale" : @1.0}, @"bar",
      @{@"font-scale" : @0.8}
    ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
}

- (void)testGenericExpressionObject {
  {
#if TARGET_OS_IPHONE
    XCTExpectFailureWithOptions(@"Awaiting unit test refactoring for "
                     @"https://github.com/maplibre/maplibre-native/issues/331", [XCTExpectedFailureOptions nonStrictOptions]);
#endif
    NSExpression *expression =
        [NSExpression expressionWithFormat:@"MLN_FUNCTION('random', 1, 2, 3, 4, 5)"];
    NSArray *jsonExpression = @[ @"random", @1, @2, @3, @4, @5 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression =
        [NSExpression expressionWithFormat:@"MLN_FUNCTION('random', 1, 2, 3, 4)"];
    XCTAssertThrowsSpecificNamed([expression expressionValueWithObject:nil context:nil],
                                 NSException, NSInvalidArgumentException);
  }
  {
    NSArray *arguments = @[
      MLNConstantExpression(@"one"),
      MLNConstantExpression(@1),
      [NSExpression expressionForVariable:@"one"],
    ];
    NSExpression *nullaryExpression = [NSExpression expressionForFunction:@"MLN_LET"
                                                                arguments:arguments];
    NSExpression *unaryExpression = [NSExpression expressionForFunction:@"MLN_LET:"
                                                              arguments:arguments];
    XCTAssertEqualObjects(nullaryExpression.mgl_jsonExpressionObject,
                          unaryExpression.mgl_jsonExpressionObject);
  }
  {
    NSArray *arguments = @[
      [NSExpression expressionForVariable:@"x"],
      MLNConstantExpression(@YES),
      MLNConstantExpression(@"yes"),
      MLNConstantExpression(@NO),
      MLNConstantExpression(@"no"),
    ];
    NSExpression *nullaryExpression = [NSExpression expressionForFunction:@"MLN_MATCH"
                                                                arguments:arguments];
    NSExpression *unaryExpression = [NSExpression expressionForFunction:@"MLN_MATCH:"
                                                              arguments:arguments];
    XCTAssertEqualObjects(nullaryExpression.mgl_jsonExpressionObject,
                          unaryExpression.mgl_jsonExpressionObject);
  }
  {
    NSArray *arguments = @[
      [NSPredicate predicateWithValue:YES],
      MLNConstantExpression(@"yes"),
      MLNConstantExpression(@"no"),
    ];
    NSExpression *nullaryExpression = [NSExpression expressionForFunction:@"MLN_IF"
                                                                arguments:arguments];
    NSExpression *unaryExpression = [NSExpression expressionForFunction:@"MLN_IF:"
                                                              arguments:arguments];
    XCTAssertEqualObjects(nullaryExpression.mgl_jsonExpressionObject,
                          unaryExpression.mgl_jsonExpressionObject);
  }
  {
    NSArray *arguments = @[ MLNConstantExpression(@"zoom") ];
    NSExpression *nullaryExpression = [NSExpression expressionForFunction:@"MLN_FUNCTION"
                                                                arguments:arguments];
    NSExpression *unaryExpression = [NSExpression expressionForFunction:@"MLN_FUNCTION:"
                                                              arguments:arguments];
    XCTAssertEqualObjects(nullaryExpression.mgl_jsonExpressionObject,
                          unaryExpression.mgl_jsonExpressionObject);
  }
}

// MARK: - Localization tests

- (void)testLocalization {
  {
    NSExpression *original = MLNConstantExpression(@"");
    NSExpression *expected = original;
    XCTAssertEqualObjects([original mgl_expressionLocalizedIntoLocale:nil], expected);
  }
  {
    NSExpression *original = MLNConstantExpression(@"Old MacDonald");
    NSExpression *expected = original;
    XCTAssertEqualObjects([original mgl_expressionLocalizedIntoLocale:nil], expected);
  }
  {
    NSExpression *original = MLNConstantExpression(@"{name_en}");
    NSExpression *expected = original;
    XCTAssertEqualObjects([original mgl_expressionLocalizedIntoLocale:nil], expected);
  }
  {
    NSExpression *keyExpression = [NSExpression expressionForKeyPath:@"name_en"];
    MLNAttributedExpression *attributedExpression =
        [MLNAttributedExpression attributedExpression:keyExpression attributes:@{}];
    NSExpression *original = [NSExpression expressionForConstantValue:attributedExpression];

#if TARGET_OS_IPHONE
    XCTExpectFailureWithOptions(@"Awaiting unit test refactoring for "
                     @"https://github.com/maplibre/maplibre-native/issues/331", [XCTExpectedFailureOptions nonStrictOptions]);
#endif
    NSExpression *coalesceExpression =
        [NSExpression expressionWithFormat:@"mgl_coalesce({%K, %K})", @"name_en", @"name"];
    MLNAttributedExpression *expectedAttributedExpression =
        [MLNAttributedExpression attributedExpression:coalesceExpression attributes:@{}];
    NSExpression *expected = [NSExpression expressionForConstantValue:expectedAttributedExpression];
    XCTAssertEqualObjects([original mgl_expressionLocalizedIntoLocale:nil], expected);
  }
  {
    NSExpression *original = [NSExpression expressionForKeyPath:@"name_en"];
    NSExpression *expected =
        [NSExpression expressionWithFormat:@"mgl_coalesce({%K, %K})", @"name_en", @"name"];
    XCTAssertEqualObjects([original mgl_expressionLocalizedIntoLocale:nil], expected);
  }
  {
    NSExpression *original = [NSExpression expressionForKeyPath:@"name_en"];
    NSExpression *expected = [NSExpression expressionForKeyPath:@"name"];
    XCTAssertEqualObjects(
        [original mgl_expressionLocalizedIntoLocale:[NSLocale localeWithLocaleIdentifier:@"mul"]],
        expected);
  }
  {
    NSExpression *original = [NSExpression expressionForKeyPath:@"name_en"];
    NSExpression *expected =
        [NSExpression expressionWithFormat:@"mgl_coalesce({%K, %K})", @"name_fr", @"name"];
    XCTAssertEqualObjects(
        [original mgl_expressionLocalizedIntoLocale:[NSLocale localeWithLocaleIdentifier:@"fr-CA"]],
        expected);
  }
  {
    NSExpression *original = [NSExpression expressionForKeyPath:@"name_en"];
    NSExpression *expected =
        [NSExpression expressionWithFormat:@"mgl_coalesce({%K, %K, %K, %K})", @"name_zh-Hans",
                                           @"name_zh-CN", @"name_zh", @"name"];
    XCTAssertEqualObjects(
        [original
            mgl_expressionLocalizedIntoLocale:[NSLocale localeWithLocaleIdentifier:@"zh-Hans"]],
        expected);
  }
  {
    NSExpression *original =
        [NSExpression expressionWithFormat:@"mgl_coalesce({%K, %K})", @"name_en", @"name"];
    NSExpression *expected = [NSExpression
        expressionWithFormat:
            @"mgl_coalesce:({mgl_coalesce:({name_en, name}), mgl_coalesce:({name_en, name})})"];
    XCTAssertEqualObjects([original mgl_expressionLocalizedIntoLocale:nil], expected);
  }
  {
    NSExpression *original =
        [NSExpression expressionWithFormat:@"mgl_coalesce({%K, %K})", @"name_en", @"name"];
    NSExpression *expected = [NSExpression
        expressionWithFormat:
            @"mgl_coalesce:({mgl_coalesce:({name_ja, name}), mgl_coalesce:({name_ja, name})})"];
    XCTAssertEqualObjects(
        [original mgl_expressionLocalizedIntoLocale:[NSLocale localeWithLocaleIdentifier:@"ja-JP"]],
        expected);
  }
  {
    NSExpression *original = [NSExpression expressionForKeyPath:@"name_en"];
    NSExpression *expected = [NSExpression expressionForKeyPath:@"name"];
    XCTAssertEqualObjects(
        [original mgl_expressionLocalizedIntoLocale:[NSLocale localeWithLocaleIdentifier:@"tlh"]],
        expected);
  }
  {
    NSExpression *original =
        [NSExpression expressionWithFormat:@"mgl_step:from:stops:($zoomLevel, short, %@)", @{
          @1 : [NSExpression expressionForKeyPath:@"abbr"],
          @2 : @"…",
          @3 : [NSExpression expressionForKeyPath:@"name_fr"],
        }];
    NSExpression *expected =
        [NSExpression expressionWithFormat:@"mgl_step:from:stops:($zoomLevel, short, %@)", @{
          @1 : [NSExpression expressionForKeyPath:@"abbr"],
          @2 : @"…",
          @3 : [NSExpression expressionWithFormat:@"mgl_coalesce({%K, %K})", @"name_es", @"name"]
        }];
    XCTAssertEqualObjects(
        [original mgl_expressionLocalizedIntoLocale:[NSLocale localeWithLocaleIdentifier:@"es-PR"]],
        expected);
  }
  {
    NSArray *jsonExpression = @[
      @"step", @[ @"zoom" ],
      @[
        @"case", @[ @"<", @[ @"to-number", @[ @"get", @"area" ] ], @80000 ], @[ @"get", @"abbr" ],
        @[ @"get", @"name_en" ]
      ],
      @5, @[ @"get", @"name_en" ]
    ];
    NSArray *localizedJSONExpression = @[
      @"step", @[ @"zoom" ],
      @[
        @"case", @[ @"<", @[ @"to-number", @[ @"get", @"area" ] ], @80000 ], @[ @"get", @"abbr" ],
        @[ @"get", @"name" ]
      ],
      @5, @[ @"get", @"name" ]
    ];
    NSExpression *expression = [NSExpression expressionWithMLNJSONObject:jsonExpression];
    NSExpression *localizedExpression =
        [expression mgl_expressionLocalizedIntoLocale:[NSLocale localeWithLocaleIdentifier:@"mul"]];
    XCTAssertEqualObjects(localizedExpression.mgl_jsonExpressionObject, localizedJSONExpression);
  }
}

- (void)testConvenienceInitializers {
  {
    NSExpression *expression =
        [NSExpression mgl_expressionForConditional:[NSPredicate predicateWithFormat:@"1 = 2"]
                                    trueExpression:MLNConstantExpression(@YES)
                                  falseExpresssion:MLNConstantExpression(@NO)];

    NSArray *jsonExpression = @[ @"case", @[ @"==", @1, @2 ], @YES, @NO ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @NO);
  }
  {
    NSDictionary *stops = @{@0 : MLNConstantExpression(@111), @1 : MLNConstantExpression(@1111)};
    NSExpression *expression = [NSExpression
        mgl_expressionForSteppingExpression:[NSExpression expressionForKeyPath:@"x"]
                             fromExpression:[NSExpression expressionForConstantValue:@11]
                                      stops:[NSExpression expressionForConstantValue:stops]];
    NSArray *jsonExpression = @[ @"step", @[ @"get", @"x" ], @11, @0, @111, @1, @1111 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSDictionary *stops = @{@0 : MLNConstantExpression(@100), @10 : MLNConstantExpression(@200)};
    NSExpression *expression = [NSExpression
        mgl_expressionForInterpolatingExpression:[NSExpression expressionForKeyPath:@"x"]
                                   withCurveType:MLNExpressionInterpolationModeLinear
                                      parameters:nil
                                           stops:[NSExpression expressionForConstantValue:stops]];
    NSArray *jsonExpression =
        @[ @"interpolate", @[ @"linear" ], @[ @"get", @"x" ], @0, @100, @10, @200 ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSExpression *expression = [[NSExpression expressionForConstantValue:@"Old"]
        mgl_expressionByAppendingExpression:[NSExpression expressionForConstantValue:@"MacDonald"]];

    NSArray *jsonExpression = @[ @"concat", @"Old", @"MacDonald" ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([expression expressionValueWithObject:nil context:nil], @"OldMacDonald");
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
  {
    NSDictionary *values = @{MLNConstantExpression(@1) : MLNConstantExpression(@"one")};
    NSExpression *expression = [NSExpression
        mgl_expressionForMatchingExpression:[NSExpression expressionWithFormat:@"2 * 1"]
                               inDictionary:values
                          defaultExpression:[NSExpression expressionForConstantValue:@"default"]];
    NSArray *jsonExpression = @[ @"match", @[ @"*", @2, @1 ], @1, @"one", @"default" ];
    XCTAssertEqualObjects(expression.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSExpression expressionWithMLNJSONObject:jsonExpression], expression);
  }
}

// MARK: - Objective-C Example Code for Expected Failures

- (void)testExpectPassObjC {
  XCTAssertNotNil(@1);
}

/// https://developer.apple.com/documentation/xctest/expected_failures?language=objc
- (void)testExpectFailureObjC {
  XCTExpectFailureWithOptions(@"Objective-C example - Anticipate known test failures to prevent failing tests "
                   @"from affecting your workflows.", [XCTExpectedFailureOptions nonStrictOptions]);
  XCTAssertNotNil(nil);
}

@end
