# Strict local dictation profile

The maintained profile keeps microphone audio and text local, uses verified local ASR, inserts the final result once, and separates explicit model/dependency setup from runtime. Telemetry, cloud ASR/enhancement, updates, content logging/history, Command Mode and the Local API remain disabled. AI enhancement, prompts and rewrite paths stay off in the initial hardened profile.

Mac and Windows retain native boundaries: InputMethodKit with microphone-only signed capability on the Mac direct route; Win32 hotkeys and Unicode SendInput in the Windows adaptation. Model formats, keyboard codes, permissions, UI, services and installers remain platform-specific. The Mac code's loopback allowlist is distinct from an enabled enhancement feature.

Acceptance uses synthetic phrases and fixtures for model failure/integrity, shortcuts, provisional/final text, focus/target changes, cleanup and privacy controls. Native physical tests cover insertion, visible UI, devices, login/sleep and recovery. Runtime diagnostics, OS crash handling, screen capture/accessibility observers and the destination application are documented trust boundaries. A source scan supplies evidence about the checked patterns; runtime acceptance requires observed native behavior.

M5 dictionary learning and private enhancement remain separate design/recovery questions. No live preferences or vocabulary/history content are imported between machines.
