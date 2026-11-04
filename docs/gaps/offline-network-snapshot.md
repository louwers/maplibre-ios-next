# C API gaps: offline storage, network, settings, snapshots

Shortfalls of the MapLibre Native C API (maplibre-native-ffi 0.202610.3)
against what classic MapLibre iOS 7.0.0 did through the C++ core, for the
offline storage, network configuration, settings, snapshotter, rendering
statistics and related classes. Each entry: affected public API — classic
behavior — C API status — what maplibre-ios-next does.

## Offline storage

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
- **Response error details** (`MLNOfflinePackErrorNotification`). Classic's
  error carried the core's `Response::Error` message. The C API's event
  carries the reason and, in the event message, the text. The
  `NSLocalizedFailureReasonErrorKey` holds that message.
- **Metadata updates** (`-[MLNOfflinePack setContext:completionHandler:]`).
  Classic reloaded all packs to read the updated region back; the C API
  returns the updated region, which the pack takes directly.
- **Region definitions** are converted to and from the C API's
  `mln_offline_region_definition` by the region classes
  (`MLNOfflineRegion_Private.h`) instead of mbgl definition objects; the
  storage copies the C API's region records (`ffi/MLNFFIOfflineRegions.mm`).
- **Error descriptions** of failed storage operations are the C API's
  diagnostics, not the core's exception texts.

## Network

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

## Settings

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

## Snapshotter

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

## Rendering statistics and action journal

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

## Renderer configuration

- **Ideographic font family** (`MLNIdeographicFontFamilyName` Info.plist key)
  and **pre-4.0 collision behavior** (`MLNCollisionBehaviorPre4_0`).
  `MLNRendererConfiguration` still reads both, but the C API creates its
  renderers without a local font family (CJK glyphs always come from the
  style's glyph server) and without per-source collision options, so neither
  takes effect.

## Resources

- **Framework bundle** (`+[NSBundle mgl_frameworkBundle]`). Built as a Swift
  package, the resources live in SwiftPM's resource bundle
  (`SWIFTPM_MODULE_BUNDLE`), whose Info.plist has no framework version, so
  `mgl_frameworkInfoDictionary[@"CFBundleShortVersionString"]` is nil.
