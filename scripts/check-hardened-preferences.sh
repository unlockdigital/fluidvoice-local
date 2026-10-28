#!/bin/bash

# Validate FluidVoice Local's case-sensitive privacy preferences.
# Usage: ./scripts/check-hardened-preferences.sh [bundle-id]

set -uo pipefail

BUNDLE_ID="${1:-com.unlockdigital.FluidVoiceHardened}"
FAIL=0

pass() { printf "  \033[32mPASS\033[0m  %s\n" "$1"; }
fail() { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; FAIL=1; }

read_value() {
  defaults read "$BUNDLE_ID" "$1" 2>/dev/null || true
}

check_bool() {
  local key="$1" expected="$2" value
  value="$(read_value "$key")"
  if [ -z "$value" ]; then
    fail "$key is unset (expected $expected after first launch)"
  elif [ "$value" = "$expected" ]; then
    pass "$key = $value"
  else
    fail "$key = $value (expected $expected)"
  fi
}

check_string() {
  local key="$1" expected="$2" value
  value="$(read_value "$key")"
  if [ "$value" = "$expected" ]; then
    pass "$key = $value"
  else
    fail "$key = '$value' (expected '$expected')"
  fi
}

check_bool ShareAnonymousAnalytics 0
check_bool AutoUpdateCheckEnabled 0
check_bool EnableDebugLogs 0
check_bool SaveTranscriptionHistory 0
check_bool SaveAudioWithTranscriptionHistory 0
check_bool CommandModeShortcutEnabled 0
check_bool LocalAPIEnabled 0
check_bool AllowCloudProviders 0
check_bool EnableAIProcessing 0
check_bool PromptModeShortcutEnabled 0
check_bool RewriteModeShortcutEnabled 0
check_bool DictationPromptOff 1
check_bool EditPromptOff 1
check_bool SecondaryDictationPromptOff 1
check_string SelectedSpeechModel parakeet-tdt-v2

exit "$FAIL"
