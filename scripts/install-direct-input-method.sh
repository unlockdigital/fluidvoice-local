#!/bin/bash
# Install a verified FluidVoice input source into the current user's Input Methods folder.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="${1:-$REPO_DIR/build/FluidVoice Local Direct Input.app}"
USER_INPUT_METHODS="$HOME/Library/Input Methods"
TARGET_APP="$USER_INPUT_METHODS/FluidVoice Direct Input.app"
STAGING_APP="$USER_INPUT_METHODS/.FluidVoice Direct Input.installing.$$.app"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/Library/Application Support/FluidVoiceHardened/InputMethodBackups"
BACKUP_APP="$BACKUP_DIR/FluidVoice Direct Input.backup-$TIMESTAMP.app"
STATE_BACKUP_DIR="$HOME/Library/Application Support/FluidVoiceHardened/InputMethodStateBackups/$TIMESTAMP"
GUARDIAN_LABEL="com.unlockdigital.fluidvoice-input-source-guardian"
GUARDIAN_DIR="$HOME/Library/Application Support/FluidVoiceHardened/InputSourceGuardian"
GUARDIAN_BIN="$GUARDIAN_DIR/FluidVoiceInputSourceGuardian"
GUARDIAN_SOURCE="$REPO_DIR/scripts/fluidvoice-input-source-guardian.swift"
GUARDIAN_MANIFEST="$GUARDIAN_DIR/install-manifest.txt"
GUARDIAN_PLIST="$HOME/Library/LaunchAgents/$GUARDIAN_LABEL.plist"
GUARDIAN_TEMPLATE="$REPO_DIR/Resources/DirectInput/$GUARDIAN_LABEL.plist"
INSTALLER_TEMP_DIR="$(mktemp -d /private/tmp/fluidvoice-input-installer.XXXXXX)"
chmod 700 "$INSTALLER_TEMP_DIR"

cleanup() {
  rm -rf "$INSTALLER_TEMP_DIR"
  if [ -e "$STAGING_APP" ]; then
    mv "$STAGING_APP" "$STATE_BACKUP_DIR/unfinished-install.app"
  fi
}
trap cleanup EXIT

"$REPO_DIR/scripts/verify-direct-input-method.sh" "$SOURCE_APP"
if ! grep -Fq 'process.arguments = ["-g", canonicalInputSourceURL.path]' "$GUARDIAN_SOURCE"; then
  echo "ERROR: Guardian must launch FluidVoice in the background with overlay visibility preserved."
  exit 1
fi
if grep -Eq 'process\.arguments.*"-[^"]*j[^"]*"' "$GUARDIAN_SOURCE"; then
  echo "ERROR: Guardian contains the macOS hidden-launch flag, which suppresses the transcription overlay."
  exit 1
fi
mkdir -p "$USER_INPUT_METHODS"
mkdir -p "$BACKUP_DIR"
mkdir -p "$STATE_BACKUP_DIR"

# Preserve the exact pre-install Text Input Services preference state so this change remains
# reversible even if macOS refreshes the source catalog asynchronously.
# `defaults export` reads the live CFPreferences domain. Copying the plist file directly can
# capture a stale on-disk cache while cfprefsd still owns newer values in memory.
if ! defaults export com.apple.HIToolbox "$STATE_BACKUP_DIR/com.apple.HIToolbox.plist"; then
  echo "ERROR: Could not preserve the live Text Input Services preferences; install aborted."
  exit 1
fi
defaults read com.apple.HIToolbox > "$STATE_BACKUP_DIR/com.apple.HIToolbox.defaults.txt" 2>/dev/null || true
echo "Pre-install input-source state preserved at: $STATE_BACKUP_DIR"

# Older installer revisions left rollback bundles inside the directory scanned by Text Input
# Services. Duplicate bundle identifiers can suppress the input source, so archive every legacy
# rollback outside the scan directory before installing or registering the active bundle.
for legacy_backup in "$USER_INPUT_METHODS"/FluidVoice\ Direct\ Input.backup-*.app; do
  [ -e "$legacy_backup" ] || continue
  mv "$legacy_backup" "$BACKUP_DIR/"
  echo "Archived legacy rollback outside Input Methods: $BACKUP_DIR/$(basename "$legacy_backup")"
done

cp -cR "$SOURCE_APP" "$STAGING_APP"
codesign --verify --deep --strict --verbose=2 "$STAGING_APP"

if [ -e "$TARGET_APP" ]; then
  mv "$TARGET_APP" "$BACKUP_APP"
  echo "Previous installation preserved at: $BACKUP_APP"
fi
mv "$STAGING_APP" "$TARGET_APP"

# Packaging and code-sign verification can cause Launch Services to discover the source build.
# Keep only the installed path registered so Text Input Services never sees two bundles with the
# same input-method identity.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -u "$SOURCE_APP" >/dev/null 2>&1 || true
"$LSREGISTER" -f -R -trusted "$TARGET_APP"

REGISTRAR_BIN="$INSTALLER_TEMP_DIR/register-input"
PERSIST_BIN="$INSTALLER_TEMP_DIR/persist-input"
ACTIVATE_BIN="$INSTALLER_TEMP_DIR/activate-input"
GLOBE_KEY_BIN="$INSTALLER_TEMP_DIR/configure-globe-key"
GUARDIAN_BUILD_BIN="$INSTALLER_TEMP_DIR/input-source-guardian"
GUARDIAN_STAGED_PLIST="$INSTALLER_TEMP_DIR/$GUARDIAN_LABEL.plist"
MODULE_CACHE_DIR="$INSTALLER_TEMP_DIR/module-cache"
mkdir -p "$MODULE_CACHE_DIR"
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR/clang" \
  SWIFT_MODULECACHE_PATH="$MODULE_CACHE_DIR/swift" \
  xcrun swiftc "$REPO_DIR/scripts/register-direct-input-source.swift" -framework Carbon -o "$REGISTRAR_BIN"
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR/clang" \
  SWIFT_MODULECACHE_PATH="$MODULE_CACHE_DIR/swift" \
  xcrun swiftc "$REPO_DIR/scripts/persist-direct-input-source.swift" -framework Carbon -o "$PERSIST_BIN"
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR/clang" \
  SWIFT_MODULECACHE_PATH="$MODULE_CACHE_DIR/swift" \
  xcrun swiftc "$REPO_DIR/scripts/activate-direct-input-source-macos26.swift" -framework Carbon -o "$ACTIVATE_BIN"
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR/clang" \
  SWIFT_MODULECACHE_PATH="$MODULE_CACHE_DIR/swift" \
  xcrun swiftc "$REPO_DIR/scripts/configure-globe-key.swift" -framework Carbon -o "$GLOBE_KEY_BIN"
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR/clang" \
  SWIFT_MODULECACHE_PATH="$MODULE_CACHE_DIR/swift" \
  xcrun swiftc "$REPO_DIR/scripts/fluidvoice-input-source-guardian.swift" \
    -framework AppKit -framework Carbon -framework IOKit -o "$GUARDIAN_BUILD_BIN"
for helper in "$REGISTRAR_BIN" "$PERSIST_BIN" "$ACTIVATE_BIN" "$GLOBE_KEY_BIN" "$GUARDIAN_BUILD_BIN"; do
  codesign --force --sign - "$helper"
  codesign --verify --strict "$helper"
done
if "$REGISTRAR_BIN" "$TARGET_APP"; then
  echo "Text Input Services registered and enabled the input source."
else
  echo "Public Text Input Services enablement was deferred; applying the guarded macOS 26 transaction."
  "$PERSIST_BIN"
  if ! "$ACTIVATE_BIN" "$TARGET_APP"; then
    echo "ERROR: macOS 26 activation failed; rolling back the app and input-source preferences."
    defaults import com.apple.HIToolbox "$STATE_BACKUP_DIR/com.apple.HIToolbox.plist"
    mv "$TARGET_APP" "$STATE_BACKUP_DIR/failed-install.app"
    if [ -e "$BACKUP_APP" ]; then
      mv "$BACKUP_APP" "$TARGET_APP"
      "$LSREGISTER" -f -R -trusted "$TARGET_APP" >/dev/null 2>&1 || true
    fi
    exit 1
  fi
  "$REGISTRAR_BIN" "$TARGET_APP"
fi

# Adding a second input source can cause macOS to assign the standalone Globe key to the input
# source switcher. This installation's owner uses Globe for Emoji & Symbols, while Right Option
# belongs to FluidVoice. Restore that exact division of responsibility through the same Carbon
# setting used by Keyboard Settings, then fail closed if macOS rejects it. The full pre-install
# HIToolbox domain above remains available for rollback.
"$GLOBE_KEY_BIN" --set-emoji

# A selected input method cannot relaunch itself after its process exits because macOS first
# switches to the U.S. fallback. This short-lived launchd helper reselects the enabled FluidVoice
# mode through public TIS APIs. It pauses in secure fields and leaves every non-U.S. source alone.
mkdir -p "$GUARDIAN_DIR" "$HOME/Library/LaunchAgents"
if [ -f "$GUARDIAN_BIN" ]; then
  cp "$GUARDIAN_BIN" "$STATE_BACKUP_DIR/FluidVoiceInputSourceGuardian"
fi
if [ -f "$GUARDIAN_PLIST" ]; then
  cp "$GUARDIAN_PLIST" "$STATE_BACKUP_DIR/$GUARDIAN_LABEL.plist"
fi
if [ -f "$GUARDIAN_MANIFEST" ]; then
  cp "$GUARDIAN_MANIFEST" "$STATE_BACKUP_DIR/input-source-guardian-install-manifest.txt"
fi

cp "$GUARDIAN_BUILD_BIN" "$GUARDIAN_BIN.installing"
chmod 755 "$GUARDIAN_BIN.installing"
mv "$GUARDIAN_BIN.installing" "$GUARDIAN_BIN"
GUARDIAN_SOURCE_SHA="$(shasum -a 256 "$GUARDIAN_SOURCE" | awk '{print $1}')"
GUARDIAN_BINARY_SHA="$(shasum -a 256 "$GUARDIAN_BIN" | awk '{print $1}')"
{
  printf 'guardian_source_sha256=%s\n' "$GUARDIAN_SOURCE_SHA"
  printf 'guardian_binary_sha256=%s\n' "$GUARDIAN_BINARY_SHA"
  printf 'runtime_launch_mode=background-overlay-visible\n'
} > "$GUARDIAN_MANIFEST.installing"
chmod 644 "$GUARDIAN_MANIFEST.installing"
mv "$GUARDIAN_MANIFEST.installing" "$GUARDIAN_MANIFEST"
cp "$GUARDIAN_TEMPLATE" "$GUARDIAN_STAGED_PLIST"
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 $GUARDIAN_BIN" "$GUARDIAN_STAGED_PLIST"
plutil -lint "$GUARDIAN_STAGED_PLIST"
mv "$GUARDIAN_STAGED_PLIST" "$GUARDIAN_PLIST"
chmod 644 "$GUARDIAN_PLIST"

USER_GUI_DOMAIN="gui/$(id -u)"
launchctl bootout "$USER_GUI_DOMAIN" "$GUARDIAN_PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "$USER_GUI_DOMAIN" "$GUARDIAN_PLIST"
launchctl kickstart -k "$USER_GUI_DOMAIN/$GUARDIAN_LABEL"
launchctl print "$USER_GUI_DOMAIN/$GUARDIAN_LABEL" >/dev/null
echo "Installed FluidVoice input-source guardian: $GUARDIAN_PLIST"

echo "Installed: $TARGET_APP"
echo "Next: select FluidVoice Local Direct Input from the menu-bar input menu."
echo "Right Option toggles dictation while this input source is selected."
echo "Globe opens Emoji & Symbols."
