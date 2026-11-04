// Copied from platform/darwin/test/MLNStyleLayerTests.h at ios-v7.0.0 by Parity/Tests/Upstream/import-upstream.py.
// See ADAPTATIONS.md before editing.

@import MapLibre;
#import <XCTest/XCTest.h>

#define MLNConstantExpression(constant) [NSExpression expressionForConstantValue:constant]

@interface MLNStyleLayerTests : XCTestCase <MLNMapViewDelegate>

@property (nonatomic, copy, readonly, class) NSString *layerType;

- (void)testPropertyName:(NSString *)name isBoolean:(BOOL)isBoolean;

@end

@interface NSString (MLNStyleLayerTestAdditions)

@property (nonatomic, readonly, copy) NSArray<NSString *> *lexicalClasses;
@property (nonatomic, readonly, copy) NSString *lemma;

@end

@interface NSValue (MLNStyleLayerTestAdditions)

+ (instancetype)valueWithMLNVector:(CGVector)vector;

@property (readonly) CGVector MLNVectorValue;

@end
