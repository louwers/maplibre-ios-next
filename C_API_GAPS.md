# Where the C API falls short

maplibre-ios-next implements the public API of MapLibre iOS 7.0.0 on the C API
of [MapLibre Native FFI](https://github.com/maplibre/maplibre-native-ffi).
Classic MapLibre iOS called the C++ core directly. This document lists every
place where the C API could not express what classic did, and what this
package does instead. The parity harness ([Parity/](Parity/)) measures the
remaining differences.

The package depends on the C API as implemented on
[maplibre-native-next](https://github.com/louwers/maplibre-native-next), a port
of the core to Rust that renders through wgpu, published as
[maplibre-native-next-ffi-distribution](https://github.com/louwers/maplibre-native-next-ffi-distribution).
The sections after the next one were written against the C++ implementation,
[maplibre-native-ffi-distribution](https://swiftpackageindex.com/maplibre/maplibre-native-ffi-distribution)
0.202610.3; they describe the C API itself, so they hold for both.

## On maplibre-native-next

maplibre-native-next-ffi-distribution 0.0.7 implements 172 of the C API's 203
functions (maplibre/maplibre-native-ffi#1589, with branch `next-ios` of
louwers/maplibre-native-ffi on top). The parity harness finds MapLibre iOS's
own tests with the same outcomes as classic, every camera, delegate,
annotation, style, offline and style-property trace the same except the
feature state removals below, and the render tests close to classic. What
differs from the C++ implementation:

- **Rendering is the Rust core's.** Of 171 render tests through
  `MLNMapSnapshotter`, 132 are pixel-identical to classic, 27 differ in under
  1 % of pixels, and 12 differ more: `fill-extrusion-opacity/function`,
  `line-gradient/gradient`, `line-gradient-dasharray/*`,
  `line-gradient/color-interpolation-rgb-hcl-lab`, `line-triangulation/*`,
  `line-miter-limit/global-state`, `line-translate/function`,
  `raster-masking/overlapping-vector`, `tilejson-bounds/default` and
  `within/paint-circle`. These are differences of maplibre-native-next's
  renderer, not of this package. Of the 10 render tests through an on-screen
  `MLNMapView`, 9 are identical and 1 differs in under 1 % of pixels.
- **The Metal layer's opacity** (`MLNMapView.opaque`). wgpu configures the
  surface as opaque and marks the `CAMetalLayer` opaque, so the transparent
  pixels of a style without a background would show black. The map view
  restores its own opacity on the layer on each display-link tick; the
  drawables keep their alpha. wgpu also creates its own Metal device and turns
  off `allowsNextDrawableTimeout`.
- **No NSURLSession hook** (`MLNNetworkConfiguration.sessionConfiguration`,
  `.delegate`). maplibre-native-next fetches over HTTP with its own client,
  not NSURLSession, and has no `MLNNativeNetworkManager`. Only the session
  configuration's additional HTTP headers apply, through the C API's header
  transform. Offline downloads of `file:` URLs still work through the resource
  provider described under Offline storage.
- **Camera transitions**: one at a time, as in upstream MapLibre Native; the
  map view cancels before each change anyway, as it did in classic.
- **Not implemented by maplibre-native-next**: custom vector sources (not
  used by MapLibre iOS), texture rings, and the rendering statistics overlay
  (`-[MLNMapView enableRenderingStatsView:]`: the flag is kept, nothing is
  drawn).
  Calls the C API leaves unimplemented return `MLN_STATUS_UNSUPPORTED`; this
  package treats them as doing nothing and logs the first of each.
- **Text**: `number-format` with a currency formats without the currency
  symbol in the Rust core.

## Summary

The public API is complete: the 85 public headers are byte-identical to the
7.0.0 XCFramework's, and every class, method and constant exists. What
differs is behavior, for these reasons.

**The C API's model differs from mbgl's.**

| Area | Classic (C++ core) | C API | maplibre-ios-next |
|---|---|---|---|
| Calls | Synchronous, on the main thread | Asynchronous, on a worker thread, in order | Blocks on each call; a getter sees every earlier setter |
| Events | Inside the call that caused them | On the worker thread, before the command's completion | Queued and delivered on the main thread before the call returns |
| Rendering | Main thread, `MTKView` | Render-session worker, `CAMetalLayer` | Display link demands frames; UIKit overlays follow the camera of the tick |
| Style objects | Typed `mbgl::style::Layer`/`Source` objects, detachable | JSON in, JSON out, inside a map only | Pending layers live in a hidden scratch map; sources keep their configuration |
| Unset properties | `getDefault…()` | No value | Spec default normalized by the core once, cached |

**The C API lacks these features**, so they are emulated or do nothing:

| Feature | Public API affected | maplibre-ios-next |
|---|---|---|
| Annotation manager | `addAnnotation(s):`, `MLNPointAnnotation`, `MLNPolyline`, `MLNPolygon`, `MLNAnnotationImage`, snapshot annotations | Emulated with a GeoJSON source and the core's annotation layers |
| Custom layers | `MLNCustomStyleLayer` drawing | Invisible placeholder layer; draw callbacks never run |
| MapLibre iOS plugin layers | `MLNPluginLayer`, `addPluginLayerType:` | Logged; not available |
| Tile server options, API key | `MLNSettings`, `mapbox://`, `maptiler://` | Kept as values; only `maplibre://` resolves |
| Local ideograph font | `MLNIdeographicFontFamilyName` | Glyphs come from the glyph server |
| HTTP session hook | `MLNNetworkConfiguration` session and delegate | Uses the FFI framework's unexported `MLNNativeNetworkManager` |
| Cache writes, tile limit | `preloadData:`, `setMaximumAllowedMapboxTiles:` | Error / nothing, logged |
| Action journal, backend resources | `getActionJournalLog`, `backendResource` | nil |
| Rendering statistics beyond timings | `MLNRenderingStats` | Only timings and draw calls |
| Shader and image-removal callbacks | `shaderWillCompile:…`, `shouldRemoveStyleImage:` | Never called |
| Synchronous missing-image answer | `mapView:didFailToLoadImage:` | Image added when the event arrives |
| Style name, default camera | `MLNStyle.name`, `resetPosition` | Read from the loaded style document |
| Layers before their source | `addLayer:` | Added on a hidden placeholder source |
| `presentsWithTransaction`, pixel format | `MLNMapView` | Not configurable |
| Pixel ratio changes | `MLNMapView` | Fixed at creation |
| x86_64 simulator | Apps built for Intel simulators | The FFI XCFramework's simulator slice is arm64 only |

**Fixed on FFI `main`, not yet released**: a frame pacer and redraw wake
(`apple.h`), releasing the render target in the background, camera fit
commands, dedicated cluster queries, typed feature identifiers, failing a
resource transform, and transform rules.

The sections below give each shortfall with the public API it affects, what
classic did, what the C API offers, and what this package does.

## Map view, rendering, camera, style and annotations

### Execution model

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
  command's completion. The bridge queues them. After each blocking call on
  the main thread it delivers the events of the kinds classic raised within a
  call (camera changes, the start of a style load, and a style loaded from
  JSON), so `regionWillChange`/`regionDidChange` still happen during
  `setCenterCoordinate:…`. Everything else (style and tile loads, rendering,
  idleness) is delivered on a later turn of the main queue, in order, as
  classic delivered it. The C API's order of events can still differ from
  classic's where the C API runs work synchronously that the core did
  asynchronously, below.
- **Local styles load within the call** (`MLNMapView.styleURL` with a
  `file:` URL, `MLNMapSnapshotter`). Classic's core read every style through
  its file source, asynchronously, so camera changes made right after setting
  a style URL happened before the style loaded, and the style's default
  camera (`center`, `zoom`, `bearing`, `pitch`) was then not applied. The C API
  can load a local style during `mln_map_set_style_url`, before those camera
  changes, so the default camera applies first and only the fields the app
  sets override it. The snapshotter sets its camera before loading the style
  to keep classic's result; `MLNMapView` cannot reorder the app's calls. For
  the same reason, `mapView:didFinishLoadingStyle:` of a local style comes
  before `mapViewWillStartRenderingMap:`, where classic had it after: the
  style is loaded before the first frame is rendered.
- **Idle during a transition** (`mapViewDidBecomeIdle:`). The core reported
  idle only after a frame that needed no repaint while no transition ran.
  The C API's worker renders concurrently with the main thread, so an idle
  event raised between two animations can be delivered after the second one
  has started (whose camera events the bridge delivers within the call). The
  map view drops idle events while a camera change is in progress; the frames
  after it raise another. That one can come sooner than classic's: in the
  harness (`MLNDelegateTraceTests.testCameraChangeSequence`) it arrives within
  0.5 s of an eased camera change's completion handler, and classic's does
  not.
- **A replaced style load may already have finished** (setting `styleURL` or
  `styleJSON` while another style loads, such as right after
  `-initWithFrame:`, which loads the default style). Classic's core cancelled
  the earlier load, which never reported anything. The C API may have finished
  it on its worker, from the cache, before the new load runs. The bridge drops
  the earlier load's undelivered events (style loaded, loading finished or
  failed, sprites, glyphs, source changes) when a new style is set, so the app
  sees one `mapView:didFinishLoadingStyle:` as before.

### Rendering

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

### Camera

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

### Style

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
  returns `MLN_STATUS_NOT_FOUND` ("layer source does not exist"), so the layer
  is added on a hidden, empty placeholder source of the kind it needs
  (`org.maplibre.next.placeholder.<vector|raster|raster-dem>.<source>`) and
  still reports its own source. Adding the source later moves the layers onto
  it in place. A layer that does not fit the source added later is logged and
  dropped; classic kept it, unrendered.
- **Layers inserted below a layer that is not in the style**
  (`-[MLNStyle insertLayer:belowLayer:]` with a sibling that was never added).
  Classic's core put the layer on top; the C API refuses
  (`before_layer_id does not exist`), so the sibling is dropped and the layer
  goes on top.
- **Layer JSON does not round-trip** (moving a layer between the scratch map
  and a style, `-[MLNStyle removeLayer:]` followed by `-addLayer:`). The C API
  serializes constant formatted text as `{"sections": …}` and constant images
  as `{"name": …, "available": …}`, which it then refuses as property values
  ("function value must specify stops"). Such values are rewritten as
  `["format", …]` expressions and plain image names before the JSON is added
  again.
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

### Annotations

- **No annotation manager** (`-addAnnotation:`, `-addAnnotations:`,
  `MLNPointAnnotation`, `MLNPolyline`, `MLNPolygon`, `MLNAnnotationImage`,
  annotation selection). The FFI is built with
  `MLN_WITH_LEGACY_ANNOTATIONS=OFF`. maplibre-ios-next reproduces what the
  core's `AnnotationManager` put in the style, which apps can see in
  `MLNStyle.sources` and `.layers`:
  - the source `org.maplibre.annotations` in every style (an `MLNSource`), here
    a GeoJSON source with one feature per annotation, its tag as the feature
    ID;
  - the symbol layer `org.maplibre.annotations.points` with classic's icon
    expression, `icon-allow-overlap` and `icon-ignore-placement`;
  - one line or fill layer `org.maplibre.annotations.shape.<tag>` per shape
    annotation, below the point layer, with the annotation's opacity, colors
    and width as constants;
  - annotation images as style images named `org.maplibre.annotations.<name>`.

  Classic's source had one tile layer per annotation layer; a GeoJSON source
  has none, so the layers select their features with a filter (their
  `predicate` is not nil, unlike classic's), while `sourceLayerIdentifier`
  keeps classic's names. Annotations are hit-tested with rendered-feature
  queries on those layers and come back after every style load, as classic's
  did.
- `MLNAnnotationView`s, callouts and the user location view are UIKit and
  work as before.

## Sources, style images and custom layers

- **Sources are created from configuration, not core objects** (`MLNSource`
  and all subclasses). Classic created an `mbgl::style::Source` in the
  initializer and handed it to the style. The C API has no detached source
  objects: a source exists only inside a map's style. Pending sources keep
  their configuration in Objective-C and serialize it (style-spec JSON, or the
  GeoJSON/custom-geometry/image-source calls) when they are added.
- **A removed source of a loaded style cannot always be added back**
  (`-[MLNStyle removeSource:]` followed by `-addSource:`). Classic got the
  core source object back on removal. The C API reports a source's metadata
  (`mln_map_get_style_source`) but not its data: tile sources are recreated
  from the reported URL or tile set, and GeoJSON and image sources from their
  URL, but inline GeoJSON data and inline image pixels of a source that came
  from the style are lost, and other source types (custom vector, video) cannot
  be added again (`MLNRedundantSourceIdentifierException` with an explanation).
- **No GeoJSON read-back** (`MLNShapeSource.shape`). As in classic, `shape` is
  only the shape the source was given through the SDK; it is nil for a source
  of a loaded style. The C API cannot return a source's GeoJSON.
- **GeoJSON options are fixed and must match the data**
  (`MLNShapeSource.shape`, `.URL`). The C API prepares GeoJSON with
  `mln_geo_json_source_data_create` and refuses data prepared with options
  that differ from the source's. The options of a GeoJSON source that came from
  the style are not reported, so setting `shape` on it prepares the data with
  default options; for a clustered or otherwise configured style source this
  fails and logs an error. Classic reused the source's own options.
- **Clustered data must be a feature collection of points**
  (`MLNShapeSourceOptionClustered`). The C API refuses a single feature or a
  bare geometry for a clustered source; such shapes are wrapped in a feature
  collection. Non-point features are refused by the C API (classic's
  supercluster could not handle them either).
- **Cluster property expressions are not validated up front**
  (`MLNShapeSourceOptionClusterProperties`). Classic parsed each map and reduce
  expression with the core when the source was created and raised
  `NSInvalidArgumentException` for an invalid one. They are sent to the C API
  as the style-spec `clusterProperties` object instead, so an invalid
  expression makes adding the source fail
  (`MLNRedundantSourceIdentifierException` with the C API's message).
- **Cluster queries** (`-leavesOfCluster:offset:limit:`,
  `-childrenOfCluster:`, `-zoomLevelForExpandingCluster:`) go through
  `mln_render_session_query_feature_extensions` with the cluster's GeoJSON;
  the result JSON is converted back to features. The release has no dedicated
  cluster calls (main adds them).
- **Source feature queries need a render session**
  (`-[MLNShapeSource featuresMatchingPredicate:]`,
  `-[MLNVectorTileSource featuresInSourceLayersWithIdentifiers:predicate:]`).
  They run on the map view's render session, as classic's ran on its
  renderer; without one they return an empty array, as before. Features come
  back as GeoJSON and are converted in Objective-C, so numeric property types
  follow JSON (integers and doubles) rather than mbgl's value types.
- **No tile URL, attribution or tile size setters** (all tile sources). The
  public API has none either, but `attributionHTMLString` is read from
  `mln_style_source_info`, which cannot tell an empty attribution from a
  missing one: a source with an inline tile set reports `@""` without one (as
  classic did), a source with a configuration URL reports nil until its
  TileJSON has loaded (`MLN_STYLE_SOURCE_INFO_TILE_JSON`).
- **Encodings are per source type.** Classic applied both
  `MLNTileSourceOptionDEMEncoding` and `MLNVectorTileSourceOptionEncoding` to
  any tile set, where the core ignored the irrelevant one. The style JSON has
  one `encoding` key, so only the option that matches the source type is sent.
- **Removed feature state disappears immediately**
  (`-removeFeatureState…`, `-resetFeatureStates…` followed by
  `-featureState…`). Classic's renderer applied removals when it next drew,
  so reading the state before then still returned the removed keys. The C
  API applies them at once.
- **Feature state is kept by the map, with string IDs**
  (`-setFeatureState…`, `-featureState…`, `-removeFeatureState…`,
  `-resetFeatureStates…`). Classic called the map view's `mbgl::Renderer`. The
  C API keeps feature state in the map (`mln_map_*_feature_state`); feature IDs
  are strings in this release, as classic's public API already passed them.
  Only sources on a map view support it, as before. State values must be JSON
  values; classic also accepted colors (converted to strings).
- **Adding a layer before its source**: see "Layers whose source is missing are
  refused" above.
- **Removing a source that a layer uses** fails in both; the C API reports
  `MLN_STATUS_INVALID_STATE` ("source is used by a layer"), mapped to
  `MLNErrorCodeSourceIsInUseCannotRemove` as before.
- **Degenerate image source quads are refused** (`MLNImageSource` with all
  four coordinates equal, such as `coordinateQuad:{}`). Classic accepted them
  (the image draws nothing); the C API refuses them ("image source coordinates
  must not all match"). They are sent with their corners a billionth of a
  degree apart and reported as given.
- **Image sources need an image or URL** (`MLNImageSource`). Classic created
  an image source with coordinates only and set the image later, and an empty
  `mln::PremultipliedImage` for `image = nil`. The C API has no image source
  without an image or URL and refuses empty images, so a missing or nil image
  is a single transparent pixel. Image source attribution is read from the
  source info (classic reported none).
- **No video source.** Neither the classic iOS API nor the C API has one; a
  video source in a loaded style appears as a plain `MLNSource`.
- **Computed shape sources** (`MLNComputedShapeSource`) use the C API's custom
  geometry source. Tiles are fetched on the data source's operation queue as
  before and sent as GeoJSON text with
  `mln_map_set_custom_geometry_source_tile_data`. `-setFeatures:inTileAtX:…`
  on a pending source does nothing (classic stored it in the unused pending
  core source), and the C API ignores tile data that it did not request.
- **Style image options.** `-[MLNStyle setImage:forName:]` sends premultiplied
  RGBA8 pixels with pixel ratio, SDF (template images), stretch areas and
  content box from the cap insets, as classic built `mln::style::Image`.
  `textFitWidth`/`textFitHeight` are not part of the iOS API and are not set.
  The C API has no call that lists style images.
- **Custom style layers do not draw** (`MLNCustomStyleLayer`). The C API has
  no custom layer (no `CustomLayerHost`, no Metal encoder access). The layer is
  represented in the style by an invisible placeholder (a background layer with
  visibility `none` and opacity 0), so it keeps its identifier, position and
  object identity; `visible` is tracked in Objective-C.
  `-didMoveToMapView:` / `-willMoveFromMapView:` are called when the layer is
  added to or removed from a map view's style; `-preDrawInMapView:…` and
  `-drawInMapView:…` are never called, and `commandBuffer`, `renderPassDesc`,
  `renderEncoder` and `context` stay nil.
- **Plugin layers cannot be registered** (`MLNPluginStyleLayer`,
  `MLNPluginLayer`). Classic registered Objective-C plugin layer classes with
  the core's plugin layer factory. The C API's plugin interface
  (`plugin.h`, `mln/plugin/plugin_api.h`) is a C ABI with host-owned drawables
  and MSL shaders, not compatible with `MLNPluginLayer`'s callbacks, so
  `-pluginLayer` returns nil unless the map view associates one.

## Shapes, features, predicates and expressions

- **`+[MLNShape shapeWithData:encoding:error:]` JSON syntax errors.** Classic
  parsed with rapidjson and reported `"<offset> - <rapidjson message>"` in
  `NSLocalizedFailureReasonErrorKey`. The C API has no GeoJSON parser, so this
  package parses with `NSJSONSerialization` and reports its message instead.
  GeoJSON structure errors ("Feature must have a geometry property", …) are
  ported from `mapbox::geojson` and match. NSJSONSerialization also differs
  from rapidjson on edge cases such as duplicate keys and very large numbers.
- **Non-numeric coordinates.** `mapbox::geojson` called rapidjson's
  `GetDouble()` on coordinate members without checking their type (an
  assertion in rapidjson). This package fails with "coordinates must be
  numbers". *Unverified* what classic release builds did.
- **Empty polygon rings.** Classic took `front()` of a polygon with no rings
  (undefined behavior). This package initializes the polygon without
  coordinates, which raises `NSInvalidArgumentException` ("A multipoint must
  have at least one vertex.").
- **`-[MLNShape geoJSONDataUsingEncoding:]` output bytes.** Classic wrote
  `mapbox::geojson::stringify()` (rapidjson: `1.0` for doubles, member order
  type/geometry/properties/id). This package writes `NSJSONSerialization` output
  of the same GeoJSON object (`1` for integral doubles, dictionary order). The
  JSON is equivalent; the bytes are not.
- **Feature equality (`-[MLNFeature isEqual:]`).** Classic compared
  `mln::GeoJSON` values, whose variants distinguish `true` from `1` and
  `1` (uint64) from `1.0` (double). This package compares the Foundation
  GeoJSON objects, and `NSNumber` equality does not make those distinctions
  (`@YES` equals `@1`, `@1` equals `@1.0`).
- **Colors as feature attributes or identifiers.** `mln::Color::stringify()`
  formatted components with rapidjson's Grisu2 double writer. This package
  writes the shortest `%g` representation that reads back as the same double,
  which is the same for all values in a color's range unless Grisu2 is
  suboptimal (rare). *Unverified* on real values.
- **Filter validation (`mgl_filter`).** Classic converted predicates to
  `mln::style::Filter` and raised "Invalid filter value: <core message>". The
  C API validates expressions with `mln_style_expression_create()` (expected
  type boolean), whose diagnostic lists each parse error with its location; the
  text after "Invalid filter value: " differs from classic's. Predicates
  always produce expression syntax, so legacy filter forms, which the core
  converted separately, do not arise.
- **Removed private conversions.** `-[NSExpression mgl_featureType]`,
  `mgl_aggregateFeatureType`, `mgl_aggregateFeatureIdentifier`,
  `-[NSComparisonPredicate mgl_constantValue/mgl_featureType/mgl_featureIdentifier]`
  and `-[NSCompoundPredicate mgl_subfilters]` built core filter types and had
  no callers left; they were dropped. No public API depended on them.
- **Offline region definitions.** Classic built `mln::OfflineRegionDefinition`
  with the geometry as `mln::Geometry<double>`. The C API takes the geometry of a
  shape region as GeoJSON text, which this package writes from the shape's
  geometry object; a region read back from the database is parsed from that
  text. Shapes survive the round trip as their geometry (feature identifiers
  and attributes are dropped, as in classic).

## Offline storage, network, settings and snapshots

### Offline storage

- **Cache database path before the runtime exists**
  (`MLNOfflineStorage.databasePath`, `MLNOfflineStorageDatabasePath`).
  Classic created its database file source when the shared storage was first
  used; maps shared it. The C API opens the database once, when a runtime is
  created (`mln_runtime_options.cache_path`), and every map and snapshotter
  shares the one runtime. MLNOfflineStorage registers a default cache path
  provider in `+load` (`+[MLNFFIRuntime setDefaultCachePathProvider:]`), so
  whichever object creates the runtime first opens the classic database
  location. The path is computed once per process instead of per storage
  instance.
- **Pausing the file sources in the background**
  (`UIApplicationDidEnterBackgroundNotification` handling). Classic paused the
  online and database file sources and resumed them in the foreground. The C
  API cannot pause a runtime's file sources. The notifications still toggle
  the storage's internal paused flag; requests keep running.
- **Tile count limit** (`-setMaximumAllowedMapboxTiles:`). Classic set the
  database's Mapbox tile count limit. The C API has no setter (it reports the
  limit's event only). Logs a warning once and does nothing.
- **Preloading resources into the cache** (`-preloadData:forURL:…`,
  `-putResourceWithUrl:…`). Classic forwarded a response into the database
  file source. The C API cannot put a resource into the cache. Logs a warning
  once; the completion handler, if any, receives an
  `MLNErrorCodeModifyingOfflineStorageFailed` error instead of success.
- **API key and tile server options for downloads**. Classic synchronized the
  online file source's API key and `TileServerOptions` with `MLNSettings`
  (key-value observing). The C API's runtime always uses the core's default
  resource options (the MapLibre demo tile server configuration) and takes no
  API key. Not applied; see Settings below.
- **Offline region observers**. Classic set an `OfflineRegionObserver` per
  pack and removed it when the pack was invalidated. The C API reports events
  per runtime for observed regions (`mln_runtime_set_offline_region_observed`).
  Each pack turns observation on; invalidating a pack leaves it on (several
  pack objects can stand for one region), and MLNOfflineStorage routes events
  only to the packs in `packs`.
- **Downloading `file:` resources** (`MLNOfflinePack` of a region whose style
  or tiles have `file:` URLs). Classic's offline download fetched every
  resource through the online file source, whose NSURLSession also read
  `file:` URLs. The C API's network loader refuses them ("native loader cannot
  request this resource"), so such a pack stopped after the style. The shared
  runtime registers a resource provider (`mln_runtime_set_resource_provider`)
  for `file://**` that reads the file with NSURLSession, as classic did, so
  errors have its wording. Map loads never reach it, since they
  read `file:` URLs before the network. MapLibre iOS's API has no way for an
  app to register a provider of its own, so nothing can replace this one.
- **Response error details** (`MLNOfflinePackErrorNotification`). Classic's
  error carried the core's `Response::Error` message. The C API's event
  carries the reason and, in the event message, the text. The
  `NSLocalizedFailureReasonErrorKey` holds that message.
- **Region geometry is reported as stored** (`MLNOfflinePack.region` of a
  pack read from the database). The C API returns a region's geometry as the
  database holds it, which can differ from the given geometry in the last bit
  of a coordinate. A pack created by `-addPackForRegion:…` keeps the region it
  was given, as classic's did.
- **Metadata updates** (`-[MLNOfflinePack setContext:completionHandler:]`).
  Classic reloaded all packs to read the updated region back; the C API
  returns the updated region, which the pack takes directly.
- **Region definitions** are converted to and from the C API's
  `mln_offline_region_definition` by the region classes
  (`MLNOfflineRegion_Private.h`) instead of mbgl definition objects; the
  storage copies the C API's region records (`ffi/MLNFFIOfflineRegions.mm`).
- **Error descriptions** of failed storage operations are the C API's
  diagnostics, not the core's exception texts.

### Network

- **NSURLSession configuration and network delegate**
  (`MLNNetworkConfiguration.sessionConfiguration`, `.delegate`:
  `sessionForNetworkConfiguration:`, `willSendRequest:`, `didReceiveResponse:`,
  download metrics). Classic implemented the core's `MLNNativeNetworkDelegate`
  against the exported `MLNNativeNetworkManager`. The C API has no hook for its
  HTTP session. Its Apple build does compile the same Objective-C bridge
  (`MLNNativeNetworkManager`, `MLNInternalNetworkResponse`), and its HTTP file
  source consults it, but the classes are not exported symbols. This
  implementation looks them up with `NSClassFromString` and installs
  MLNNetworkConfiguration as the manager's delegate, so the classic behavior
  holds — relying on an undocumented internal of the C API build. If a future
  build drops those classes, only the session configuration's additional HTTP
  headers apply, through `mln_runtime_set_http_header_transform`, which cannot
  set `User-Agent` or other headers the C API manages. This SDK must not define
  classes named `MLNNativeNetworkManager`, `MLNInternalNetworkResponse`,
  `MBGLBundleCanary`, `MLNHTTPRedirectDelegate` or `MLNFFIFramePacerTarget`,
  which the C API framework registers.
- **Resource URL transform** (`MLNOfflineStorageDelegate
  offlineStorage:URLForResourceOfKind:withURL:`). Classic called the delegate
  on the main thread through a core actor. Implemented with
  `mln_runtime_set_resource_transform`; the callback hops to the main queue to
  ask the delegate and answers the request from there. Differences: the C API
  applies the transform only to network loads (not file, asset, database or
  MBTiles requests), and a nil URL from the delegate keeps the original URL
  (classic would crash).

### Settings

- **Tile server options and API key** (`MLNSettings.apiKey`,
  `+useWellKnownTileServer:`, `+tileServerOptions`, `MLNTileServerBaseURL`,
  `MLNApiKey`). Classic passed `TileServerOptions` and the API key to every
  file source, which resolved `mapbox://`, `maptiler://` and `maplibre://`
  URLs and appended API keys. The C API's runtime always uses the core's
  default configuration (MapLibre demo tiles, `maplibre://`) and takes no API
  key or tile server options. The values are kept in Objective-C (the core's
  presets are reproduced) and reported back, but not applied: `maplibre://`
  URLs resolve; `mapbox://` and `maptiler://` URLs and API keys do not. A
  resource transform cannot emulate this, because the C API refuses those URL
  schemes before transforming.
- `+tileServerOptions` reports the sprites, glyphs and tile version prefixes
  only when the style has one, as classic did.

### Snapshotter

- **Snapshot annotations** (`-addAnnotation:`, `-addAnnotations:`, the
  delegate's annotation image and shape styling methods). Classic added them to
  the core's annotation manager. The C API has none. They are drawn with style
  layers configured as the annotation manager configured its own (a round-joined
  line or a fill layer per shape with the delegate's color, width and alpha,
  and one symbol layer with `icon-allow-overlap` and `icon-ignore-placement`
  for the points, above the shapes), with identifiers under
  `org.maplibre.next.snapshot.annotations.`, which MLNStyle hides. They are
  added once the style has loaded, after
  `mapSnapshotter:didFinishLoadingStyle:`.
- **Rendering** uses a static map and a graphics-device texture session per
  start (`mln_graphics_device_create`, `mln_map_attach_graphics_device_texture`,
  `mln_map_request_still_image`, `mln_render_session_read_texture`), as classic
  created an `mbgl::MapSnapshotter` per start. The snapshot waits for the style
  to load (or fail) before requesting the image; a failed style load completes
  the snapshot with an `MLNErrorCodeSnapshotFailed` error carrying the load
  error's message.
- **Point/coordinate conversion** (`MLNMapSnapshot`, `MLNMapSnapshotOverlay`)
  uses a C API projection of the still image's frame view. Classic wrapped the
  coordinate and unwrapped it for the shortest path to the camera center; the
  C API converts in the world copy nearest the center, which is the same for
  coordinates within 180° of it.
- **Local ideographic font family** and **tile server options** are not
  passed (see Rendering and Settings).
- **Missing images**: the C API reports the missing image's identifier as the
  event message (`mapSnapshotter:didFailLoadingImageNamed:` gets it from
  there).

### Rendering statistics and action journal

- **Rendering statistics** (`MLNRenderingStats`, `MLNMapOptions`). Classic
  copied every field of `mbgl::gfx::RenderingStats` (textures, buffers, memory,
  stencil counts) and the rendered feature information. The C API's render
  frame event reports encoding and rendering time, frame count and draw call
  counts (`mln_rendering_stats`) only. Those are set
  (`-[MLNRenderingStats mgl_setFFIStats:]`); all other properties stay zero and
  `frameRenderedFeatures` stays nil. `MLNOverscaledTileID`, `MLNSourceLayerID`
  and `MLNFeatureInfo` are never created.
- **Action journal** (`MLNActionJournalOptions`, the map view's action journal
  API). The C API has no action journal. The options keep their values and
  classic defaults (enabled NO, 1 MiB files, 5 files, 60 s report interval)
  and are not applied.

### Renderer configuration

- **Ideographic font family** (`MLNIdeographicFontFamilyName` Info.plist key)
  and **pre-4.0 collision behavior** (`MLNCollisionBehaviorPre4_0`).
  `MLNRendererConfiguration` still reads both, but the C API creates its
  renderers without a local font family (CJK glyphs always come from the
  style's glyph server) and without per-source collision options, so neither
  takes effect.

### Resources

- **Framework bundle** (`+[NSBundle mgl_frameworkBundle]`). Built as a Swift
  package, the resources live in SwiftPM's resource bundle
  (`SWIFTPM_MODULE_BUNDLE`), whose Info.plist has no framework version, so
  `mgl_frameworkInfoDictionary[@"CFBundleShortVersionString"]` is nil.
