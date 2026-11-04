#!/usr/bin/env bash
# Compares maplibre-ios-next with classic MapLibre iOS.
#
#   Parity/run.sh [api|behaviour|render|all] [--impl classic|next|both]
#
#   api        public headers, Objective-C symbols and the Swift interface of
#              both implementations (no build needed)
#   behaviour  the API coverage test, MapLibre iOS's own tests and the trace
#              tests, on the iOS Simulator, once per implementation
#   render     render-test styles through MLNMapSnapshotter and MLNMapView
#   all        all of the above (the default)
#
# Results go to Parity/out/<impl>/; the report to Parity/out/report.md and
# Parity/out/report.html.
#
# Environment:
#   PARITY_SIMULATOR     name of the simulator to use, created if missing
#                        (default "MapLibre Parity", an iPhone 17 on the newest iOS)
#   --stability          run the behaviour tests against classic twice; trace
#                        values that differ between the two runs are reported
#                        as timing-dependent instead of as differences
#
#   PARITY_RENDER_LIST   render tests to run: a file of ids, or "all"
#                        (default Parity/render/curated.txt)
set -uo pipefail

parity="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$parity/.." && pwd)"
out="$parity/out"

parts="all"
impls="classic next"
stability=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    api | behaviour | render | all) parts="$1" ;;
    --stability) stability=1 ;;
    --impl)
      shift
      [[ "${1:-}" == both ]] && impls="classic next" || impls="${1:?--impl needs a value}"
      ;;
    *)
      echo "usage: $0 [api|behaviour|render|all] [--impl classic|next|both] [--stability]" >&2
      exit 2
      ;;
  esac
  shift
done
[[ "$parts" == all ]] && parts="api behaviour render"

"$repo/scripts/fetch-upstream.sh"
mkdir -p "$out"

# A simulator of our own, so other simulator users do not interfere.
simulator="${PARITY_SIMULATOR:-MapLibre Parity}"
device_type="${PARITY_SIMULATOR_DEVICE_TYPE:-iPhone 17}"
udid="$(xcrun simctl list devices available -j | python3 -I -c '
import json, sys
name = sys.argv[1]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for device in devices:
        if device["name"] == name:
            print(device["udid"])
            sys.exit()
' "$simulator")"
if [[ -z "$udid" ]]; then
  runtime="${PARITY_SIMULATOR_RUNTIME:-$(xcrun simctl list runtimes available -j | python3 -I -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS"]
print(sorted(runtimes, key=lambda r: [int(p) for p in r["version"].split(".")])[-1]["identifier"])
')}"
  udid="$(xcrun simctl create "$simulator" "$device_type" "$runtime")"
fi
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
destination="id=$udid"

# Writes out/<impl>/status.json, which the report reads.
status() {
  local impl="$1" part="$2" state="$3" message="$4"
  python3 -I - "$out/$impl/status.json" "$part" "$state" "$message" <<'PY'
import json, os, sys
path, part, state, message = sys.argv[1:5]
data = json.load(open(path)) if os.path.exists(path) else {}
data[part] = {"state": state, "message": message}
json.dump(data, open(path, "w"), indent=2, sort_keys=True)
PY
}

# Builds the test bundle of one implementation; returns non-zero if it does not build.
build() {
  local impl="$1"
  if [[ -f "$out/$impl/.built" ]]; then
    return 0
  fi
  "$parity/make-projects.sh" "$impl" >/dev/null || return 1
  echo "building $impl..."
  if ! xcodebuild build-for-testing -project "$parity/build/$impl/Parity.xcodeproj" -scheme Parity \
      -destination "$destination" -derivedDataPath "$parity/build/$impl/DerivedData" \
      >"$out/$impl/build.log" 2>&1; then
    local reason="the test bundle does not build"
    if [[ "$impl" == next ]]; then
      reason="the maplibre-ios-next package does not build yet"
    fi
    grep -E " error:" "$out/$impl/build.log" | sort -u | head -n 20 >"$out/$impl/build-errors.txt" || true
    # Leave no results of an earlier build for the report to pick up.
    rm -rf "$out/$impl/traces" "$out/$impl/coverage.json" "$out/$impl/render" "$out/$impl"/*-tests.json
    status "$impl" build failed "$reason (see out/$impl/build.log)"
    echo "$impl: $reason; see $out/$impl/build.log" >&2
    return 1
  fi
  status "$impl" build ok ""
  touch "$out/$impl/.built"
}

# Runs tests of the built bundle: test <impl> <part> <xcodebuild selection args...>
run_tests() {
  local impl="$1" part="$2"
  shift 2
  local bundle="$out/$impl/$part.xcresult"
  rm -rf "$bundle"
  echo "running $part tests against $impl..."
  TEST_RUNNER_PARITY_OUT="$out/$impl" \
  TEST_RUNNER_PARITY_UPSTREAM="$repo/.upstream" \
  TEST_RUNNER_PARITY_RENDER_TESTS="$repo/.upstream/metrics/integration" \
  TEST_RUNNER_PARITY_RENDER_LIST="${PARITY_RENDER_LIST:-$parity/render/curated.txt}" \
  TEST_RUNNER_PARITY_RENDER_ONSCREEN_LIST="$parity/render/onscreen.txt" \
    xcodebuild test-without-building -project "$parity/build/$impl/Parity.xcodeproj" -scheme Parity \
      -destination "$destination" -derivedDataPath "$parity/build/$impl/DerivedData" \
      -resultBundlePath "$bundle" -test-timeouts-enabled YES \
      -default-test-execution-time-allowance "${PARITY_TEST_TIME_ALLOWANCE:-120}" \
      "$@" >"$out/$impl/$part.log" 2>&1
  local code=$?
  xcrun xcresulttool get test-results tests --path "$bundle" --format json >"$out/$impl/$part-tests.json" 2>/dev/null ||
    echo '{}' >"$out/$impl/$part-tests.json"
  if [[ $code -eq 0 ]]; then
    status "$impl" "$part" ok ""
  else
    status "$impl" "$part" finished-with-failures "xcodebuild exited with $code (see out/$impl/$part.log)"
  fi
}

for part in $parts; do
  case "$part" in
    api)
      "$parity/api/check-api.sh"
      ;;
    behaviour | render)
      for impl in $impls; do
        mkdir -p "$out/$impl"
        rm -f "$out/$impl/.built"
      done
      ;;
  esac
done

for part in $parts; do
  [[ "$part" == api ]] && continue
  for impl in $impls; do
    mkdir -p "$out/$impl"
    if ! build "$impl"; then
      status "$impl" "$part" not-run "not built"
      continue
    fi
    if [[ "$part" == behaviour ]]; then
      if [[ "$impl" == classic && "$stability" == 1 ]]; then
        rm -rf "$out/$impl/traces" "$out/classic-rerun"
        run_tests "$impl" behaviour -skip-testing:ParityTests/MLNRenderParityTests
        mkdir -p "$out/classic-rerun"
        mv "$out/$impl/traces" "$out/classic-rerun/traces"
      fi
      rm -rf "$out/$impl/traces" "$out/$impl/coverage.json"
      run_tests "$impl" behaviour -skip-testing:ParityTests/MLNRenderParityTests
    else
      rm -rf "$out/$impl/render"
      run_tests "$impl" render -only-testing:ParityTests/MLNRenderParityTests
    fi
  done
done

python3 -I "$parity/compare.py" --out "$out" --parity "$parity"
