// Based on platform/darwin/src/MLNMultiPoint_Private.h at ios-v7.0.0
//
// Classic converted shape annotations to mbgl::Annotation for the core's
// annotation manager. The C API has none, so MLNMapView renders annotations
// with style layers; see MLNMapView+Annotations.

#import "MLNGeometry.h"
#import "MLNMultiPoint.h"

#import <CoreGraphics/CoreGraphics.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

@class MLNPolygon;
@class MLNPolyline;

@protocol MLNMultiPointDelegate;

@interface MLNMultiPoint (Private)

- (instancetype)initWithCoordinates:(const CLLocationCoordinate2D *)coords count:(NSUInteger)count;
- (BOOL)intersectsOverlayBounds:(MLNCoordinateBounds)overlayBounds;

@end

/** An object that tells the MLNMultiPoint instance how to style itself. */
@protocol MLNMultiPointDelegate <NSObject>

/** Returns the fill alpha value for the given annotation. */
- (double)alphaForShapeAnnotation:(MLNShape *)annotation;

/** Returns the stroke color object for the given annotation. */
- (MLNColor *)strokeColorForShapeAnnotation:(MLNShape *)annotation;

/** Returns the fill color object for the given annotation. */
- (MLNColor *)fillColorForPolygonAnnotation:(MLNPolygon *)annotation;

/** Returns the stroke width object for the given annotation. */
- (CGFloat)lineWidthForPolylineAnnotation:(MLNPolyline *)annotation;

@end

NS_ASSUME_NONNULL_END
