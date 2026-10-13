#!/usr/bin/env bash
# Typecheck App/Sources on Linux against the Apple-framework stubs in Stubs/.
#   tools/ios-typecheck/run.sh            # app sources + stub samples
#   tools/ios-typecheck/run.sh --app-only # skip Tests/StubSamples
# Prints compiler diagnostics (paths rewritten to App/Sources/...) and exits non-zero on any error.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SRC="$REPO/App/Sources"
DST="$HERE/Sources/AppTypecheck"
SWIFT="${SWIFT:-swift}"

# 1. Refresh the copy of App/Sources (mirror: deleted/renamed app files disappear from the copy too).
rm -rf "$DST"
mkdir -p "$DST"
if [ -d "$SRC" ]; then
  (cd "$SRC" && find . -name '*.swift' -print0 | while IFS= read -r -d '' f; do
     mkdir -p "$DST/$(dirname "$f")"
     cp "$f" "$DST/$f"
   done)
fi
if [ -z "$(find "$DST" -name '*.swift' -print -quit)" ]; then
  echo "// no app sources" > "$DST/_Empty.swift"
fi

# 2. Build. Diagnostics point at the copy; rewrite them to the real App/Sources paths.
targets=(--target AppTypecheck)
[ "${1:-}" = "--app-only" ] || targets+=(--target StubSamples)

status=0
for t in "${targets[@]}"; do
  [ "$t" = "--target" ] && continue
  echo "== typecheck: $t"
  set +e
  out="$("$SWIFT" build --package-path "$HERE" --target "$t" -Xswiftc -diagnostic-style=llvm 2>&1)"
  rc=$?
  set -e
  printf '%s\n' "$out" | sed "s#$DST/#App/Sources/#g; s#$HERE/#tools/ios-typecheck/#g" \
    | grep -Ev '^\[[0-9]+/[0-9]+\] (Compiling|Emitting|Write|Planning|Build)|emit-module command failed' \
    | awk '!seen[$0]++' || true
  if [ $rc -ne 0 ] || printf '%s' "$out" | grep -q ' error: '; then
    status=1
  fi
done

if [ $status -ne 0 ]; then
  echo "typecheck FAILED"
else
  echo "typecheck OK"
fi
exit $status
