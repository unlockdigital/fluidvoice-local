#!/bin/bash
#
# Phase 9 runtime checks for FluidVoice Hardened.
#
# Run this AFTER launching the hardened app once and dictating the fake phrases (see
# docs/CONTROLLED_TEST_PLAN.md). It automates every inspectable check:
#   - Local API port 47733 is closed
#   - the app has no unexpected listening sockets
#   - first-run secure defaults are active (analytics/updates/debug/history/command/localapi/cloud OFF)
#   - no fake dictation phrase appears in logs or local data stores
#
# It canNOT verify the firewall/outbound-network behavior — that requires LuLu/Little Snitch
# logs (a human step). This script prints what to check there.
#
# Usage:  ./scripts/phase9-runtime-checks.sh
#
set -uo pipefail

BUNDLE_ID="com.unlockdigital.FluidVoiceHardened"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_SUPPORT="$HOME/Library/Application Support/FluidVoiceHardened"
LOGS_DIR="$HOME/Library/Logs/FluidVoiceHardened"
PORT=47733
# Fake phrases from the controlled test plan (must NEVER appear in logs/stores).
FAKE_PATTERN="redwood alpha|blue folder|forty two|Jordan about the blue folder"

FAIL=0
pass() { printf "  \033[32mPASS\033[0m  %s\n" "$1"; }
fail() { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; FAIL=1; }
warn() { printf "  \033[33mMANUAL\033[0m %s\n" "$1"; }
section() { printf "\n== %s ==\n" "$1"; }

# ---------------------------------------------------------------------------
section "Local API port $PORT closed"
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  fail "Port $PORT is LISTENING (Local API should be off)"
  lsof -nP -iTCP:"$PORT" | sed 's/^/        /'
else
  pass "Port $PORT is not listening"
fi

# ---------------------------------------------------------------------------
section "App listening sockets"
SOCKETS="$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | grep -iE 'Fluid' || true)"
if [ -n "$SOCKETS" ]; then
  fail "Hardened app has listening TCP sockets:"
  printf '%s\n' "$SOCKETS" | sed 's/^/        /'
else
  pass "No listening TCP sockets owned by the hardened app"
fi

# ---------------------------------------------------------------------------
section "First-run secure defaults ($BUNDLE_ID)"
if "$SCRIPT_DIR/check-hardened-preferences.sh" "$BUNDLE_ID"; then
  pass "All case-sensitive hardened preferences match the secure profile"
else
  fail "One or more hardened preferences are missing or insecure"
fi

# ---------------------------------------------------------------------------
section "No fake dictation content in logs / data stores"
SCAN_HITS=""
for loc in "$LOGS_DIR" "$APP_SUPPORT"; do
  [ -e "$loc" ] || continue
  if command -v rg >/dev/null 2>&1; then
    HIT="$(rg -i --no-heading -n "$FAKE_PATTERN" "$loc" 2>/dev/null || true)"
  else
    HIT="$(grep -riEn "$FAKE_PATTERN" "$loc" 2>/dev/null || true)"
  fi
  [ -n "$HIT" ] && SCAN_HITS="$SCAN_HITS"$'\n'"$HIT"
done
# Also scan the UserDefaults plist (history persists there).
PLIST="$HOME/Library/Preferences/$BUNDLE_ID.plist"
if [ -f "$PLIST" ]; then
  DUMP="$(defaults read "$BUNDLE_ID" 2>/dev/null | grep -iE "$FAKE_PATTERN" || true)"
  [ -n "$DUMP" ] && SCAN_HITS="$SCAN_HITS"$'\n'"(UserDefaults) $DUMP"
fi
if [ -n "$(printf '%s' "$SCAN_HITS" | tr -d '[:space:]')" ]; then
  fail "Fake dictation content found in logs/stores:"
  printf '%s\n' "$SCAN_HITS" | sed 's/^/        /' | head -20
else
  pass "No fake dictation phrases in logs, Application Support, or UserDefaults"
fi

# ---------------------------------------------------------------------------
section "FluidAudio model integrity (no empty/partial model dirs)"
MODELS_DIR="$HOME/Library/Application Support/FluidAudio/Models"
REQUIRED_FILES=(Preprocessor.mlmodelc Encoder.mlmodelc Decoder.mlmodelc JointDecision.mlmodelc parakeet_vocab.json)
MIN_MB=50   # a real Parakeet model is hundreds of MB; anything tiny is empty/partial/corrupt
if [ ! -d "$MODELS_DIR" ]; then
  pass "No FluidAudio models installed yet (nothing to validate)"
else
  any=0
  for d in "$MODELS_DIR"/*/; do
    [ -d "$d" ] || continue
    any=1
    name="$(basename "$d")"
    sizemb="$(du -sm "$d" 2>/dev/null | awk '{print $1}')"
    sizemb="${sizemb:-0}"
    if [ "$sizemb" -lt "$MIN_MB" ]; then
      fail "Model dir '$name' is ${sizemb}MB (< ${MIN_MB}MB) — empty/partial/corrupt"
      continue
    fi
    case "$name" in
      parakeet-tdt-*)
        missing=""
        for f in "${REQUIRED_FILES[@]}"; do
          find "$d" -name "$f" 2>/dev/null | grep -q . || missing="$missing $f"
        done
        if [ -n "$missing" ]; then
          fail "Model dir '$name' (${sizemb}MB) missing required files:$missing"
        else
          pass "Model dir '$name' = ${sizemb}MB with all required files"
        fi
        ;;
      *)
        pass "Model dir '$name' = ${sizemb}MB (size check only)"
        ;;
    esac
  done
  [ "$any" -eq 0 ] && pass "FluidAudio Models dir present but contains no model subdirs"
fi

# ---------------------------------------------------------------------------
section "FluidAudio model SHA-256 manifest"
APP_PATH="${FLUIDVOICE_APP_PATH:-}"
if [ -z "$APP_PATH" ] && [ -d "/Applications/FluidVoice Hardened.app" ]; then
  APP_PATH="/Applications/FluidVoice Hardened.app"
fi
if [ -z "$APP_PATH" ] && [ -d "$REPO_DIR/build/FluidVoice Hardened.app" ]; then
  APP_PATH="$REPO_DIR/build/FluidVoice Hardened.app"
fi
MODEL_NAME="parakeet-tdt-0.6b-v2-coreml"
MANIFEST="$APP_PATH/Contents/Resources/PreseededModels/$MODEL_NAME.manifest.json"
MODEL_DIR="$MODELS_DIR/$MODEL_NAME"
if [ -z "$APP_PATH" ] || [ ! -f "$MANIFEST" ]; then
  fail "Packaged model manifest unavailable (set FLUIDVOICE_APP_PATH to the installed app)"
elif [ ! -d "$MODEL_DIR" ]; then
  fail "Installed model directory unavailable: $MODEL_DIR"
elif ! command -v jq >/dev/null 2>&1; then
  fail "jq is required for full model-manifest verification"
elif (
  cd "$MODEL_DIR" || exit 1
  jq -r '.files | to_entries[] | "\(.value)  \(.key)"' "$MANIFEST" | shasum -a 256 -c - >/dev/null
); then
  pass "Every installed model file matches the packaged SHA-256 manifest"
else
  fail "Installed model checksum mismatch"
fi

# ---------------------------------------------------------------------------
section "Manual checks (cannot be automated here)"
warn "Confirm the outbound firewall (LuLu/Little Snitch) shows ZERO external connections"
warn "from '$BUNDLE_ID' after model setup (localhost to Ollama/LM Studio is allowed)."
warn "Confirm local ASR and local post-processing both work with network blocked."

# ---------------------------------------------------------------------------
section "Summary"
if [ "$FAIL" -eq 0 ]; then
  printf "\n\033[32mAutomated Phase 9 checks passed. Complete the manual firewall checks above.\033[0m\n"
else
  printf "\n\033[31mPhase 9 checks FAILED. See above.\033[0m\n"
fi
exit "$FAIL"
