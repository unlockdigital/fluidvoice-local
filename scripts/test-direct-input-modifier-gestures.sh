#!/bin/bash
# Regression tests for Right Option ownership and Globe/Fn Character Viewer passthrough.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d /private/tmp/fluidvoice-modifier-tests.XXXXXX)"
MODULE_CACHE_DIR="$TEMP_DIR/module-cache"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$MODULE_CACHE_DIR"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR/clang" \
  SWIFT_MODULECACHE_PATH="$MODULE_CACHE_DIR/swift" \
  xcrun swiftc \
    "$REPO_DIR/Sources/Fluid/Hardening/DirectInputModifierGestureTracker.swift" \
    "$REPO_DIR/scripts/fixtures/DirectInputModifierGestureTests.swift" \
    -framework AppKit \
    -o "$TEMP_DIR/modifier-gesture-tests"

"$TEMP_DIR/modifier-gesture-tests"
