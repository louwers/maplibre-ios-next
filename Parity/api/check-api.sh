#!/usr/bin/env bash
# Compares the public API of classic MapLibre iOS and maplibre-ios-next:
#   1. the header trees, byte for byte;
#   2. Objective-C symbol graphs from `clang -extract-api`, symbol by symbol;
#   3. the Swift view of each module from `swift-api-digester -dump-sdk`.
# Writes out/<impl>/api/* and out/api-diff.json.
set -euo pipefail
source "$(dirname "$0")/common.sh"
"$repo/scripts/fetch-upstream.sh"

for impl in classic next; do
  mkdir -p "$out_root/$impl/api"
  fw="$(api_framework_dir "$impl")"
  headers="$fw/MapLibre.framework/Headers"
  # Every public header, as the umbrella header lists them.
  xcrun clang -extract-api --product-name=MapLibre -x objective-c-header \
    -target "$target" -isysroot "$sdk" -F "$fw" \
    -Wno-everything "$headers"/*.h -o "$out_root/$impl/api/symbols.json"
  # The full AST of the headers, for the coverage test. extract-api leaves out
  # categories on classes outside the product (NSValue, NSExpression, ...).
  # With -fmodules and the headers on the include path, only MapLibre's
  # declarations are dumped; system frameworks stay modules.
  xcrun clang -fsyntax-only -fmodules -x objective-c -target "$target" -isysroot "$sdk" -I "$headers" \
    -Wno-everything -Xclang -ast-dump=json - <<<'#import "MapLibre.h"' > "$out_root/$impl/api/ast.json"
  flat="$(api_framework_dir "$impl" flat)"
  xcrun swift-api-digester -dump-sdk -module MapLibre -target "$target" -sdk "$sdk" -F "$flat" \
    -o "$out_root/$impl/api/swift-sdk.json" -avoid-location 2>"$out_root/$impl/api/swift-sdk.log" || {
    echo "swift-api-digester failed for $impl; see $out_root/$impl/api/swift-sdk.log" >&2
  }
done

python3 -I "$parity/api/gen_coverage.py" --ast "$out_root/classic/api/ast.json" \
  --headers "$out_root/classic/api/frameworks/MapLibre.framework/Headers" \
  --known-gaps "$parity/api/coverage-known-classic-gaps.json" \
  --out "$parity/Tests/Coverage/MLNAPICoverageTests.m"

xcrun swift-api-digester -diagnose-sdk -input-paths "$out_root/classic/api/swift-sdk.json" \
  -input-paths "$out_root/next/api/swift-sdk.json" -o "$out_root/api-swift-diagnose.txt" \
  2>/dev/null || true

python3 -I "$parity/api/api_diff.py" \
  --classic-headers "$classic_headers" --next-headers "$next_headers" \
  --classic-symbols "$out_root/classic/api/symbols.json" --next-symbols "$out_root/next/api/symbols.json" \
  --classic-swift "$out_root/classic/api/swift-sdk.json" --next-swift "$out_root/next/api/swift-sdk.json" \
  --swift-diagnose "$out_root/api-swift-diagnose.txt" \
  --out "$out_root/api-diff.json"
