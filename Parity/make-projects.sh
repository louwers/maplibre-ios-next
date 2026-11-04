#!/usr/bin/env bash
# Generates Parity/build/<impl>/Parity.xcodeproj for classic MapLibre iOS
# (maplibre-gl-native-distribution 7.0.0) and for maplibre-ios-next (this
# repository), from project.yml.in. Both projects compile the same tests.
#
#   Parity/make-projects.sh [classic|next|both]
set -euo pipefail

parity="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$parity/.." && pwd)"
impls="${1:-both}"
[[ "$impls" == both ]] && impls="classic next"

# Resources of the upstream tests, which are too big to keep in this
# repository. They come from the upstream release the package mirrors.
"$repo/scripts/fetch-upstream.sh"
source "$repo/scripts/upstream.env"
resources="$parity/build/upstream-resources"
mkdir -p "$resources"
for fixture in test/fixtures/local_glyphs/mixed.json test/fixtures/offline_database/sideload_sat.db \
  test/fixtures/resources/glyphs.pbf; do
  file="$resources/$(basename "$fixture")"
  if [[ ! -f "$file" ]]; then
    if [[ -f "$repo/.upstream/$fixture" ]]; then
      cp "$repo/.upstream/$fixture" "$file"
    else
      curl -fsSL "https://raw.githubusercontent.com/$UPSTREAM_REPO/$UPSTREAM_TAG/$fixture" -o "$file"
    fi
  fi
done
rm -rf "$resources/Media.xcassets"
cp -R "$repo/.upstream/platform/darwin/test/Media.xcassets" "$resources/"

for impl in $impls; do
  dir="$parity/build/$impl"
  mkdir -p "$dir"
  case "$impl" in
    classic)
      package='  MapLibre:
    url: https://github.com/maplibre/maplibre-gl-native-distribution
    exactVersion: 7.0.0'
      ;;
    next)
      # The repository root, relative to the project directory.
      package='  MapLibre:
    path: ../../..'
      ;;
    *)
      echo "unknown implementation: $impl" >&2
      exit 1
      ;;
  esac
  python3 -I - "$parity/project.yml.in" "$dir/project.yml" "$impl" "$package" <<'PY'
import sys
template, out, impl, package = sys.argv[1:5]
text = open(template).read()
text = text.replace("@MAPLIBRE_PACKAGE@", package).replace("@IMPL@", impl).replace("@IMPL_MACRO@", impl.upper())
open(out, "w").write(text)
PY
  rm -rf "$dir/UpstreamResources"
  cp -R "$resources" "$dir/UpstreamResources"
  (cd "$dir" && xcodegen generate --quiet --spec project.yml)
  echo "generated $dir/Parity.xcodeproj"
done
