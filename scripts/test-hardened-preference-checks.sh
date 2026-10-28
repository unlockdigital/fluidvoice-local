#!/bin/bash

# Negative-test the case-sensitive runtime preference checker without touching the live domain.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKER="$SCRIPT_DIR/check-hardened-preferences.sh"
TEST_TMP="$(mktemp -d "/private/tmp/fluidvoice-preference-test.XXXXXX")"
TEST_DOMAIN="$TEST_TMP/secure-profile"

cleanup() {
  rm -rf "$TEST_TMP"
}
trap cleanup EXIT

OFF_KEYS=(
  ShareAnonymousAnalytics
  AutoUpdateCheckEnabled
  EnableDebugLogs
  SaveTranscriptionHistory
  SaveAudioWithTranscriptionHistory
  CommandModeShortcutEnabled
  LocalAPIEnabled
  AllowCloudProviders
  EnableAIProcessing
  PromptModeShortcutEnabled
  RewriteModeShortcutEnabled
)
ON_KEYS=(DictationPromptOff EditPromptOff SecondaryDictationPromptOff)

for key in "${OFF_KEYS[@]}"; do defaults write "$TEST_DOMAIN" "$key" -bool false; done
for key in "${ON_KEYS[@]}"; do defaults write "$TEST_DOMAIN" "$key" -bool true; done
defaults write "$TEST_DOMAIN" SelectedSpeechModel -string parakeet-tdt-v2

"$CHECKER" "$TEST_DOMAIN" >/dev/null
printf "  PASS  secure fixture accepted\n"

for key in "${OFF_KEYS[@]}"; do
  defaults write "$TEST_DOMAIN" "$key" -bool true
  if "$CHECKER" "$TEST_DOMAIN" >/dev/null; then
    printf "  FAIL  insecure value escaped detection: %s=1\n" "$key"
    exit 1
  fi
  defaults write "$TEST_DOMAIN" "$key" -bool false
done

for key in "${ON_KEYS[@]}"; do
  defaults write "$TEST_DOMAIN" "$key" -bool false
  if "$CHECKER" "$TEST_DOMAIN" >/dev/null; then
    printf "  FAIL  insecure value escaped detection: %s=0\n" "$key"
    exit 1
  fi
  defaults write "$TEST_DOMAIN" "$key" -bool true
done

defaults write "$TEST_DOMAIN" SelectedSpeechModel -string whisper-base
if "$CHECKER" "$TEST_DOMAIN" >/dev/null; then
  printf "  FAIL  insecure model selection escaped detection\n"
  exit 1
fi

printf "  PASS  every insecure preference mutation was rejected\n"
