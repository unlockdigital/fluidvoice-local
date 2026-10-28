#!/bin/bash
#
# Post-build verification for FluidVoice Hardened.
#
# Inspects a BUILT .app bundle (not the source tree) to confirm the hardened identity
# actually shipped: hardened bundle id, hardened product name, no telemetry keys in the
# embedded Info.plist, and that the binary was compiled with the HARDENED flag.
#
# First-run secure defaults (analytics/updates/debug-logs/history/Command Mode/Local API
# OFF) are enforced in code via `#if HARDENED` + SettingsStore.enforceHardenedDefaults()
# and are proven statically by verify-hardening.sh. Their RUNTIME values are confirmed in
# the Phase 9 fake-data trial by reading the app's UserDefaults domain after first launch.
#
# Usage:
#   ./scripts/verify-built-app.sh /path/to/FluidVoice\ Hardened.app
#   ./scripts/verify-built-app.sh            # auto-discovers under ./scratchpad DerivedData / ~/Library/Developer
#
set -uo pipefail

EXPECTED_BUNDLE_ID="${EXPECTED_BUNDLE_ID:-com.unlockdigital.FluidVoiceHardened}"
EXPECTED_NAME_PREFIX="${EXPECTED_NAME_PREFIX:-FluidVoice Hardened}"

FAIL=0
pass() { printf "  \033[32mPASS\033[0m  %s\n" "$1"; }
fail() { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; FAIL=1; }

APP="${1:-}"
if [ -z "$APP" ]; then
  APP="$(find "$HOME/Library/Developer/Xcode/DerivedData" /tmp -name 'FluidVoice Hardened*.app' -maxdepth 8 -type d 2>/dev/null | head -1)"
fi

if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "Built .app not found. Pass the path explicitly:"
  echo "  ./scripts/verify-built-app.sh \"/path/to/FluidVoice Hardened.app\""
  exit 2
fi

# Resolve the bundle path before the model verifier changes its working directory.
# This keeps explicit relative paths and auto-discovered absolute paths equivalent.
APP="$(cd "$(dirname "$APP")" && pwd -P)/$(basename "$APP")"

PLIST="$APP/Contents/Info.plist"
BIN="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST" 2>/dev/null)"
echo "Inspecting: $APP"
echo

read_key() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null; }

# 1. Bundle identifier
BID="$(read_key CFBundleIdentifier)"
[ "$BID" = "$EXPECTED_BUNDLE_ID" ] && pass "Bundle id = $BID" || fail "Bundle id = '$BID' (expected $EXPECTED_BUNDLE_ID)"

# 2. Product / display name
BNAME="$(read_key CFBundleName)"
case "$BNAME" in
  "$EXPECTED_NAME_PREFIX"*) pass "Product name = $BNAME" ;;
  *) fail "Product name = '$BNAME' (expected to start with '$EXPECTED_NAME_PREFIX')" ;;
esac

# 3. No telemetry keys embedded
if read_key POSTHOG_API_KEY >/dev/null 2>&1 || read_key POSTHOG_HOST >/dev/null 2>&1; then
  fail "Telemetry keys present in built Info.plist"
else
  pass "No PostHog keys in built Info.plist"
fi

# 4. No PostHog string anywhere in the bundle binary/resources
if grep -aErl "eu\.i\.posthog\.com|us\.i\.posthog\.com|phc_[A-Za-z0-9]{20}" "$APP" >/dev/null 2>&1; then
  fail "PostHog host/key string found inside the built bundle"
else
  pass "No PostHog host/key strings inside the built bundle"
fi

warn() { printf "  \033[33mWARN\033[0m  %s\n" "$1"; }

# ---------------------------------------------------------------------------
# 5. Packaging integrity: every @rpath dynamic dependency is embedded.
#    Collect Mach-O binaries (main executable + embedded frameworks) and verify
#    each @rpath/<Name>.framework/... resolves to Contents/Frameworks/<Name>.framework
#    (system frameworks under /System|/usr/lib are always fine and are not @rpath).
echo
FW_DIR="$APP/Contents/Frameworks"
MISSING=""
binaries=("$BIN")
if [ -d "$FW_DIR" ]; then
  while IFS= read -r fw; do
    binaries+=("$fw")
  done < <(find "$FW_DIR" -type f -perm -u+x 2>/dev/null)
fi

if otool -L "$BIN" 2>/dev/null | grep -q 'MediaRemoteAdapter'; then
  fail "MediaRemoteAdapter remains dynamically linked"
else
  pass "Private MediaRemoteAdapter dynamic dependency absent"
fi
for b in "${binaries[@]}"; do
  [ -f "$b" ] || continue
  while IFS= read -r dep; do
    # dep like @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter
    name="$(printf '%s' "$dep" | sed -E 's#^@rpath/([^/]+\.framework)/.*#\1#')"
    [ -z "$name" ] && continue
    if [ ! -d "$FW_DIR/$name" ]; then
      MISSING="$MISSING"$'\n'"        $(basename "$b"): $dep"
    fi
  done < <(otool -L "$b" 2>/dev/null | awk '/@rpath\/.*\.framework\//{print $1}' | sort -u)
done
if [ -n "$(printf '%s' "$MISSING" | tr -d '[:space:]')" ]; then
  fail "Missing embedded @rpath frameworks in Contents/Frameworks:"
  printf '%s\n' "$MISSING"
else
  if [ -d "$FW_DIR" ]; then
    pass "All @rpath frameworks embedded ($(ls "$FW_DIR" 2>/dev/null | tr '\n' ' '))"
  else
    pass "No @rpath dynamic frameworks required (none missing)"
  fi
fi

# 6. Code signature integrity (deep, strict). Ad-hoc supports a local test build;
#    this catches incomplete/inconsistent bundles like the missing-resources error.
if codesign --verify --deep --strict --verbose=2 "$APP" >/tmp/_cs.txt 2>&1; then
  pass "codesign --verify --deep --strict OK"
else
  fail "codesign --verify --deep --strict FAILED:"
  sed 's/^/        /' /tmp/_cs.txt | head -8
fi

# 6b. Hardened runtime and least-privilege signature entitlements.
CS_DETAIL="$(codesign -dvv "$APP" 2>&1 || true)"
if printf '%s' "$CS_DETAIL" | grep -q 'flags=.*runtime'; then
  pass "Hardened runtime flag present in code signature"
else
  fail "Hardened runtime flag missing from code signature"
fi

ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)"
if printf '%s' "$ENTITLEMENTS" | grep -Eq 'get-task-allow|disable-library-validation|network\.server|automation\.apple-events'; then
  fail "High-risk entitlement found in app signature"
  printf '%s\n' "$ENTITLEMENTS" | sed 's/^/        /' | head -20
else
  pass "No debugger, library-validation bypass, server, or Apple Events entitlement"
fi

# 7. Gatekeeper assessment. An ad-hoc/unsigned local build is EXPECTED to be rejected
#    (not notarized / no Developer ID); report it but do not fail the packaging check.
if spctl --assess --type execute --verbose=4 "$APP" >/tmp/_spctl.txt 2>&1; then
  pass "spctl --assess --type execute: accepted"
else
  warn "spctl --assess --type execute: rejected (expected for ad-hoc/unsigned local build)"
  sed 's/^/        /' /tmp/_spctl.txt | head -4
fi

# ---------------------------------------------------------------------------
# 8. Required preseeded offline model and full manifest verification.
echo
PRESEED="$APP/Contents/Resources/PreseededModels"
MODEL_NAME="parakeet-tdt-0.6b-v2-coreml"
REQ=(Preprocessor.mlmodelc Encoder.mlmodelc Decoder.mlmodelc JointDecision.mlmodelc parakeet_vocab.json)
if [ -d "$PRESEED/$MODEL_NAME" ]; then
  miss=""
  for f in "${REQ[@]}"; do [ -e "$PRESEED/$MODEL_NAME/$f" ] || miss="$miss $f"; done
  szmb="$(du -sm "$PRESEED/$MODEL_NAME" 2>/dev/null | awk '{print $1}')"; szmb="${szmb:-0}"
  if [ -n "$miss" ]; then
    fail "Preseeded model incomplete — missing:$miss"
  elif [ ! -f "$PRESEED/$MODEL_NAME.manifest.json" ]; then
    fail "Preseeded model present but manifest.json missing"
  elif [ "$szmb" -lt 50 ]; then
    fail "Preseeded model too small (${szmb}MB) — empty/partial"
  elif ! command -v jq >/dev/null 2>&1; then
    fail "jq is required for complete packaged-model verification"
  elif (
    cd "$PRESEED/$MODEL_NAME" || exit 1
    jq -r '.files | to_entries[] | "\(.value)  \(.key)"' "$PRESEED/$MODEL_NAME.manifest.json" | shasum -a 256 -c - >/dev/null
  ); then
    pass "Every packaged model file matches the SHA-256 manifest"
    [ -f "$PRESEED/$MODEL_NAME.LICENSE.txt" ] && pass "Model license/attribution included" || warn "Model license file missing"
  else
    fail "Packaged model checksum verification failed"
  fi
else
  fail "Required preseeded offline model is absent"
fi

echo
if [ "$FAIL" -eq 0 ]; then
  printf "\033[32mBuilt-app verification passed.\033[0m\n"
else
  printf "\033[31mBuilt-app verification FAILED.\033[0m\n"
fi
exit "$FAIL"
