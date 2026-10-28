#!/bin/bash
# Verify the packaged FluidVoice InputMethodKit variant.
set -uo pipefail

EXPECTED_BUNDLE_ID="com.unlockdigital.inputmethod.FluidVoiceHardened"
EXPECTED_MODE_ID="$EXPECTED_BUNDLE_ID.direct"
FAIL=0

pass() { printf "  \033[32mPASS\033[0m  %s\n" "$1"; }
fail() { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; FAIL=1; }

APP="${1:-}"
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "Usage: $0 /path/to/FluidVoice\\ Direct\\ Input.app"
  exit 2
fi
APP="$(cd "$(dirname "$APP")" && pwd -P)/$(basename "$APP")"
PLIST="$APP/Contents/Info.plist"
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST" 2>/dev/null)"
BIN="$APP/Contents/MacOS/$EXECUTABLE"

read_key() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null; }

echo "Inspecting direct input source: $APP"
echo

[ "$(read_key CFBundleIdentifier)" = "$EXPECTED_BUNDLE_ID" ] \
  && pass "Dedicated input-source bundle identifier" \
  || fail "Unexpected input-source bundle identifier"
[ "$(read_key FluidVoiceDirectInputMode)" = "true" ] \
  && pass "Direct-input runtime switch enabled" \
  || fail "Direct-input runtime switch missing"
[ "$(read_key InputMethodConnectionName)" = "${EXPECTED_BUNDLE_ID}_Connection" ] \
  && pass "Stable InputMethodKit connection name" \
  || fail "InputMethodKit connection name mismatch"
[ "$(read_key InputMethodServerControllerClass)" = "FluidVoiceInputController" ] \
  && pass "Input controller class declared" \
  || fail "Input controller class mismatch"
[ "$(read_key InputMethodServerDelegateClass)" = "FluidVoiceInputController" ] \
  && pass "Input server delegate class declared" \
  || fail "Input server delegate class mismatch"
[ "$(read_key ComponentInputModeDict:tsInputModeListKey:$EXPECTED_MODE_ID:TISInputSourceID)" = "$EXPECTED_MODE_ID" ] \
  && pass "Visible direct-input mode declared" \
  || fail "Direct-input mode dictionary mismatch"
LOCALIZED_INFO="$APP/Contents/Resources/en.lproj/InfoPlist.strings"
LOCALIZED_NAME="$(/usr/libexec/PlistBuddy -c "Print :$EXPECTED_MODE_ID" "$LOCALIZED_INFO" 2>/dev/null)"
if [ -f "$LOCALIZED_INFO" ] \
  && { [ "$LOCALIZED_NAME" = "FluidVoice Local Direct Input" ] || [ "$LOCALIZED_NAME" = "FluidVoice Direct Input" ]; }; then
  pass "Direct-input mode has a human-readable localized name"
else
  fail "Direct-input mode localization is missing"
fi
if read_key ComponentInputModeDict:tsInputModeListKey:$EXPECTED_MODE_ID:tsInputModeDefaultStateKey >/dev/null 2>&1; then
  fail "Direct-input mode forces a default enabled state outside System Settings"
else
  pass "System Settings owns the direct-input enabled state"
fi
[ "$(read_key tsInputMethodIconFileKey)" = "AppIcon.icns" ] \
  && [ -f "$APP/Contents/Resources/AppIcon.icns" ] \
  && pass "Required input-method icon metadata resolves to a bundled icon" \
  || fail "Input-method icon metadata is missing or invalid"
[ "$(read_key tsInputMethodCharacterRepertoireKey:0)" = "Latn" ] \
  && pass "Latin character repertoire declared" \
  || fail "Input-method character repertoire missing"
[ "$(read_key LSUIElement)" = "true" ] \
  && pass "UI-agent classification supports the FluidVoice overlay" \
  || fail "LSUIElement is not enabled"
if read_key LSBackgroundOnly >/dev/null 2>&1; then
  fail "Background-only classification suppresses the FluidVoice overlay"
else
  pass "Background-only classification absent"
fi

if read_key NSAccessibilityUsageDescription >/dev/null 2>&1; then
  fail "Accessibility usage declaration remains in input-source bundle"
else
  pass "Accessibility usage declaration absent"
fi
if read_key NSAppleEventsUsageDescription >/dev/null 2>&1; then
  fail "Apple Events usage declaration remains in input-source bundle"
else
  pass "Apple Events usage declaration absent"
fi
if [ -n "$(read_key NSMicrophoneUsageDescription)" ]; then
  pass "Microphone purpose string declared"
else
  fail "Microphone purpose string missing"
fi

if otool -L "$BIN" 2>/dev/null | grep -q '/InputMethodKit.framework/'; then
  pass "Executable links the system InputMethodKit framework"
else
  fail "InputMethodKit framework link missing"
fi

ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)"
ENTITLEMENT_KEY_COUNT="$(printf '%s' "$ENTITLEMENTS" | grep -o '<key>' | wc -l | tr -d ' ')"
if [[ "$ENTITLEMENTS" == *'<key>com.apple.security.device.audio-input</key><true/>'* ]] \
  && [ "$ENTITLEMENT_KEY_COUNT" = "1" ]; then
  pass "Signed entitlement set is microphone-only"
else
  fail "Input source entitlement set is not microphone-only"
  printf '%s\n' "$ENTITLEMENTS" | sed 's/^/        /' | head -30
fi

if codesign --verify --deep --strict --verbose=2 "$APP" >/dev/null 2>&1; then
  pass "Deep strict code-signature verification"
else
  fail "Deep strict code-signature verification failed"
fi

SYMBOLS="$(nm -a "$BIN" 2>/dev/null || true)"
if [[ "$SYMBOLS" == *'_OBJC_CLASS_$_FluidVoiceInputController'* ]]; then
  pass "Input controller symbol is present in executable"
else
  fail "Input controller symbol is absent from executable"
fi

echo
if [ "$FAIL" -eq 0 ]; then
  printf "\033[32mDirect-input verification passed.\033[0m\n"
else
  printf "\033[31mDirect-input verification FAILED.\033[0m\n"
fi
exit "$FAIL"
