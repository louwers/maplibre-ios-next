// swift-tools-version: 6.2

// MapLibre iOS, with the public API of MapLibre iOS 7.0.0, implemented on the
// MapLibre Native FFI C API instead of the C++ core. See README.md.

import PackageDescription

let package = Package(
  name: "MapLibreNext",
  defaultLocalization: "en",
  platforms: [.iOS("15.5")],
  products: [
    .library(name: "MapLibre", targets: ["MapLibre"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/maplibre/maplibre-native-ffi-distribution",
      exact: "0.202610.3"
    ),
  ],
  targets: [
    .target(
      name: "MapLibre",
      dependencies: [
        .product(name: "MaplibreNativeC", package: "maplibre-native-ffi-distribution"),
      ],
      path: "Sources/MapLibre",
      resources: [
        .process("Resources/Images.xcassets"),
        .process("Resources/Localizations"),
        .copy("Resources/PrivacyInfo.xcprivacy"),
      ],
      publicHeadersPath: "include",
      cSettings: [
        .headerSearchPath("include/MapLibre"),
        .headerSearchPath("darwin"),
        .headerSearchPath("ios"),
        .headerSearchPath("ffi"),
        .headerSearchPath("style"),
        .headerSearchPath("style/generated"),
        .headerSearchPath("vendor/SMCalloutView"),
        .headerSearchPath("vendor/polylabel"),
        .define("MLN_NEXT", to: "1"),
        .define("MLN_NEXT_API_VERSION", to: "\"7.0.0\""),
        .define("MLN_RENDER_BACKEND_METAL", to: "1"),
      ],
      cxxSettings: [
        .headerSearchPath("include/MapLibre"),
        .headerSearchPath("darwin"),
        .headerSearchPath("ios"),
        .headerSearchPath("ffi"),
        .headerSearchPath("style"),
        .headerSearchPath("style/generated"),
        .headerSearchPath("vendor/SMCalloutView"),
        .headerSearchPath("vendor/polylabel"),
        .define("MLN_NEXT", to: "1"),
        .define("MLN_NEXT_API_VERSION", to: "\"7.0.0\""),
        .define("MLN_RENDER_BACKEND_METAL", to: "1"),
      ],
      linkerSettings: [
        .linkedFramework("CoreLocation"),
        .linkedFramework("CoreText"),
        .linkedFramework("ImageIO"),
        .linkedFramework("Metal"),
        .linkedFramework("QuartzCore"),
        .linkedFramework("SystemConfiguration"),
        .linkedFramework("UIKit"),
      ]
    ),
  ],
  cxxLanguageStandard: .cxx20
)
