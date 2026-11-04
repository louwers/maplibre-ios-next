#!/usr/bin/env bash
# Shows how files copied from upstream differ from their originals. Every
# changed file names its original in its first line ("Based on platform/...");
# files without that line must be identical.
#
#   scripts/diff-upstream.sh            summary of all copied files
#   scripts/diff-upstream.sh FILE...    unified diffs for these files
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
"$root/scripts/fetch-upstream.sh"
upstream="$root/.upstream"

original_of() {
  local file="$1" based
  based="$(head -n 1 "$file" | sed -n 's|^// Based on \(platform/[^ ]*\) at .*|\1|p')"
  if [[ -n "$based" ]]; then
    echo "$upstream/$based"
    return
  fi
  local name
  name="$(basename "$file")"
  for dir in platform/darwin/src platform/ios/src platform/ios/vendor/SMCalloutView; do
    if [[ -f "$upstream/$dir/$name" ]]; then
      echo "$upstream/$dir/$name"
      return
    fi
  done
}

if [[ $# -gt 0 ]]; then
  for file in "$@"; do
    original="$(original_of "$file")"
    [[ -n "$original" ]] || { echo "$file: no upstream original" >&2; continue; }
    diff -u "$original" <(tail -n +2 "$file" | sed '1{/^$/d;}') --label "upstream/${original#"$upstream"/}" --label "$file" || true
  done
  exit 0
fi

cd "$root"
find Sources/MapLibre -type f \( -name '*.h' -o -name '*.m' -o -name '*.mm' \) | sort | while read -r file; do
  original="$(original_of "$file")"
  [[ -n "$original" ]] || continue
  if head -n 1 "$file" | grep -q '^// Based on '; then
    changed="$(diff <(tail -n +2 "$file" | sed '1{/^$/d;}') "$original" | grep -c '^[<>]' || true)"
    printf '%6s lines changed  %s\n' "$changed" "$file"
  elif ! cmp -s "$file" "$original"; then
    printf '%6s                %s (differs but has no "Based on" line)\n' '!' "$file"
  fi
done
