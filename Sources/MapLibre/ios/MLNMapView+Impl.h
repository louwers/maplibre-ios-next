// Based on platform/ios/src/MLNMapView+Impl.h at ios-v7.0.0
//
// Classic MLNMapViewImpl was the core's MapObserver and renderer backend
// (with MLNMapView+Metal.mm and MLNRendererFrontend.h). Here it owns the C API
// map and its render session: it renders into a CAMetalLayer through the
// session's core worker, demands frames from the view's display link, and
// turns the map's runtime events into MLNMapView's observer calls.

#pragma once

#import <MetalKit/MetalKit.h>
#import <UIKit/UIKit.h>

#import "MLNCoreShim.h"
#import "MLNFFI.h"

@class MLNMapView;

class MLNMapViewImpl {
 public:
  static std::unique_ptr<MLNMapViewImpl> Create(MLNMapView *nativeView, CGSize size,
                                                double scaleFactor);

  MLNMapViewImpl(MLNMapView *nativeView, CGSize size, double scaleFactor);
  ~MLNMapViewImpl();

  MLNFFIMap *ffiMap() const { return map; }
  mln::Map &shim() { return *shimMap; }

  /// Attaches the render session to a new CAMetalLayer view.
  void createView();
  /// Stops rendering into the view; the view stays until the map goes away.
  void deleteView();
  /// Demands a frame if none is outstanding. Called from the display link.
  void display();
  /// Demands a frame even if the map has no new update.
  void setNeedsForcedFrame() { forceNextFrame = true; }
  void layoutChanged();
  void setOpaque(bool opaque);
  /// The C API presents drawables itself; presentsWithTransaction is not
  /// configurable (C_API_GAPS.md). Kept for the view's bookkeeping.
  void setPresentsWithTransaction(bool) {}
  void reduceMemoryUse();
  void setTileCacheEnabled(bool enabled) { tileCacheEnabled = enabled; }
  bool getTileCacheEnabled() const { return tileCacheEnabled; }
  EAGLContext *getEAGLContext() { return nil; }
  /// The view that renders the map; annotation views are its subviews, as
  /// they were the MTKView's.
  UIView *getView() const { return metalView; }

  /// The view that the latest rendered frame drew; size zero before one.
  mln_map_view lastRenderedView() const { return renderedView; }

  void handleEvent(MLNFFIEvent *event);
  void drainFrameResults();

 private:
  __weak MLNMapView *mapView;
  MLNFFIMap *map;
  std::unique_ptr<mln::Map> shimMap;
  UIView *metalView = nil;
  id observer = nil;
  mln_render_session session = MLN_HANDLE_NULL;
  double scaleFactor;
  bool frameOutstanding = false;
  bool forceNextFrame = false;
  bool lastFrameNeedsRepaint = false;
  bool cameraChanging = false;
  bool rendering = false;
  bool tileCacheEnabled = true;
  bool opaque = false;
  uint64_t nextFrameToken = 1;
  mln_map_view renderedView = {};
};
