#!/usr/bin/env bash
# Downloads the upstream MapLibre iOS sources and the classic XCFramework into
# .upstream/ (git-ignored). Everything else in the repository reads from there.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/scripts/upstream.env"
out="$root/.upstream"

if [[ ! -f "$out/.tag" || "$(cat "$out/.tag")" != "$UPSTREAM_TAG" ]]; then
  rm -rf "$out"
  mkdir -p "$out"
  curl -fsSL "https://codeload.github.com/$UPSTREAM_REPO/tar.gz/refs/tags/$UPSTREAM_TAG" \
    | tar -xz -C "$out" --strip-components=1 \
      "maplibre-native-$UPSTREAM_TAG/LICENSE.md" \
      "maplibre-native-$UPSTREAM_TAG/include" \
      "maplibre-native-$UPSTREAM_TAG/metrics/integration" \
      "maplibre-native-$UPSTREAM_TAG/platform/darwin" \
      "maplibre-native-$UPSTREAM_TAG/platform/ios" \
      "maplibre-native-$UPSTREAM_TAG/scripts"
  echo "$UPSTREAM_TAG" > "$out/.tag"
fi

classic="$out/classic"
if [[ ! -d "$classic/MapLibre.xcframework" ]]; then
  mkdir -p "$classic"
  curl -fsSL "$CLASSIC_XCFRAMEWORK_URL" -o "$classic/MapLibre.dynamic.xcframework.zip"
  echo "$CLASSIC_XCFRAMEWORK_SHA256  $classic/MapLibre.dynamic.xcframework.zip" | shasum -a 256 -c -
  unzip -q -o "$classic/MapLibre.dynamic.xcframework.zip" -d "$classic"
fi
