// Based on platform/darwin/src/MLNCustomStyleLayer.mm at ios-v7.0.0
//
// Classic backed this class with an mbgl::style::CustomLayer whose host called
// the drawing methods during rendering. The C API has no custom layers, so the
// layer is represented in the style by a placeholder that draws nothing (an
// invisible background layer). It keeps the layer's identifier, position and
// object identity; the drawing methods are never called (C_API_GAPS.md).

#import "MLNCustomStyleLayer.h"
#import "MLNCustomStyleLayer_Private.h"

#import "MLNGeometry_Private.h"
#import "MLNLoggingConfiguration_Private.h"
#import "MLNMapView.h"
#import "MLNStyleLayer_Private.h"
#import "MLNStyle_Private.h"

#if MLN_RENDER_BACKEND_METAL
#import <MetalKit/MetalKit.h>
#endif

@interface MLNCustomStyleLayer ()
@property (nonatomic, readonly, nullable) MLNMapView *mapView;
@property (nonatomic, weak, readwrite) MLNStyle *style;
@end

@implementation MLNCustomStyleLayer {
  // The placeholder's visibility stays "none"; this is the layer's own.
  BOOL _layerVisible;
}

- (instancetype)initWithIdentifier:(NSString *)identifier {
  if (self = [super initWithIdentifier:identifier layerType:@"background" sourceIdentifier:nil]) {
    _layerVisible = YES;
    [self mgl_setJSON:@"none" forProperty:@"visibility" errorFormat:@"%@"];
    [self mgl_setJSON:@0 forProperty:@"background-opacity" errorFormat:@"%@"];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      MLNLogWarning(@"MLNCustomStyleLayer is not supported on the MapLibre Native C API: the layer "
                    @"keeps its place in the style but never draws. This will be logged only "
                    @"once.");
    });
  }
  return self;
}

- (MLNMapView *)mapView {
  if ([self.style.stylable isKindOfClass:[MLNMapView class]]) {
    return (MLNMapView *)self.style.stylable;
  }
  return nil;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#if TARGET_OS_IPHONE
- (EAGLContext *)context {
  // Only the OpenGL backend had a context; the C API renders with Metal.
  return nil;
}
#else
- (CGLContextObj)context {
  return NULL;
}
#endif
#pragma clang diagnostic pop

- (void)addToStyle:(MLNStyle *)style belowLayer:(MLNStyleLayer *)otherLayer {
  self.style = style;
  self.style.customLayers[self.identifier] = self;
  [super addToStyle:style belowLayer:otherLayer];
  // Classic called this when the core initialized the layer for rendering.
  if (self.mapView) {
    [self didMoveToMapView:self.mapView];
  }
}

- (void)removeFromStyle:(MLNStyle *)style {
  MLNMapView *mapView = self.mapView;
  [super removeFromStyle:style];
  if (mapView) {
    [self willMoveFromMapView:mapView];
  }
  self.style.customLayers[self.identifier] = nil;
  self.style = nil;
}

- (void)setVisible:(BOOL)visible {
  MLNAssertStyleLayerIsValid();

  _layerVisible = visible;
}

- (BOOL)isVisible {
  MLNAssertStyleLayerIsValid();

  return _layerVisible;
}

- (void)didMoveToMapView:(MLNMapView *)mapView {
}

- (void)willMoveFromMapView:(MLNMapView *)mapView {
}

- (void)preDrawInMapView:(MLNMapView *)mapView withContext:(MLNStyleLayerDrawingContext)context {
}

- (void)drawInMapView:(MLNMapView *)mapView withContext:(MLNStyleLayerDrawingContext)context {
}

- (void)setNeedsDisplay {
  id stylable = self.style.stylable;
  if ([stylable respondsToSelector:@selector(mgl_setNeedsRerender)]) {
    [(id<MLNFFIStylable>)stylable mgl_setNeedsRerender];
  }
}

@end
