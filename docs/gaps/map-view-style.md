# Map view, camera, rendering, style object model and annotations

Shortfalls of the MapLibre Native FFI C API (0.202610.3) for `MLNMapView`,
`MLNMapProjection`, `MLNStyle`, `MLNStyleLayer` and its subclasses,
`MLNLight` and the annotation API, and what maplibre-ios-next does instead.

## Execution model

- **Everything is asynchronous** (all of `MLNMapView`, `MLNStyle`, layers,
  sources). Classic called `mbgl::Map` on the main thread and every getter
  answered immediately. The C API runs each map on its runtime's worker thread
  and answers through completions; only `mln_map_get_snapshot`, projections,
  expression evaluation and GeoJSON preparation are synchronous. The bridge
  (`ffi/MLNFFI.h`) submits every call and blocks until its completion, so
  calls keep their order and a getter sees every earlier setter. Each style
  getter or setter is a round trip to the worker thread (classic: a function
  call); a busy worker (parsing a large style) blocks the main thread for as
  long, as it did in classic.
- **Events arrive on a worker thread** (all `MLNMapViewDelegate` callbacks).
  Classic's `MapObserver` ran inside the call that caused the change, on the
  main thread. The C API delivers runtime events on the worker before the
  command's completion. The bridge queues them and, after each blocking call
  on the main thread, delivers them before the call returns, so camera and
  style callbacks still happen during `setCenterCoordinate:…`,
  `-[MLNStyle addLayer:]` and so on. Events not caused by a call (animation
  frames, tile loads, rendering) are delivered asynchronously on the main
  queue, a run-loop turn later than classic.

## Rendering

- **The core renders on its own thread** (`MLNMapView`). Classic rendered on
  the main thread into an `MTKView` from `-[MLNMapView renderSync]`. The C API
  renders a `CAMetalLayer` from a render-session worker
  (`mln_map_attach_metal_surface`, `MLN_RENDER_DRIVER_CORE_WORKER`); the view
  demands one frame per display-link tick
  (`mln_render_session_request_frame`). Annotation views and the user location
  view are positioned from the camera at that tick, which may be one frame
  ahead of or behind the frame on screen.
- **No frame pacer or redraw wake** in the release; the view's
  `CADisplayLink` drives demands. FFI `main` adds `apple.h`'s frame pacer and a
  redraw wake.
- **`presentsWithTransaction`, pixel format and colorspace are not
  configurable** (`MLNMapView`'s transaction-synchronized presentation for
  annotation views and anchored callouts). The session presents with
  `presentDrawable` in `BGRA8Unorm`. The view keeps its bookkeeping but the
  setting has no effect.
- **The pixel ratio is fixed when the map is created**
  (`MLNMapView` moving to a screen with another scale). Classic created the
  renderer with the scale factor too, but could be recreated by the view; the
  C API map keeps `initial_extent.scale_factor` for its lifetime.
- **No release of the target for backgrounding** (`MLNMapView` entering the
  background). The view stops demanding frames instead. FFI `main` adds
  `mln_render_session_release_target`.
- **No local ideograph rendering** (`MLNIdeographicFontFamilyName`,
  `MLNRendererConfiguration.localFontFamilyName`). The C API creates the
  renderer without a local font family, so CJK glyphs come from the style's
  glyph server.
- **No per-map renderer options**: cross-source collisions
  (`MLNCollisionBehaviorPre4_0`), FastPFOR (`MLNMapOptions.fastPFOREnabled`),
  rendered feature info (`MLNMapOptions.featureInfoEnabled`) and the tile
  cache toggle (`MLNMapView.tileCacheEnabled`, kept as a value only) have no C
  API.
- **No shader compilation events** (`mapView:shaderWillCompile:…`,
  `shaderDidCompile:`, `shaderDidFailCompile:`); never called.
- **No answer to "can this unused image be removed"**
  (`mapView:shouldRemoveStyleImage:`); never called, images are kept.
- **Missing style images are answered late** (`mapView:didFailToLoadImage:`).
  Classic's core asked synchronously during layout and used the image in the
  same layout. The C API only raises an event; the image is added when the
  event arrives and the core lays out the affected tiles again.
- **Rendering statistics are a subset** (`MLNRenderingStats`). The C API
  reports encoding and rendering time, frame count and draw calls.
- **No backend resources** (`MLNMapView.backendResource`). The C API owns the
  Metal device, command buffers and render passes; the property returns an
  `MLNBackendResource` with nil members.
- **No action journal** (`MLNMapOptions.actionJournalOptions`,
  `-getActionJournalLog`, `-getActionJournalLogFiles`,
  `-clearActionJournalLog`): they return nil or do nothing.
- **No plugin layers of MapLibre iOS's kind** (`-[MLNMapView
  addPluginLayerType:]`, `MLNPluginLayer`). The C API's plugin ABI
  (`mln/plugin/plugin_api.h`) is a different, source-bound interface; the
  method logs an error.
- **No rendered feature count** (`-renderedFeatureCountForFeatureID:LayerID:SourceID:`).
  Emulated by querying the rendered features in the view and counting the
  matches.
- **Network reachability cannot trigger retries** (`MLNReachability`). Classic
  called `mbgl::NetworkStatus::Reachable()`, which retried failed requests.
  The C API can only set the online status.

## Camera

- **Animations do not replace each other** (all animated camera changes).
  The FFI's core patch 0015 animates camera fields independently, so a new
  animation only replaces the fields it sets. The shim cancels all transitions
  before each camera command, as the core did.
- **No per-frame transition callback** (`AnimationOptions.transitionFrameFn`,
  unused by the public API but used internally by classic for some
  animations). Completion handlers use the C API's transition end handler,
  which runs for completed, cancelled and replaced transitions as
  `transitionFinishFn` did.
- **No gesture flag** (`mbgl::Map::setGestureInProgress`). The C API tracks
  gestures through the phase of camera commands; the shim sends `BEGIN` with
  the first camera change of a gesture and an empty delta with `END` when it
  ends.
- **No standalone projection fitting** (`-[MLNMapProjection
  setVisibleCoordinateBounds:edgePadding:]`). `mln::MapProjection` fitted with
  its own transform; the C API projection cannot, so the map's
  `mln_map_camera_for_lat_lngs` is asked with the projection's bearing and
  pitch.
- **No meters-per-pixel without a map** (`MLNMetersPerPointAtLatitude…`,
  `MLNAltitudeForZoomLevel`). The core's formula is ported
  (`ffi/MLNCoreGeometry.h`).

## Style

- **No style name** (`MLNStyle.name`); read from the loaded style document
  (`mln_map_get_loaded_style_json`), which is what the core reported.
- **No default camera** (`-[MLNMapView resetPosition]`); read from the loaded
  style document's `center`, `zoom`, `bearing` and `pitch`.
- **No layer objects before a layer is in a style** (`MLNStyleLayer`
  initializers). Classic created a core layer in the initializer and owned it
  until it was added. The C API has none, so pending layers live in a hidden
  scratch map under an internal identifier, where the core validates and
  normalizes their properties exactly as in a style.
- **Layers whose source is missing are refused**
  (`-[MLNStyle addLayer:]` and friends with a layer whose source is not in the
  style). Classic's core added such layers (`TODO: verify source`). The C API
  returns `MLN_STATUS_NOT_FOUND` ("layer source does not exist"), so
  maplibre-ios-next keeps the layer back and adds it once a source with that
  identifier is added; until then it is not in `style.layers`.
- **Unset properties report nothing** (every style layer and light property
  getter). Classic fell back to the core's `getDefault…()`. The C API returns
  no value for an unset property, so the getter sets the style-spec default on
  a scratch layer of the same type once and returns the core's normalized
  value.
- **Visibility is not a layer property in the getter**
  (`MLNStyleLayer.visible`, `visibilityExpression`).
  `mln_map_get_style_layer_property("visibility")` reports nothing; the
  visibility comes from `mln_style_layer_info` and the expression from the
  layer's JSON.
- **Filters come back as stored** (`MLNVectorStyleLayer.predicate`). Classic
  converted the core's parsed filter expression back to a predicate; the C
  API returns the filter as it was given (a legacy filter stays legacy), which
  `+[NSPredicate predicateWithMLNJSONObject:]` converts.
- **Transitions are whole milliseconds** (`…Transition` properties,
  `MLNStyle.transition`). The C API takes transition JSON in milliseconds,
  which the core truncates to integers; classic kept nanoseconds.
- **Layer types without a darwin class** (location indicator, plugin layers)
  come back as plain `MLNStyleLayer` objects, as in classic.

## Annotations

- **No annotation manager** (`-addAnnotation:`, `-addAnnotations:`,
  `MLNPointAnnotation`, `MLNPolyline`, `MLNPolygon`, `MLNAnnotationImage`,
  annotation selection). The FFI is built with
  `MLN_WITH_LEGACY_ANNOTATIONS=OFF`. maplibre-ios-next draws annotations with
  three hidden GeoJSON sources and layers (symbols, lines, fills) above the
  style's layers, styled from feature properties, and hit-tests them with
  rendered-feature queries:
  - Classic kept one layer per shape annotation, ordered by insertion; here
    all fills draw below all lines, and features of one kind in insertion
    order.
  - Layers added at the top of the style go below the annotation layers,
    which stay on top as the core's did.
  - Annotation sources and layers are hidden from `MLNStyle.sources` and
    `.layers`; the core's own were hidden by its source type.
  - The annotations are added again after every style load, as the core did.
  - Rendered-feature queries without a layer filter can return annotation
    features with the SDK's own properties.
- `MLNAnnotationView`s, callouts and the user location view are UIKit and
  work as before.
