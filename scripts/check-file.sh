#!/usr/bin/env bash
# Type-checks source files of the MapLibre target for the iOS Simulator
# without building the package, so a file can be checked before the rest of
# the target compiles.
#
#   scripts/check-file.sh Sources/MapLibre/darwin/MLNStyle.mm ...
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/Sources/MapLibre"
ffi="$(find "$root/.build/artifacts" -path '*MaplibreNativeC.xcframework/ios-arm64-simulator' -maxdepth 6 | head -n 1)"
if [[ -z "$ffi" ]]; then
  (cd "$root" && swift package resolve >/dev/null)
  ffi="$(find "$root/.build/artifacts" -path '*MaplibreNativeC.xcframework/ios-arm64-simulator' -maxdepth 6 | head -n 1)"
fi
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"

status=0
for file in "$@"; do
  case "$file" in
    *.mm) lang=(-x objective-c++ -std=c++20) ;;
    *.m) lang=(-x objective-c) ;;
    *) continue ;;
  esac
  if ! xcrun clang -fsyntax-only -fobjc-arc -fmodules -fcxx-modules "${lang[@]}" \
      -target arm64-apple-ios15.5-simulator -isysroot "$sdk" \
      -F "$ffi" ${MLN_CHECK_EXTRA_INCLUDE:+-I "$MLN_CHECK_EXTRA_INCLUDE"} \
      -I "$src/include/MapLibre" -I "$src/darwin" -I "$src/ios" -I "$src/ffi" -I "$src/style" \
      -I "$src/style/generated" -I "$src/vendor/SMCalloutView" -I "$src/vendor/polylabel" \
      -DMLN_NEXT=1 -DMLN_RENDER_BACKEND_METAL=1 -Wno-nullability-completeness -ferror-limit=50 "$file"; then
    status=1
  fi
done
exit $status
