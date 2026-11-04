# maplibre-ios-next

MapLibre iOS with the public API of [MapLibre iOS](https://github.com/maplibre/maplibre-native/tree/main/platform/ios)
7.0.0, implemented on the C API of
[MapLibre Native FFI](https://github.com/maplibre/maplibre-native-ffi)
([0.202610.3](https://swiftpackageindex.com/maplibre/maplibre-native-ffi-distribution))
instead of on the C++ core.

Work in progress. See [C_API_GAPS.md](C_API_GAPS.md) for where the C API falls
short of an identical API, and [Parity/](Parity/) for the harness that compares
this package with classic MapLibre iOS.
