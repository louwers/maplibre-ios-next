# Shared paths for the API scripts. Source this file.
parity="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(cd "$parity/.." && pwd)"
out_root="$parity/out"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
target="arm64-apple-ios15.5-simulator"
classic_slice="$repo/.upstream/classic/MapLibre.xcframework/ios-arm64_x86_64-simulator"
classic_headers="$classic_slice/MapLibre.framework/Headers"
next_headers="$repo/Sources/MapLibre/include/MapLibre"

# Lays out the headers of an implementation as MapLibre.framework (headers and
# module map only), so both are compiled exactly as an app would import them.
# Prints the directory to pass with -F. With "flat", the module map has no
# per-header submodules, so swift-api-digester attributes every declaration to
# the MapLibre module itself.
api_framework_dir() {
  local impl="$1" flavor="${2:-}" dir="$out_root/$1/api/frameworks${2:+-$2}"
  local headers="$next_headers"
  [[ "$impl" == classic ]] && headers="$classic_headers"
  rm -rf "$dir"
  mkdir -p "$dir/MapLibre.framework/Headers" "$dir/MapLibre.framework/Modules"
  cp "$headers"/*.h "$dir/MapLibre.framework/Headers/"
  if [[ "$flavor" == flat ]]; then
    printf 'framework module MapLibre {\n  umbrella header "MapLibre.h"\n  export *\n}\n' \
      > "$dir/MapLibre.framework/Modules/module.modulemap"
  else
    # The module map classic ships.
    cp "$classic_slice/MapLibre.framework/Modules/module.modulemap" "$dir/MapLibre.framework/Modules/"
  fi
  echo "$dir"
}
