#!/bin/bash
#
# Reset all local state owned by FluidVoice Local.
#
# Removes the hardened build's UserDefaults, Keychain credentials, logs, and
# Application Support data so the next launch starts from a clean, first-run state.
# Does NOT touch any upstream FluidVoice (com.FluidApp.app) install.
#
# Non-sensitive model caches (FluidAudio / WhisperModels) are left in place so a
# reset does not force multi-gigabyte re-downloads. Pass --models to also remove them.
#
# Usage:  ./scripts/reset-hardened-state.sh [--models]
#
set -euo pipefail

BUNDLE_ID="com.unlockdigital.FluidVoiceHardened"
APP_SUPPORT_FOLDER="FluidVoiceHardened"
LOGS_FOLDER="FluidVoiceHardened"
KEYCHAIN_SERVICE="com.unlockdigital.fluidvoicehardened.provider-api-keys"

REMOVE_MODELS=0
[ "${1:-}" = "--models" ] && REMOVE_MODELS=1

echo "Resetting FluidVoice Local local state..."

# UserDefaults holds settings AND transcription/file-transcription history + derived stats;
# Application Support holds dictation audio history. Both are removed below.
echo "- UserDefaults ($BUNDLE_ID) [settings + transcription history + stats]"
defaults delete "$BUNDLE_ID" 2>/dev/null || echo "    (none)"

echo "- Keychain provider API keys ($KEYCHAIN_SERVICE)"
security delete-generic-password -s "$KEYCHAIN_SERVICE" 2>/dev/null || echo "    (none)"

echo "- Logs (~/Library/Logs/$LOGS_FOLDER)"
rm -rf "$HOME/Library/Logs/$LOGS_FOLDER"

echo "- Application Support (~/Library/Application Support/$APP_SUPPORT_FOLDER)"
rm -rf "$HOME/Library/Application Support/$APP_SUPPORT_FOLDER"

if [ "$REMOVE_MODELS" -eq 1 ]; then
  echo "- Model caches (FluidAudio, WhisperModels)"
  rm -rf "$HOME/Library/Application Support/FluidAudio"
  rm -rf "$HOME/Library/Application Support/WhisperModels"
else
  echo "- Model caches: kept (use --models to remove)"
fi

echo "Done. Next launch will start from a clean hardened state."
