# FluidVoice Hardened Contributor Instructions

Read HANDOFF.md before changing Mac lifecycle, hotkeys, text insertion, signing or installation. Read platform-specific instructions before editing a native implementation.

- Preserve working installations, user state, model caches and source changes. Build candidates in isolated output directories.
- Keep the Mac Direct Input runtime microphone-only: InputMethodKit insertion, external networking disabled, history/content logs/cloud/Command Mode/Local API disabled.
- Preserve the original horizontal live-text panel and guardian launch with open -g.
- Keep OS-version activation restrictions until a separate qualification demonstrates a supported route.
- Distinguish source scans, fixture tests, builds and physical platform acceptance in reports.
- Run the relevant deterministic tests for a change. Hardware/installation trials require an explicitly scoped environment.
- Write direct affirmative prose and preserve upstream credit, GPL notices and independent Windows provenance.
