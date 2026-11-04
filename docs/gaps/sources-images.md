# Sources, style images and custom layers

Shortfalls of the MapLibre Native FFI C API (0.202610.3) for `MLNSource` and
its subclasses, style images, `MLNCustomStyleLayer` and `MLNPluginStyleLayer`,
and what maplibre-ios-next does instead.

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
- **Feature state is kept by the map, with string IDs**
  (`-setFeatureState…`, `-featureState…`, `-removeFeatureState…`,
  `-resetFeatureStates…`). Classic called the map view's `mbgl::Renderer`. The
  C API keeps feature state in the map (`mln_map_*_feature_state`); feature IDs
  are strings in this release, as classic's public API already passed them.
  Only sources on a map view support it, as before. State values must be JSON
  values; classic also accepted colors (converted to strings).
- **Adding a layer before its source.** Classic's core accepted a layer whose
  source was not in the style ("TODO: verify source"); the C API refuses it
  (`MLN_STATUS_NOT_FOUND`). The style defers such layers and adds them when the
  source is added (`-[MLNStyle mgl_deferLayer:…]`), so they are missing from
  `MLNStyle.layers` until then.
- **Removing a source that a layer uses** fails in both; the C API reports
  `MLN_STATUS_INVALID_STATE` ("source is used by a layer"), mapped to
  `MLNErrorCodeSourceIsInUseCannotRemove` as before.
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
