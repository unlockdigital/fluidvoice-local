#!/bin/bash
#
# Create the least-privilege FluidVoice macOS input source from the verified hardened build.
#
# Output: build/FluidVoice Local Direct Input.app
# Usage:  ./scripts/package-direct-input-method.sh
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BASE_APP="$REPO_DIR/build/FluidVoice Local.app"
DIRECT_APP="$REPO_DIR/build/FluidVoice Local Direct Input.app"
PLIST="$DIRECT_APP/Contents/Info.plist"
SIGN_ID="${SIGN_IDENTITY:--}"
BUNDLE_ID="com.unlockdigital.inputmethod.FluidVoiceHardened"
MODE_ID="$BUNDLE_ID.direct"
CONNECTION_NAME="${BUNDLE_ID}_Connection"
ENTITLEMENTS="$REPO_DIR/FluidVoiceDirectInput.entitlements"
LOCALIZATION_SOURCE="$REPO_DIR/Resources/DirectInput/en.lproj/InfoPlist.strings"

if [ ! -d "$BASE_APP" ]; then
  echo "ERROR: package the hardened base app first with ./scripts/package-release.sh"
  exit 1
fi

echo "[0/4] Verifying direct-input modifier gestures ..."
bash "$REPO_DIR/scripts/test-direct-input-modifier-gestures.sh"

echo "[1/4] Cloning verified hardened app into the input-source bundle ..."
if [ -e "$DIRECT_APP" ]; then
  echo "ERROR: output already exists: $DIRECT_APP"
  echo "       Move the existing output to an archive location before packaging."
  exit 1
fi
cp -cR "$BASE_APP" "$DIRECT_APP"

delete_plist_key() {
  /usr/libexec/PlistBuddy -c "Delete :$1" "$PLIST" >/dev/null 2>&1 || true
}

echo "[2/4] Applying InputMethodKit identity and least-privilege metadata ..."
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName FluidVoice Local Direct Input" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName FluidVoice Local Direct Input" "$PLIST"

delete_plist_key NSAccessibilityUsageDescription
delete_plist_key NSAppleEventsUsageDescription
delete_plist_key LSUIElement
delete_plist_key LSBackgroundOnly
delete_plist_key ComponentInputModeDict
delete_plist_key FluidVoiceDirectInputMode
delete_plist_key InputMethodConnectionName
delete_plist_key InputMethodServerControllerClass
delete_plist_key InputMethodServerDelegateClass
delete_plist_key NSPrincipalClass
delete_plist_key TISInputSourceID
delete_plist_key TISIntendedLanguage
delete_plist_key CFBundleDevelopmentRegion
delete_plist_key CFBundleInfoDictionaryVersion
delete_plist_key CFBundleSignature
delete_plist_key NSSupportsSuddenTermination
delete_plist_key TISIconIsTemplate
delete_plist_key tsInputMethodCharacterRepertoireKey
delete_plist_key tsInputMethodIconFileKey

/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string en" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleSignature string ????" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :FluidVoiceDirectInputMode bool true" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :InputMethodConnectionName string $CONNECTION_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :InputMethodServerControllerClass string FluidVoiceInputController" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :InputMethodServerDelegateClass string FluidVoiceInputController" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :NSPrincipalClass string NSApplication" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :NSSupportsSuddenTermination bool true" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :TISInputSourceID string $BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :TISIntendedLanguage string en" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :TISIconIsTemplate bool false" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :tsInputMethodCharacterRepertoireKey array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :tsInputMethodCharacterRepertoireKey: string Latn" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :tsInputMethodIconFileKey string AppIcon.icns" "$PLIST"

/usr/libexec/PlistBuddy -c "Add :ComponentInputModeDict dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ComponentInputModeDict:tsInputModeListKey dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ComponentInputModeDict:tsInputModeListKey:$MODE_ID dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ComponentInputModeDict:tsInputModeListKey:$MODE_ID:TISInputSourceID string $MODE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ComponentInputModeDict:tsInputModeListKey:$MODE_ID:TISIntendedLanguage string en" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ComponentInputModeDict:tsInputModeListKey:$MODE_ID:tsInputModeIsVisibleKey bool true" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ComponentInputModeDict:tsInputModeListKey:$MODE_ID:tsInputModePrimaryInScriptKey bool false" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ComponentInputModeDict:tsInputModeListKey:$MODE_ID:tsInputModeScriptKey string smUnicodeScript" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ComponentInputModeDict:tsInputModeListKey:$MODE_ID:tsInputModeMenuIconFileKey string AppIcon.icns" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ComponentInputModeDict:tsInputModeListKey:$MODE_ID:TISIconLabels dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ComponentInputModeDict:tsInputModeListKey:$MODE_ID:TISIconLabels:Primary string FV" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ComponentInputModeDict:tsVisibleInputModeOrderedArrayKey array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :ComponentInputModeDict:tsVisibleInputModeOrderedArrayKey: string $MODE_ID" "$PLIST"

mkdir -p "$DIRECT_APP/Contents/Resources/en.lproj"
cp "$LOCALIZATION_SOURCE" "$DIRECT_APP/Contents/Resources/en.lproj/InfoPlist.strings"

plutil -lint "$PLIST"
plutil -lint "$DIRECT_APP/Contents/Resources/en.lproj/InfoPlist.strings"

echo "[3/4] Re-signing with Hardened Runtime and microphone-only entitlement ..."
SIGN_ARGS=(--force --options runtime --sign "$SIGN_ID")
if [ "$SIGN_ID" != "-" ]; then
  SIGN_ARGS+=(--timestamp)
fi
find "$DIRECT_APP/Contents/Frameworks" -name '*.framework' -type d 2>/dev/null | while read -r framework; do
  codesign "${SIGN_ARGS[@]}" "$framework"
done
codesign "${SIGN_ARGS[@]}" --entitlements "$ENTITLEMENTS" "$DIRECT_APP"

echo "[4/4] Verifying bundle, model, identity, and direct-input gates ..."
EXPECTED_BUNDLE_ID="$BUNDLE_ID" EXPECTED_NAME_PREFIX="FluidVoice Local Direct Input" \
  "$REPO_DIR/scripts/verify-built-app.sh" "$DIRECT_APP"
"$REPO_DIR/scripts/verify-direct-input-method.sh" "$DIRECT_APP"

echo
echo "Delivered: $DIRECT_APP"
