// Based on platform/ios/src/UIColor+MLNAdditions.h at ios-v7.0.0

#import <UIKit/UIKit.h>

/// Color components as mln::Color held them.
typedef struct MLNColorComponents {
  float r, g, b, a;
} MLNColorComponents;

@interface UIColor (MLNAdditions)

/// Premultiplied components, as mln::Color stores them.
- (MLNColorComponents)mgl_color;


- (MLNColorComponents)mgl_colorForPremultipliedValue;

+ (UIColor *)mgl_colorWithColor:(MLNColorComponents)color;
+ (UIColor *)mgl_colorWithPremultipliedRed:(float)red
                                      green:(float)green
                                       blue:(float)blue
                                      alpha:(float)alpha;

@end

@interface NSExpression (MLNColorAdditions)

+ (NSExpression *)mgl_expressionForRGBComponents:(NSArray<NSExpression *> *)components;
+ (NSExpression *)mgl_expressionForRGBAComponents:(NSArray<NSExpression *> *)components;
+ (UIColor *)mgl_colorWithRGBComponents:(NSArray<NSExpression *> *)components;

@end
