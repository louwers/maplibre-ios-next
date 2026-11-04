// Stand-ins for the few internal helpers that upstream MapLibre iOS tests use,
// so the copied tests compile against the public API of either
// implementation. See Tests/Upstream/ADAPTATIONS.md.

#import <Foundation/Foundation.h>

#include <math.h>

/// mln::util::wrap (include/mln/math/wrap.hpp at ios-v7.0.0).
static inline double ParityWrap(double value, double min, double max) {
  if (value >= min && value < max) {
    return value;
  } else if (value == max) {
    return min;
  }
  const double delta = max - min;
  const double wrapped = min + fmod(value - min, delta);
  return value < min ? wrapped + delta : wrapped;
}

/// MLN_OBJC_DYNAMIC_CAST(_AS_PROTOCOL) from MLNFoundation_Private.h.
#define MLN_OBJC_DYNAMIC_CAST(object, type)                                       \
  ({                                                                              \
    __typeof__(object) temp##__LINE__ = (object);                                 \
    (type *)([temp##__LINE__ isKindOfClass:[type class]] ? temp##__LINE__ : nil); \
  })

#define MLN_OBJC_DYNAMIC_CAST_AS_PROTOCOL(object, proto)                                      \
  ({                                                                                          \
    __typeof__(object) temp##__LINE__ = (object);                                             \
    (id<proto>)([temp##__LINE__ conformsToProtocol:@protocol(proto)] ? temp##__LINE__ : nil); \
  })

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>

/// -[UIView mgl_frameForIdentifyTransform] from UIView+MLNAdditions.m.
static inline CGRect ParityFrameForIdentityTransform(UIView *view) {
  CGPoint center = view.center;
  CGSize size = view.bounds.size;
  return CGRectMake(center.x - size.width / 2, center.y - size.height / 2, size.width, size.height);
}
#endif

#if TARGET_OS_IPHONE
/// +[UIColor mgl_colorWithColor:] from UIColor+MLNAdditions.mm: the color for
/// premultiplied mln::Color components.
static inline UIColor *ParityColorWithPremultipliedComponents(float r, float g, float b, float a) {
  if (a == 0.0f) {
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
  }
  return [UIColor colorWithRed:(float)(r / a) green:(float)(g / a) blue:(float)(b / a) alpha:a];
}
#endif
