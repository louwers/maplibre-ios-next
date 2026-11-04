// Copied from platform/darwin/test/MLNPredicateTests.mm at ios-v7.0.0 by Parity/Tests/Upstream/import-upstream.py.
// See ADAPTATIONS.md before editing.

@import MapLibre;
#import <XCTest/XCTest.h>


@implementation NSString (MLNAdditions)

- (NSString *)stringByRemovingPointerAddresses {
  return [self stringByReplacingOccurrencesOfString:@"\\b0x[0-9a-f]+\\b"
                                         withString:@"0xdeadbeef"
                                            options:NSRegularExpressionSearch
                                              range:NSMakeRange(0, self.length)];
}

@end

@interface MLNPredicateTests : XCTestCase
@end

@implementation MLNPredicateTests




- (void)testCompoundPredicates {
  {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"a == 'b' AND c == 'd'"];
    NSArray *jsonExpression =
        @[ @"all", @[ @"==", @[ @"get", @"a" ], @"b" ], @[ @"==", @[ @"get", @"c" ], @"d" ] ];
    XCTAssertEqualObjects(predicate.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSPredicate predicateWithMLNJSONObject:jsonExpression], predicate);
    [self testSymmetryWithPredicate:[NSPredicate predicateWithMLNJSONObject:jsonExpression]
                      mustRoundTrip:NO];
  }
  {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"a == 'b' OR c == 'd'"];
    NSArray *jsonExpression =
        @[ @"any", @[ @"==", @[ @"get", @"a" ], @"b" ], @[ @"==", @[ @"get", @"c" ], @"d" ] ];
    XCTAssertEqualObjects(predicate.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSPredicate predicateWithMLNJSONObject:jsonExpression], predicate);
    [self testSymmetryWithPredicate:[NSPredicate predicateWithMLNJSONObject:jsonExpression]
                      mustRoundTrip:NO];
  }
  {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"NOT(a == 'b' AND c == 'd')"];
    NSArray *jsonExpression = @[
      @"!", @[ @"all", @[ @"==", @[ @"get", @"a" ], @"b" ], @[ @"==", @[ @"get", @"c" ], @"d" ] ]
    ];
    XCTAssertEqualObjects(predicate.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSPredicate predicateWithMLNJSONObject:jsonExpression], predicate);
    [self testSymmetryWithPredicate:[NSPredicate predicateWithMLNJSONObject:jsonExpression]
                      mustRoundTrip:NO];
  }
  {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"NOT(a == 'b' OR c == 'd')"];
    NSArray *jsonExpression = @[
      @"!", @[ @"any", @[ @"==", @[ @"get", @"a" ], @"b" ], @[ @"==", @[ @"get", @"c" ], @"d" ] ]
    ];
    XCTAssertEqualObjects(predicate.mgl_jsonExpressionObject, jsonExpression);
    XCTAssertEqualObjects([NSPredicate predicateWithMLNJSONObject:jsonExpression], predicate);
    [self testSymmetryWithPredicate:[NSPredicate predicateWithMLNJSONObject:jsonExpression]
                      mustRoundTrip:NO];
  }
  {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"NOT a == nil"];
    NSArray *jsonExpression = @[ @"!", @[ @"==", @[ @"get", @"a" ], [NSNull null] ] ];
    XCTAssertEqualObjects(predicate.mgl_jsonExpressionObject, jsonExpression);
    [self testSymmetryWithPredicate:predicate mustRoundTrip:NO];
  }
  {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"NOT a != nil"];
    NSArray *jsonExpression = @[ @"!", @[ @"!=", @[ @"get", @"a" ], [NSNull null] ] ];
    XCTAssertEqualObjects(predicate.mgl_jsonExpressionObject, jsonExpression);
    [self testSymmetryWithPredicate:predicate mustRoundTrip:NO];
  }
}

- (void)testSymmetryWithPredicate:(NSPredicate *)forwardPredicate
                    mustRoundTrip:(BOOL)mustRoundTrip {
  // Parity: round-trips through the public JSON form instead of mbgl::style::Filter.
  NSPredicate *forwardPredicateAfter =
      [NSPredicate predicateWithMLNJSONObject:forwardPredicate.mgl_jsonExpressionObject];
  if (mustRoundTrip) {
    // A collection of ints may turn into an aggregate of longs, for
    // example, so compare formats instead of the predicates themselves.
    XCTAssertEqualObjects(forwardPredicate.predicateFormat.stringByRemovingPointerAddresses,
                          forwardPredicateAfter.predicateFormat.stringByRemovingPointerAddresses);
  } else {
    XCTAssertEqualObjects(forwardPredicate, forwardPredicateAfter);
  }
}

@end
