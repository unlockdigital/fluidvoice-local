#!/bin/bash
# Read-only live readiness check for the installed FluidVoice input source.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_APP="$HOME/Library/Input Methods/FluidVoice Direct Input.app"
# Resolve the executable from metadata for both preserved and renamed candidates.
TARGET_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$TARGET_APP/Contents/Info.plist" 2>/dev/null || true)"
case "$TARGET_EXECUTABLE" in
  'FluidVoice Local'|'FluidVoice Hardened') ;;
  *) echo "FAIL: Unexpected or missing direct-input executable identity."; exit 1 ;;
esac
TARGET_BIN="$TARGET_APP/Contents/MacOS/$TARGET_EXECUTABLE"
GUARDIAN_LABEL="com.unlockdigital.fluidvoice-input-source-guardian"
GUARDIAN_BIN="$HOME/Library/Application Support/FluidVoiceHardened/InputSourceGuardian/FluidVoiceInputSourceGuardian"
GUARDIAN_SOURCE="$REPO_DIR/scripts/fluidvoice-input-source-guardian.swift"
GUARDIAN_MANIFEST="$HOME/Library/Application Support/FluidVoiceHardened/InputSourceGuardian/install-manifest.txt"
GUARDIAN_PLIST="$HOME/Library/LaunchAgents/$GUARDIAN_LABEL.plist"
TEMP_DIR="$(mktemp -d /private/tmp/fluidvoice-health.XXXXXX)"
INSPECTOR_BIN="$TEMP_DIR/inspect-direct-input-state"
GLOBE_KEY_BIN="$TEMP_DIR/configure-globe-key"
MODULE_CACHE_DIR="$TEMP_DIR/module-cache"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

if [ ! -d "$TARGET_APP" ]; then
  echo "FAIL: FluidVoice Direct Input is not installed at the canonical path."
  exit 1
fi

"$REPO_DIR/scripts/verify-direct-input-method.sh" "$TARGET_APP"

mkdir -p "$MODULE_CACHE_DIR"
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR/clang" \
  SWIFT_MODULECACHE_PATH="$MODULE_CACHE_DIR/swift" \
  xcrun swiftc "$REPO_DIR/scripts/inspect-direct-input-state.swift" -framework Carbon -o "$INSPECTOR_BIN"
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR/clang" \
  SWIFT_MODULECACHE_PATH="$MODULE_CACHE_DIR/swift" \
  xcrun swiftc "$REPO_DIR/scripts/configure-globe-key.swift" -framework Carbon -o "$GLOBE_KEY_BIN"
"$INSPECTOR_BIN" --require-ready
"$GLOBE_KEY_BIN" --require-emoji

PROCESS_PIDS="$(pgrep -f -x "$TARGET_BIN" || true)"
if [ -z "$PROCESS_PIDS" ]; then
  PROCESS_COUNT=0
else
  PROCESS_COUNT="$(printf '%s\n' "$PROCESS_PIDS" | wc -l | tr -d ' ')"
fi
if [ "$PROCESS_COUNT" != "1" ]; then
  echo "FAIL: Expected one FluidVoice Direct Input process; found $PROCESS_COUNT."
  exit 1
fi

if [ ! -x "$GUARDIAN_BIN" ] || ! codesign --verify --strict "$GUARDIAN_BIN"; then
  echo "FAIL: FluidVoice input-source guardian is missing or has an invalid signature."
  exit 1
fi
if [ ! -f "$GUARDIAN_MANIFEST" ]; then
  echo "FAIL: FluidVoice input-source guardian install manifest is missing."
  exit 1
fi
EXPECTED_GUARDIAN_SOURCE_SHA="$(shasum -a 256 "$GUARDIAN_SOURCE" | awk '{print $1}')"
INSTALLED_GUARDIAN_SOURCE_SHA="$(awk -F= '$1 == "guardian_source_sha256" { print $2 }' "$GUARDIAN_MANIFEST")"
EXPECTED_GUARDIAN_BINARY_SHA="$(awk -F= '$1 == "guardian_binary_sha256" { print $2 }' "$GUARDIAN_MANIFEST")"
INSTALLED_GUARDIAN_BINARY_SHA="$(shasum -a 256 "$GUARDIAN_BIN" | awk '{print $1}')"
INSTALLED_LAUNCH_MODE="$(awk -F= '$1 == "runtime_launch_mode" { print $2 }' "$GUARDIAN_MANIFEST")"
if [ "$EXPECTED_GUARDIAN_SOURCE_SHA" != "$INSTALLED_GUARDIAN_SOURCE_SHA" ]; then
  echo "FAIL: Installed guardian was built from a different source revision."
  exit 1
fi
if [ "$EXPECTED_GUARDIAN_BINARY_SHA" != "$INSTALLED_GUARDIAN_BINARY_SHA" ]; then
  echo "FAIL: Installed guardian binary differs from its install manifest."
  exit 1
fi
if [ "$INSTALLED_LAUNCH_MODE" != "background-overlay-visible" ]; then
  echo "FAIL: Installed guardian launch mode does not preserve overlay visibility."
  exit 1
fi
if [ ! -f "$GUARDIAN_PLIST" ] || ! plutil -lint "$GUARDIAN_PLIST" >/dev/null; then
  echo "FAIL: FluidVoice input-source guardian launch configuration is missing or invalid."
  exit 1
fi
USER_GUI_DOMAIN="gui/$(id -u)"
if ! launchctl print "$USER_GUI_DOMAIN/$GUARDIAN_LABEL" >/dev/null 2>&1; then
  echo "FAIL: FluidVoice input-source guardian is not loaded."
  exit 1
fi

echo "PASS: FluidVoice Direct Input, its source guardian, and Globe-to-Emoji assignment are ready."
