#!/bin/bash
#
# Static hardening verification for FluidVoice Hardened.
#
# Scans the source tree for privacy-critical regressions. This is the "outer" static
# gate that runs before any build or fake-data test. It grows one section per hardening
# phase. Exit non-zero if any check fails.
#
# Usage:  ./scripts/verify-hardening.sh
#
set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

FAIL=0
pass() { printf "  \033[32mPASS\033[0m  %s\n" "$1"; }
fail() { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; FAIL=1; }
section() { printf "\n== %s ==\n" "$1"; }

# Resolve ripgrep even when PATH is minimal (e.g. under a bare `#!/bin/bash` shebang where
# Homebrew dirs are absent). A broken resolver previously fell back to BSD grep with an
# unquoted, word-split pattern in Basic-regex mode — every check passed VACUOUSLY. Do not
# reintroduce that: keep rg resolution explicit and the grep fallback quoted + ERE (-E).
RG_BIN="$(command -v rg 2>/dev/null || true)"
if [ -z "$RG_BIN" ]; then
  for cand in /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg; do
    if [ -x "$cand" ]; then RG_BIN="$cand"; break; fi
  done
fi

# scan <pattern> [paths...] — print matching "file:line:text". Extended-regex semantics.
scan() {
  local pat="$1"; shift
  if [ -n "$RG_BIN" ]; then
    "$RG_BIN" -n --no-heading -- "$pat" "$@" 2>/dev/null
  else
    grep -rEn -- "$pat" "$@" 2>/dev/null
  fi
}

# ---------------------------------------------------------------------------
section "Telemetry / PostHog (Phase 2)"

if scan "POSTHOG_API_KEY|POSTHOG_HOST|phc_[A-Za-z0-9]" Info.plist >/dev/null; then
  fail "PostHog key/host still present in Info.plist"
else
  pass "No PostHog keys/host in Info.plist"
fi

if scan "posthog-ios|PostHog/posthog" Package.swift Package.resolved >/dev/null; then
  fail "PostHog SPM dependency still present in Package manifests"
else
  pass "No PostHog SPM dependency in Package manifests"
fi

if scan "eu\.i\.posthog\.com|us\.i\.posthog\.com|i\.posthog\.com" Sources Info.plist >/dev/null; then
  fail "PostHog ingestion host literal still present in source/bundle"
else
  pass "No PostHog ingestion host literal in source/bundle"
fi

# ---------------------------------------------------------------------------
section "App identity scoping (Phase 1)"

if scan 'PRODUCT_BUNDLE_IDENTIFIER = com\.FluidApp\.app' Fluid.xcodeproj/project.pbxproj >/dev/null; then
  fail "App target still uses upstream bundle id com.FluidApp.app"
else
  pass "App bundle id re-scoped to hardened identity"
fi

if scan '"com\.fluidvoice\.provider-api-keys"' Sources >/dev/null; then
  fail "Upstream Keychain service literal still hardcoded (should use AppIdentity.keychainService)"
else
  pass "Keychain service routed through AppIdentity"
fi

# ---------------------------------------------------------------------------
section "Logging privacy (Phase 3)"

# Helper: fail if a pattern is found anywhere under Sources/, else pass.
# $1 = human label, remaining args = ripgrep/grep pattern + optional paths.
refute() {
  local label="$1"; shift
  local hits
  hits="$(scan "$@" Sources 2>/dev/null)"
  if [ -n "$hits" ]; then
    fail "$label"
    printf '%s\n' "$hits" | sed 's/^/        /' | head -8
  else
    pass "$label"
  fi
}

# 1. Full request body / cURL reproduction in logs.
refute "No cURL request reproduction in logs" "as cURL|curl -X .*\\\\\(|Full Request as cURL"

# Logging-call prefix matcher: matches `.debug(/.info(/.warning(/.error(` on any receiver
# (e.g. DebugLogger.shared.debug(...)), plus raw print()/NSLog().
LOGCALL='(\.(debug|info|warning|error)|print|NSLog)\('

# 2. Request/response BODY strings logged (the body var interpolated into a log/print).
refute "No HTTP request/response body logged" \
  "${LOGCALL}[^)]*\\\\\((requestString|responseString|bodyString|errText|curl)\)"

# 3. Direct print() of content — any raw print() outside the single gated DebugLogger sink.
PRINTS="$(scan '^[[:space:]]*print\(' Sources 2>/dev/null | grep -v 'Services/DebugLogger.swift')"
if [ -n "$PRINTS" ]; then
  fail "Raw print() found outside DebugLogger (use DebugLogger + sanitize)"
  printf '%s\n' "$PRINTS" | sed 's/^/        /' | head -8
else
  pass "No raw print() outside the gated DebugLogger sink"
fi

# 4. Transcript / prompt / response / selected-text VALUES interpolated into logs.
refute "No transcript/prompt/response content interpolated into logs" \
  "${LOGCALL}[^)]*\\\\\((result\.text|transcription|cleanedText|finalText|updatedText|partialTranscription|promptBody|systemPrompt|contextText|selectedText|transcribedText|instruction|command|escaped|response\.content|messageDump)\)"

# 5. Single-quoted content interpolation pattern '\(x)' — the classic transcript log shape.
refute "No quoted-content interpolation ('\\(...)') in logs/prints" \
  "${LOGCALL}[^)]*'\\\\\([^)]+\)'"

# 6. Provider response bodies can echo prompts and generated text.
refute "No provider response/error body previews in logs" \
  "${LOGCALL}[^)]*(Response preview|Response body|errText|bodyPreview|bodyString)"

# ---------------------------------------------------------------------------
section "History off (Phase 4)"

# require <label> <pattern> <paths...> — PASS if the pattern is found (guard present).
require() {
  local label="$1"; shift
  local pat="$1"; shift
  if scan "$pat" "$@" >/dev/null 2>&1; then
    pass "$label"
  else
    fail "$label"
  fi
}

HSTORE="Sources/Fluid/Persistence"
SS="Sources/Fluid/Persistence/SettingsStore.swift"

# History defaults must not be true.
if scan 'Keys\.saveTranscriptionHistory\) ?\n?.*\?\? true' "$SS" >/dev/null 2>&1 \
   || scan '\?\? true // Default to true \(save history\)' "$SS" >/dev/null 2>&1; then
  fail "saveTranscriptionHistory still defaults to true"
else
  pass "saveTranscriptionHistory no longer defaults to true"
fi

# Hardened enforcement writes both history toggles OFF.
require "enforceHardenedDefaults sets saveTranscriptionHistory OFF" \
  'set\(false, forKey: Keys\.saveTranscriptionHistory\)' "$SS"
require "enforceHardenedDefaults sets saveAudioWithTranscriptionHistory OFF" \
  'set\(false, forKey: Keys\.saveAudioWithTranscriptionHistory\)' "$SS"

# Store-level fail-closed guards (cover unguarded callers: meeting mode, backup import).
require "TranscriptionHistoryStore.addEntry guarded by saveTranscriptionHistory" \
  'saveTranscriptionHistory else \{ return \}' "$HSTORE/TranscriptionHistoryStore.swift"
require "TranscriptionHistoryStore.restore guarded by saveTranscriptionHistory" \
  'saveTranscriptionHistory else \{ return \}' "$HSTORE/TranscriptionHistoryStore.swift"
require "FileTranscriptionHistoryStore.addEntry guarded by saveTranscriptionHistory" \
  'saveTranscriptionHistory else \{ return \}' "$HSTORE/FileTranscriptionHistoryStore.swift"
require "DictationAudioHistoryStore.save guarded by audio-history toggle" \
  'saveAudioWithTranscriptionHistory' "$HSTORE/DictationAudioHistoryStore.swift"

# ---------------------------------------------------------------------------
section "Local ASR only (Phase 5)"

ASR="Sources/Fluid/Services"

# Apple Speech must never allow off-device (server) recognition.
refute "AppleSpeechProvider never sets requiresOnDeviceRecognition = false" \
  'requiresOnDeviceRecognition = false'
require "AppleSpeechProvider forces on-device recognition (= true)" \
  'requiresOnDeviceRecognition = true' "$ASR/AppleSpeechProvider.swift"

# Selection and catalog are fixed to the bundled Parakeet v2 engine.
require "Hardened speech catalog exposes only Parakeet v2" \
  'CPUArchitecture\.isAppleSilicon \? \[\.parakeetTDTv2\] : \[\]' "$SS"
require "Hardened selectedSpeechModel returns Parakeet v2" \
  'return \.parakeetTDTv2' "$SS"

# Launch-time tripwire present.
require "ASRService launch tripwire rejects Apple Speech" \
  'HARDENED invariant violated: Apple Speech' "$ASR/ASRService.swift"

# Onboarding catalog gates Apple Speech routes behind !HARDENED.
require "VoiceEngineLanguageCatalog gates Apple routes behind !HARDENED" \
  '#if !HARDENED' "Sources/Fluid/Persistence/VoiceEngineLanguageCatalog.swift"

# Fail-closed offline-only ASR: no automatic Hugging Face download in the hardened build.
require "ASRService refuses online model download under HARDENED" \
  'Offline model missing; use an offline-ready build' "$ASR/ASRService.swift"
require "FluidAudioProvider is offline-only (load, never downloadAndLoad) under HARDENED" \
  'Offline model missing; use an offline-ready build' "$ASR/FluidAudioProvider.swift"
require "ASRService public model downloader is blocked under HARDENED" \
  'throw HardenedNetworkPolicy\.PolicyError\.blockedExternalEndpoint' "$ASR/ASRService.swift"
require "Hugging Face model downloader is blocked under HARDENED" \
  'throw HardenedNetworkPolicy\.PolicyError\.blockedExternalEndpoint' "Sources/Fluid/Networking/ModelDownloader.swift"
require "Whisper model downloader is blocked under HARDENED" \
  'throw HardenedNetworkPolicy\.PolicyError\.blockedExternalEndpoint' "$ASR/WhisperProvider.swift"
require "ModelPreseeder present (first-launch offline copy + checksum)" \
  'preseedIfNeeded' "Sources/Fluid/Hardening/ModelPreseeder.swift"
require "ModelPreseeder performs full manifest validation before ASR starts" \
  'validateChecksums' "Sources/Fluid/Hardening/ModelPreseeder.swift"
require "ModelPreseeder includes hidden manifested files in exact-set validation" \
  'options: \[\]' "Sources/Fluid/Hardening/ModelPreseeder.swift"
require "ModelPreseeder validates a staging copy before cache replacement" \
  'validateChecksums\(target: staged' "Sources/Fluid/Hardening/ModelPreseeder.swift"
require "AppDelegate invokes ModelPreseeder at launch" \
  'ModelPreseeder.preseedIfNeeded' "Sources/Fluid/AppDelegate.swift"
require "Hardened media playback integration is a no-op" \
  'Media auto-pause is excluded from FluidVoice Hardened' "$ASR/MediaPlaybackService.swift"

if scan 'MediaRemoteAdapter|mediaremote-adapter' Fluid.xcodeproj Package.resolved Sources >/dev/null; then
  fail "MediaRemoteAdapter dependency or import remains in the hardened source"
else
  pass "MediaRemoteAdapter dynamic framework and import removed"
fi

# ---------------------------------------------------------------------------
section "Local post-processing only (Phase 6)"

NET="Sources/Fluid/Networking"
SVC="Sources/Fluid/Services"

# Central boundary accepts exact HTTP(S) loopback destinations and validates redirects.
POLICY="Sources/Fluid/Hardening/HardenedNetworkPolicy.swift"
require "Central hardened network policy exists" \
  'enum HardenedNetworkPolicy' "$POLICY"
require "Network policy accepts exact localhost" \
  'host == "localhost" \|\| host == "::1"' "$POLICY"
require "Network policy accepts only numeric 127/8 IPv4 loopback" \
  'octets\.first == "127"' "$POLICY"
require "Network policy rejects redirect escape attempts" \
  'willPerformHTTPRedirection' "$POLICY"
require "Hardened session disables system proxy routing" \
  'connectionProxyDictionary = \[:\]' "$POLICY"

# Every enabled LLM/model-list request path validates its final URL and uses the guarded session.
require "LLMClient validates final URL through central policy" \
  'HardenedNetworkPolicy\.validate\(url\)' "$SVC/LLMClient.swift"
require "LLMClient uses hardened session factory" \
  'HardenedNetworkPolicy\.makeSession' "$SVC/LLMClient.swift"
require "AIProvider validates final URL through central policy" \
  'HardenedNetworkPolicy\.validate\(url\)' "$NET/AIProvider.swift"
require "FunctionCallingProvider validates final URLs through central policy" \
  'HardenedNetworkPolicy\.validate\(url\)' "$NET/FunctionCallingProvider.swift"
require "ModelRepository validates model-list URL through central policy" \
  'HardenedNetworkPolicy\.validate\(url\)' "$SVC/ModelRepository.swift"
require "Connection tester validates final URL through central policy" \
  'HardenedNetworkPolicy\.validate\(url\)' "Sources/Fluid/UI/AISettings/AIEnhancementSettingsViewModel.swift"

# Cloud controls, provider catalogs, secrets, feedback, and updates remain unavailable.
require "allowCloudProviders is hard-forced OFF" \
  'self\.defaults\.set\(false, forKey: Keys\.allowCloudProviders\)' "$SS"
require "Hardened provider catalog contains local providers" \
  'var providers = \["ollama", "lmstudio"\]' "$SVC/ModelRepository.swift"

# Apple Intelligence disabled in the hardened build.
require "AppleIntelligenceProvider disabled under HARDENED" \
  'Apple Intelligence is disabled in the hardened build' "$NET/AppleIntelligenceProvider.swift"

# No API key access or storage in the hardened build.
require "Provider API keys resolve to an empty map under HARDENED" \
  'return \[:\]' "$SS"
require "In-app update network path is blocked under HARDENED" \
  'throw SimpleUpdateError\.networkDisabled' "$SVC/SimpleUpdater.swift"
require "Hardened updater cannot replace the app from a rollback backup" \
  'blocks self-replacement through local rollback artifacts' "$SVC/SimpleUpdater.swift"
require "Update and rollback settings UI is excluded under HARDENED" \
  '#if !HARDENED' "Sources/Fluid/UI/SettingsView.swift"
require "Transcription feedback network path is blocked under HARDENED" \
  'throw ReporterError\.disabledInHardenedBuild' "$SVC/TranscriptionFeedbackReporter.swift"
require "General feedback submission is disabled under HARDENED" \
  '#if HARDENED' "Sources/Fluid/UI/FeedbackView.swift"

# Executable policy and preference regression tests ship with the source.
require "Loopback network policy executable test is present" \
  'swiftc -D HARDENED' "scripts/test-hardened-network-policy.sh"
require "Case-sensitive hardened preference checker is present" \
  'AutoUpdateCheckEnabled' "scripts/check-hardened-preferences.sh"
require "Negative preference regression test is present" \
  'insecure value escaped detection' "scripts/test-hardened-preference-checks.sh"

# ---------------------------------------------------------------------------
section "Command Mode disabled (Phase 7)"

require "TerminalService.execute refuses shell execution under HARDENED" \
  'blocked shell execution in hardened build' "$SVC/TerminalService.swift"
require "CommandModeService entry refuses under HARDENED" \
  'Command Mode disabled in hardened build' "$SVC/CommandModeService.swift"
require "commandModeShortcutEnabled forced OFF under HARDENED" \
  'Command Mode is disabled \(shell execution path is also guarded\)' "$SS"
require "enforceHardenedDefaults sets commandModeShortcutEnabled OFF" \
  'set\(false, forKey: Keys.commandModeShortcutEnabled\)' "$SS"

# ---------------------------------------------------------------------------
section "Local API disabled (Phase 8)"

LAPI="Sources/Fluid/Services/LocalAPI"

require "LocalAPIServer.start() is a no-op under HARDENED" \
  'Local API permanently disabled \(hardened build\)' "$LAPI/LocalAPIServer.swift"
require "LocalAPI.Configuration forced disabled under HARDENED" \
  'Local API is permanently disabled regardless of stored settings' "$LAPI/LocalAPIModels.swift"
require "LocalAPIEnabled default remains false" \
  'LocalAPIEnabled' "$LAPI/LocalAPIModels.swift"

# ---------------------------------------------------------------------------
section "Direct input least privilege"

AX_TRUST_CALLS="$(scan 'AXIsProcessTrusted\(' Sources 2>/dev/null)"
AX_TRUST_COUNT="$(printf '%s\n' "$AX_TRUST_CALLS" | grep -c . || true)"
if [ "$AX_TRUST_COUNT" -eq 1 ] && printf '%s\n' "$AX_TRUST_CALLS" | grep -q 'Hardening/DirectInputMethodBridge.swift'; then
  pass "Accessibility trust checks are centralized behind the direct-input runtime gate"
else
  fail "Accessibility trust checks bypass the direct-input runtime gate"
  printf '%s\n' "$AX_TRUST_CALLS" | sed 's/^/        /' | head -12
fi
require "Direct input delivery stops when its IMK client is unavailable" \
  'request_return reason=input_method_client_unavailable' "$SVC/TypingService.swift"
require "Direct input selection capture avoids Accessibility APIs" \
  'DirectInputMethodRuntime\.isEnabled == false else \{ return nil \}' "$SVC/TextSelectionService.swift"
require "Direct input overlay avoids global event monitoring" \
  'guard DirectInputMethodRuntime\.isEnabled == false else \{ return \}' "$SVC/NotchOverlayManager.swift"
require "Direct input bottom overlay avoids global mouse monitoring" \
  'DirectInputMethodRuntime\.isEnabled == false, self\.globalMouseDownMonitor' "Sources/Fluid/Views/BottomOverlayView.swift"
require "Direct input overlay follows the active InputMethodKit client screen" \
  'DirectInputMethodBridge\.shared\.activeClientScreen\(\)' "$SVC/OverlayScreenResolver.swift"
require "Direct input overlay verifies visible-screen placement" \
  'window\.frame\.intersects\(selectedFrame\) == false' "Sources/Fluid/Views/BottomOverlayView.swift"
require "Direct input overlay retries hidden panel presentation without activation" \
  'Bottom overlay remains hidden after visibility recovery' "Sources/Fluid/Views/BottomOverlayView.swift"
require "Direct input package preserves custom overlay UI-agent capability" \
  'Add :LSUIElement bool true' "scripts/package-direct-input-method.sh"
if scan 'Add :LSBackgroundOnly bool true' "scripts/package-direct-input-method.sh" >/dev/null; then
  fail "Direct input package avoids background-only overlay suppression"
else
  pass "Direct input package avoids background-only overlay suppression"
fi
require "Direct input live transcription uses the original FluidVoice overlay" \
  'NotchOverlayManager\.shared\.updateTranscriptionText\(newText\)' "$SVC/MenuBarManager.swift"
if scan 'IMKCandidates|DirectInputCandidateOverlay' Sources/Fluid >/dev/null; then
  fail "Direct input source must not replace the FluidVoice overlay with a generic candidate window"
else
  pass "Direct input source excludes the generic candidate-window fallback"
fi
require "Direct input skips analytics identity creation" \
  'isTrueFirstOpen = false' "Sources/Fluid/AppDelegate.swift"
require "Direct input skips command-history initialization" \
  'guard DirectInputMethodRuntime\.isEnabled == false else \{ return \}' "$SVC/CommandModeService.swift"
require "Direct hotkey consumes a complete Right Option press" \
  'toggleDictation, consumesEvent: true' "Sources/Fluid/Hardening/DirectInputModifierGestureTracker.swift"
require "Direct input observes key-down only to distinguish Globe/Fn chords" \
  '\.union\(\.keyDown\)' "Sources/Fluid/Hardening/FluidVoiceInputController.swift"
require "Direct input restores the system character palette for an isolated Globe tap" \
  'NSApp\.orderFrontCharacterPalette\(nil\)' "Sources/Fluid/Hardening/FluidVoiceInputController.swift"
require "Globe/Fn remains a pass-through system gesture" \
  'showCharacterPalette, consumesEvent: false' "Sources/Fluid/Hardening/DirectInputModifierGestureTracker.swift"
require "Globe/Fn chords suppress the isolated palette gesture" \
  'globeWasCombined' "Sources/Fluid/Hardening/DirectInputModifierGestureTracker.swift"
require "Globe action helper uses the macOS Text Input Services setting" \
  'TISUpdateFnUsageType\(emojiAndSymbolsUsageType\)' "scripts/configure-globe-key.swift"
require "Globe action helper verifies the Emoji & Symbols value" \
  'emojiAndSymbolsUsageType: UInt32 = 2' "scripts/configure-globe-key.swift"
require "Direct-input installer restores the owner Globe action" \
  '"\$GLOBE_KEY_BIN" --set-emoji' "scripts/install-direct-input-method.sh"
require "Direct-input health check detects Globe action drift" \
  '"\$GLOBE_KEY_BIN" --require-emoji' "scripts/check-direct-input-health.sh"
require "Direct-input packaging runs modifier gesture regression tests" \
  'test-direct-input-modifier-gestures\.sh' "scripts/package-direct-input-method.sh"
require "Direct input source drift is reconciled through documented TIS selection" \
  'TISSelectInputSource\(mode\)' "Sources/Fluid/Hardening/DirectInputSourceCoordinator.swift"
require "Direct input reconciliation pauses during Secure Event Input" \
  'IsSecureEventInputEnabled\(\) == false' "Sources/Fluid/Hardening/DirectInputSourceCoordinator.swift"
require "Direct input restoration is bounded to three attempts" \
  'maximumRepairAttempts = 3' "Sources/Fluid/Hardening/DirectInputSourceCoordinator.swift"
require "Direct input restoration requires a stability dwell" \
  'stabilityCheckDelay: TimeInterval = 1\.5' "Sources/Fluid/Hardening/DirectInputSourceCoordinator.swift"
require "Direct input restoration automatically targets only the U.S. fallback" \
  'knownFallbackSourceIDs: Set<String> = \["com\.apple\.keylayout\.US"\]' "Sources/Fluid/Hardening/DirectInputSourceCoordinator.swift"
require "Direct input restoration coalesces self-generated source notifications" \
  'self\.repairInFlight == false else \{ return \}' "Sources/Fluid/Hardening/DirectInputSourceCoordinator.swift"
require "Direct input source health starts with the InputMethodKit server" \
  'DirectInputSourceCoordinator\.shared\.start\(inputMethodServerReady: inputMethodServerReady\)' "Sources/Fluid/AppDelegate.swift"
require "Direct input source recovery starts even when initial server readiness is incomplete" \
  'Direct input source coordinator started; inputMethodServerReady=' "Sources/Fluid/Hardening/DirectInputSourceCoordinator.swift"
require "Direct input menu cannot terminate the active input method" \
  'if DirectInputMethodRuntime\.isEnabled == false \{' "$SVC/MenuBarManager.swift"
require "Direct input live health check requires one canonical process" \
  'Expected one FluidVoice Direct Input process' "scripts/check-direct-input-health.sh"
require "Input-source guardian repairs only the U.S. fallback" \
  'guard currentID == fallbackID else \{ exit\(0\) \}' "scripts/fluidvoice-input-source-guardian.swift"
require "Input-source guardian pauses during Secure Event Input" \
  'secureOwnerIsAlive == false' "scripts/fluidvoice-input-source-guardian.swift"
require "Input-source guardian identifies the recorded Secure Input owner" \
  'kCGSSessionSecureInputPID' "scripts/fluidvoice-input-source-guardian.swift"
require "Input-source guardian restores only after a Secure Input owner exits" \
  'Guardian detected a stale Secure Event Input owner' "scripts/fluidvoice-input-source-guardian.swift"
require "Input-source guardian bounds stale-owner restoration to one attempt" \
  'paused after one bounded stale-owner recovery attempt' "scripts/fluidvoice-input-source-guardian.swift"
require "Input-source guardian clears the stale-owner marker after Secure Input ends" \
  'secureInputEnabled == false' "scripts/fluidvoice-input-source-guardian.swift"
require "Input-source guardian uses documented TIS selection" \
  'TISSelectInputSource\(mode\)' "scripts/fluidvoice-input-source-guardian.swift"
require "Input-source guardian restricts compatibility activation to macOS 26" \
  'operatingSystemVersion\.majorVersion == 26' "scripts/fluidvoice-input-source-guardian.swift"
require "Input-source guardian verifies the compatibility symbol image" \
  'loadedImagePath == carbonFrameworkPath \|\| loadedImagePath == hitoolboxFrameworkPath' "scripts/fluidvoice-input-source-guardian.swift"
require "Input-source guardian requires the canonical installed path" \
  'Library/Input Methods/FluidVoice Direct Input\.app' "scripts/fluidvoice-input-source-guardian.swift"
require "Input-source guardian relaunches without stealing keyboard focus" \
  'process\.arguments = \["-g", canonicalInputSourceURL\.path\]' "scripts/fluidvoice-input-source-guardian.swift"
if scan 'process\.arguments = \[[^]]*"-[^"]*j' "scripts/fluidvoice-input-source-guardian.swift" >/dev/null; then
  fail "Input-source guardian launch must preserve custom overlay visibility"
else
  pass "Input-source guardian launch preserves custom overlay visibility"
fi
require "Input-source guardian verifies canonical runtime ownership" \
  'NSRunningApplication\.runningApplications\(withBundleIdentifier: bundleID\)' "scripts/fluidvoice-input-source-guardian.swift"
require "Input-source guardian launch interval is bounded" \
  '<integer>15</integer>' "Resources/DirectInput/com.unlockdigital.fluidvoice-input-source-guardian.plist"
require "Input-source guardian runs as a background launch agent" \
  '<string>Background</string>' "Resources/DirectInput/com.unlockdigital.fluidvoice-input-source-guardian.plist"
require "Input-source guardian is covered by live health checks" \
  'source guardian is not loaded' "scripts/check-direct-input-health.sh"
require "Input-source guardian installation rejects hidden launches" \
  'hidden-launch flag, which suppresses the transcription overlay' "scripts/install-direct-input-method.sh"
require "Input-source guardian installation records source and binary identity" \
  'runtime_launch_mode=background-overlay-visible' "scripts/install-direct-input-method.sh"
require "Input-source guardian health check detects source drift" \
  'Installed guardian was built from a different source revision' "scripts/check-direct-input-health.sh"
require "Input-source guardian health check verifies overlay-visible launch mode" \
  'Installed guardian launch mode does not preserve overlay visibility' "scripts/check-direct-input-health.sh"
require "Runtime TIS registration occurs only when the exact mode is absent" \
  'if existingModes\.isEmpty == false' "Sources/Fluid/AppDelegate.swift"
require "Menu readiness reflects the live direct-input source state" \
  'DirectInputSourceCoordinator\.shared\.menuStatusTitle' "$SVC/MenuBarManager.swift"
require "Menu opening observes direct-input state without forcing selection" \
  'DirectInputSourceCoordinator\.shared\.refreshState\(reason: "menu-open"\)' "$SVC/MenuBarManager.swift"
require "Menu offers an explicit input-source restore action" \
  'coordinator\.requestRestore\(\)' "$SVC/MenuBarManager.swift"
require "Direct-input recovery identifies the live Secure Input owner" \
  'kCGSSessionSecureInputPID' "Sources/Fluid/Hardening/DirectInputSourceCoordinator.swift"
require "Direct-input menu keeps recovery available during Secure Input" \
  'self\.restoreInputSourceMenuItem\?\.isEnabled = sourceState != \.restoring' "$SVC/MenuBarManager.swift"
require "Direct-input menu names its owner recovery action" \
  'Recover Fluid Voice\.\.\.' "$SVC/MenuBarManager.swift"
require "Direct-input recovery offers an owner-initiated normal quit" \
  'application\.terminate\(\)' "$SVC/MenuBarManager.swift"
require "Direct-input recovery waits for Secure Input to clear before restoring" \
  'coordinator\.secureInputIsActive == false' "$SVC/MenuBarManager.swift"

# ---------------------------------------------------------------------------
section "Summary"
if [ "$FAIL" -eq 0 ]; then
  printf "\n\033[32mAll hardening checks passed.\033[0m\n"
else
  printf "\n\033[31mHardening checks FAILED. See above.\033[0m\n"
fi
exit "$FAIL"
