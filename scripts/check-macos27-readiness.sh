#!/bin/bash
# Read-only observations; exit 3 always means physical qualification remains pending.
set -euo pipefail

case "${1:-}" in
  "") [ "$#" -eq 0 ] || exit 2 ;;
  --self-test|--help) [ "$#" -eq 1 ] || exit 2 ;;
  --fixture)
    [ "$#" -eq 2 ] || exit 2
    case "$2" in host26|observed27|missing27|invalid27|unavailable27|duplicate27|incomplete27|disabled27) ;;
      *) printf '%s\n' 'Unknown readiness fixture.' >&2; exit 2 ;;
    esac ;;
  *) printf '%s\n' 'Usage: bash scripts/check-macos27-readiness.sh [--help|--self-test|--fixture NAME]' >&2; exit 2 ;;
esac

if [ "${1:-}" = --help ]; then
  printf '%s\n' \
    'Read-only macOS 27 readiness observations for the canonical FluidVoice fork.' \
    'Usage: bash scripts/check-macos27-readiness.sh [--self-test|--fixture NAME]' \
    'Fixtures: host26 observed27 missing27 invalid27 unavailable27 duplicate27 incomplete27 disabled27' \
    'Exit 3: qualification pending (including every successful live/fixture report).' \
    'Exit 0: deterministic self-tests passed. Exit 2: usage/toolchain/probe failure.'
  exit 0
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ "$(/usr/bin/uname -s)" != Darwin ]; then
  printf '%s\n' 'UNAVAILABLE: macOS host/toolchain required; qualification pending.' >&2
  exit 2
fi
PROBE_TEMP="$(/usr/bin/mktemp -d /private/tmp/fluidvoice-macos27-readiness.XXXXXX)"
trap 'rm -rf "$PROBE_TEMP"' EXIT
trap 'exit 2' HUP INT TERM
mkdir -p "$PROBE_TEMP/module-cache"

# Keep compiler diagnostics private and temporary: they can contain local paths.
# Compile caches and outputs remain in this fresh /private/tmp directory.
if ! CLANG_MODULE_CACHE_PATH="$PROBE_TEMP/module-cache/clang" \
  SWIFT_MODULECACHE_PATH="$PROBE_TEMP/module-cache/swift" \
  /usr/bin/xcrun swiftc -parse-as-library \
    -module-cache-path "$PROBE_TEMP/module-cache/swift" \
    "$REPO_DIR/scripts/fixtures/MacOS27Readiness.swift" \
    -framework Carbon -framework Security -o "$PROBE_TEMP/readiness" \
    >"$PROBE_TEMP/compiler.log" 2>&1; then
  printf '%s\n' 'UNAVAILABLE: readiness probe compilation failed; qualification pending.' >&2
  exit 2
fi

# Buffer before publishing so framework diagnostics never enter the sanitized report.
PROBE_STATUS=0
"$PROBE_TEMP/readiness" "$@" >"$PROBE_TEMP/report" 2>"$PROBE_TEMP/runtime.log" || PROBE_STATUS=$?
case "$PROBE_STATUS" in
  0|3) cat "$PROBE_TEMP/report" ;;
  *) printf '%s\n' 'UNAVAILABLE: readiness probe failed; qualification pending.' >&2; exit 2 ;;
esac
exit "$PROBE_STATUS"
