// Based on platform/ios/src/MLNMapView+Impl.mm and MLNMapView+Metal.mm at ios-v7.0.0

#import "MLNMapView+Impl.h"

#import "MLNLoggingConfiguration_Private.h"
#import "MLNMapView_Private.h"
#import "MLNStyle_Private.h"
#import "NSBundle+MLNAdditions.h"

#import <QuartzCore/CAMetalLayer.h>

/// The view the render session draws into.
@interface MLNMetalView : UIView
@end

@implementation MLNMetalView

+ (Class)layerClass {
  return [CAMetalLayer class];
}

@end

/// Receives the map's events on the main thread.
@interface MLNMapViewEventObserver : NSObject <MLNFFIMapEventObserver>
@property (nonatomic) MLNMapViewImpl *impl;
@end

@implementation MLNMapViewEventObserver

- (void)ffiMap:(MLNFFIMap *)map didReceiveEvent:(MLNFFIEvent *)event {
  if (self.impl) {
    self.impl->handleEvent(event);
  }
}

@end

namespace {

// Wakes run on a library thread and must not call into the C API. The
// observer outlives the impl, which clears its pointer when it goes away.
void frameWakeCallback(void *userData) {
  MLNMapViewEventObserver *observer = (__bridge MLNMapViewEventObserver *)userData;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (MLNMapViewImpl *impl = observer.impl) {
      impl->drainFrameResults();
    }
  });
}

void releaseObserver(void *userData) { CFBridgingRelease(userData); }

NSArray<NSString *> *fontStack(MLNFFIEvent *event) { return event.fontStack ?: @[]; }

NSRange glyphRange(MLNFFIEvent *event) {
  // The core reported glyph ranges as [first, second); the C API reports the
  // first and last code point of the range.
  return NSMakeRange(event.payload.glyphs.first,
                     event.payload.glyphs.last + 1 - event.payload.glyphs.first);
}

}  // namespace

std::unique_ptr<MLNMapViewImpl> MLNMapViewImpl::Create(MLNMapView *nativeView, CGSize size,
                                                      double scaleFactor) {
  return std::make_unique<MLNMapViewImpl>(nativeView, size, scaleFactor);
}

MLNMapViewImpl::MLNMapViewImpl(MLNMapView *nativeView, CGSize size, double scaleFactor_)
    : mapView(nativeView), scaleFactor(scaleFactor_) {
  map = [[MLNFFIMap alloc] initWithSize:size scaleFactor:scaleFactor mode:MLN_MAP_MODE_CONTINUOUS];
  if (!map) {
    [NSException raise:NSInternalInconsistencyException format:@"Failed to create the map."];
  }
  MLNMapViewEventObserver *eventObserver = [MLNMapViewEventObserver new];
  eventObserver.impl = this;
  observer = eventObserver;
  map.eventObserver = eventObserver;
  shimMap = std::make_unique<mln::Map>(map);
}

MLNMapViewImpl::~MLNMapViewImpl() {
  ((MLNMapViewEventObserver *)observer).impl = nullptr;
  map.eventObserver = nil;
  if (session != MLN_HANDLE_NULL) {
    mln_diagnostic diagnostic = {sizeof(mln_diagnostic)};
    mln_render_session_dispose(session, NULL, &diagnostic);
    session = MLN_HANDLE_NULL;
  }
  shimMap.reset();
  [map invalidate];
  [metalView removeFromSuperview];
}

void MLNMapViewImpl::createView() {
  rendering = true;
  if (metalView) {
    return;
  }
  MLNMapView *view = mapView;
  MLNMetalView *metal = [[MLNMetalView alloc] initWithFrame:view.bounds];
  metal.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  metal.contentScaleFactor = scaleFactor;
  metal.opaque = opaque;
  metal.layer.opaque = opaque;
  [view insertSubview:metal atIndex:0];
  metalView = metal;

  CAMetalLayer *layer = (CAMetalLayer *)metal.layer;
  layer.contentsScale = scaleFactor;

  mln_metal_surface_descriptor descriptor = {sizeof(mln_metal_surface_descriptor)};
  CGSize size = view.bounds.size;
  descriptor.logical_size = {(uint32_t)MAX(1, round(size.width)),
                             (uint32_t)MAX(1, round(size.height))};
  descriptor.layer = (__bridge void *)layer;
  mln_render_session_attach_options options = {sizeof(mln_render_session_attach_options)};
  options.driver = MLN_RENDER_DRIVER_CORE_WORKER;
  options.frame_wake.callback = frameWakeCallback;
  options.frame_wake.user_data = (void *)CFBridgingRetain(observer);
  options.frame_wake.release_user_data = releaseObserver;
  mln_map handle = map.handle;
  __block mln_render_session attached = MLN_HANDLE_NULL;
  __block mln_render_session *out = &attached;
  NSString *message;
  mln_status status = [map call:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
    return mln_map_attach_metal_surface(handle, &descriptor, &options, out, completion, diagnostic);
  }
                       consume:nil
                       message:&message];
  if (status != MLN_STATUS_OK && attached == MLN_HANDLE_NULL) {
    CFBridgingRelease(options.frame_wake.user_data);
  }
  if (status != MLN_STATUS_OK) {
    MLNLogError(@"Failed to attach the Metal surface: %@ (%@)", message,
                MLNFFIStatusDescription(status));
    return;
  }
  session = attached;
  shimMap->setRenderSession(session);
  frameOutstanding = false;
  forceNextFrame = true;
}

void MLNMapViewImpl::deleteView() { rendering = false; }

void MLNMapViewImpl::display() {
  if (!rendering || session == MLN_HANDLE_NULL || frameOutstanding) {
    return;
  }
  // A surface session shows each frame that it draws.
  mln_frame_demand demand = {sizeof(mln_frame_demand)};
  demand.flags = forceNextFrame || lastFrameNeedsRepaint ? MLN_FRAME_DEMAND_FORCE
                                                         : MLN_FRAME_DEMAND_WAIT_FOR_UPDATE;
  demand.token = nextFrameToken++;
  mln_diagnostic diagnostic = {sizeof(mln_diagnostic)};
  mln_status status = mln_render_session_demand_frame(session, &demand, &diagnostic);
  if (status == MLN_STATUS_OK) {
    frameOutstanding = true;
    forceNextFrame = false;
  } else if (status != MLN_STATUS_BUSY) {
    MLNLogDebug(@"Frame demand refused: %s (%@)", diagnostic.message, MLNFFIStatusDescription(status));
  }
}

void MLNMapViewImpl::drainFrameResults() {
  if (session == MLN_HANDLE_NULL) {
    return;
  }
  // A surface session may make the layer opaque when it configures it (wgpu
  // does), which turns the transparent pixels of a style without a background
  // black. The drawables keep their alpha, so the view's own opacity applies.
  if (metalView.layer.opaque != opaque) {
    metalView.layer.opaque = opaque;
  }
  mln_render_frame_batch batch = MLN_HANDLE_NULL;
  mln_render_frame_batch_view view = {sizeof(mln_render_frame_batch_view)};
  mln_diagnostic diagnostic = {sizeof(mln_diagnostic)};
  if (mln_render_session_drain_frame_results(session, &batch, &view, &diagnostic) != MLN_STATUS_OK) {
    return;
  }
  for (size_t i = 0; i < view.result_count; i++) {
    const mln_render_frame_result *result =
        MLN_STRIDED_AT(mln_render_frame_result, view.results, view.result_size, i);
    if (result->token == MLN_FRAME_DEMAND_TOKEN_STILL_IMAGE) {
      continue;
    }
    if (result->token == nextFrameToken - 1) {
      frameOutstanding = false;
    }
    switch (result->disposition) {
      case MLN_RENDER_RESULT_RENDERED:
        renderedView = result->view;
        lastFrameNeedsRepaint = result->needs_repaint;
        break;
      case MLN_RENDER_RESULT_TARGET_NOT_READY:
        forceNextFrame = true;
        break;
      default:
        break;
    }
  }
  if (batch != MLN_HANDLE_NULL) {
    mln_render_frame_batch_release(batch);
  }
}

void MLNMapViewImpl::layoutChanged() {
  MLNMapView *view = mapView;
  metalView.frame = view.bounds;
  forceNextFrame = true;
}

void MLNMapViewImpl::setOpaque(bool opaque_) {
  opaque = opaque_;
  metalView.opaque = opaque;
  metalView.layer.opaque = opaque;
}

void MLNMapViewImpl::reduceMemoryUse() {
  if (session == MLN_HANDLE_NULL) {
    return;
  }
  mln_render_session target = session;
  [map post:@"reduce memory use"
      submit:^(const mln_completion *completion, mln_diagnostic *diagnostic) {
        return mln_render_session_reduce_memory_use(target, completion, diagnostic);
      }];
}

void MLNMapViewImpl::handleEvent(MLNFFIEvent *event) {
  MLNMapView *view = mapView;
  if (!view) {
    return;
  }
  switch (event.type) {
    case MLN_RUNTIME_EVENT_MAP_CAMERA_WILL_CHANGE:
      cameraChanging = true;
      [view cameraWillChangeAnimated:event.code == MLN_CAMERA_CHANGE_MODE_ANIMATED];
      break;
    case MLN_RUNTIME_EVENT_MAP_CAMERA_IS_CHANGING:
      [view cameraIsChanging];
      break;
    case MLN_RUNTIME_EVENT_MAP_CAMERA_DID_CHANGE:
      cameraChanging = false;
      [view cameraDidChangeAnimated:event.code == MLN_CAMERA_CHANGE_MODE_ANIMATED];
      break;
    case MLN_RUNTIME_EVENT_MAP_LOADING_STARTED:
      [view mapViewWillStartLoadingMap];
      break;
    case MLN_RUNTIME_EVENT_MAP_LOADING_FINISHED:
      [view mapViewDidFinishLoadingMap];
      break;
    case MLN_RUNTIME_EVENT_MAP_LOADING_FAILED: {
      // The code is the core's MapLoadError.
      NSString *description;
      MLNErrorCode code;
      switch (event.code) {
        case 0:
          code = MLNErrorCodeParseStyleFailed;
          description = NSLocalizedStringWithDefaultValue(
              @"PARSE_STYLE_FAILED_DESC", nil, nil,
              @"The map failed to load because the style is corrupted.",
              @"User-friendly error description");
          break;
        case 1:
          code = MLNErrorCodeLoadStyleFailed;
          description = NSLocalizedStringWithDefaultValue(
              @"LOAD_STYLE_FAILED_DESC", nil, nil,
              @"The map failed to load because the style can’t be loaded.",
              @"User-friendly error description");
          break;
        case 2:
          code = MLNErrorCodeNotFound;
          description = NSLocalizedStringWithDefaultValue(
              @"STYLE_NOT_FOUND_DESC", nil, nil,
              @"The map failed to load because the style can’t be found or is incompatible.",
              @"User-friendly error description");
          break;
        default:
          code = MLNErrorCodeUnknown;
          description = NSLocalizedStringWithDefaultValue(
              @"LOAD_MAP_FAILED_DESC", nil, nil,
              @"The map failed to load because an unknown error occurred.",
              @"User-friendly error description");
      }
      NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey : description,
        NSLocalizedFailureReasonErrorKey : event.message,
      };
      NSError *error = [NSError errorWithDomain:MLNErrorDomain code:code userInfo:userInfo];
      [view mapViewDidFailLoadingMapWithError:error];
      break;
    }
    case MLN_RUNTIME_EVENT_MAP_RENDER_FRAME_STARTED:
      [view mapViewWillStartRenderingFrame];
      break;
    case MLN_RUNTIME_EVENT_MAP_RENDER_FRAME_FINISHED: {
      const mln_runtime_event_render_frame &frame = event.payload.render_frame;
      lastFrameNeedsRepaint = frame.needs_repaint;
      [view mapViewDidFinishRenderingFrameFullyRendered:frame.mode == MLN_RENDER_MODE_FULL
                                         renderingStats:frame.stats];
      break;
    }
    case MLN_RUNTIME_EVENT_MAP_RENDER_MAP_STARTED:
      [view mapViewWillStartRenderingMap];
      break;
    case MLN_RUNTIME_EVENT_MAP_RENDER_MAP_FINISHED:
      [view mapViewDidFinishRenderingMapFullyRendered:event.payload.render_map.mode ==
                                                      MLN_RENDER_MODE_FULL];
      break;
    case MLN_RUNTIME_EVENT_MAP_STYLE_LOADED:
      shimMap->restoreAnnotationsAfterStyleLoad();
      [view mapViewDidFinishLoadingStyle];
      break;
    case MLN_RUNTIME_EVENT_MAP_SOURCE_CHANGED: {
      MLNSource *source = [view.style sourceWithIdentifier:event.message];
      if (source) {
        [view sourceDidChange:source];
      }
      break;
    }
    case MLN_RUNTIME_EVENT_MAP_IDLE:
      // The core never became idle during a transition. Camera changes are
      // delivered within the call that starts them, ahead of an idle event the
      // worker raised before it, which is stale by then; the frames after the
      // change raise another.
      if (!cameraChanging) {
        [view mapViewDidBecomeIdle];
      }
      break;
    case MLN_RUNTIME_EVENT_MAP_STYLE_IMAGE_MISSING:
      [view didFailToLoadImage:event.message];
      break;
    case MLN_RUNTIME_EVENT_MAP_RENDER_ERROR:
      [view rendererDidError];
      break;
    case MLN_RUNTIME_EVENT_MAP_TILE_ACTION: {
      const mln_runtime_event_tile_action &action = event.payload.tile_action;
      [view tileDidTriggerAction:MLNTileOperation(static_cast<int>(action.operation))
                               x:action.tile_id.canonical_x
                               y:action.tile_id.canonical_y
                               z:action.tile_id.canonical_z
                            wrap:action.tile_id.wrap
                     overscaledZ:action.tile_id.overscaled_z
                        sourceID:event.message];
      break;
    }
    case MLN_RUNTIME_EVENT_MAP_GLYPHS_REQUESTED:
      [view glyphsWillLoad:fontStack(event) range:glyphRange(event)];
      break;
    case MLN_RUNTIME_EVENT_MAP_GLYPHS_LOADED:
      [view glyphsDidLoad:fontStack(event) range:glyphRange(event)];
      break;
    case MLN_RUNTIME_EVENT_MAP_GLYPHS_ERROR:
      [view glyphsDidError:fontStack(event) range:glyphRange(event)];
      break;
    case MLN_RUNTIME_EVENT_MAP_SPRITE_REQUESTED:
      [view spriteWillLoad:event.spriteIdentifier url:event.spriteURL];
      break;
    case MLN_RUNTIME_EVENT_MAP_SPRITE_LOADED:
      [view spriteDidLoad:event.spriteIdentifier url:event.spriteURL];
      break;
    case MLN_RUNTIME_EVENT_MAP_SPRITE_ERROR:
      [view spriteDidError:event.spriteIdentifier url:event.spriteURL];
      break;
    default:
      break;
  }
}
