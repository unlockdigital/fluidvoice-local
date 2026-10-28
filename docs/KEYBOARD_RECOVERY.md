# Keyboard pass-through recovery candidate

The owner reported ordinary typing failures in Brave and Finder while FluidVoice was selected; T3 continued accepting physical typing. Selecting the U.S. keyboard and stopping the FluidVoice runtime restored typing in all three applications. A fresh instance of the original executable, with the guardian paused, reproduced the failure. Restarting the per-user InputMethodKit service also left the Brave/Finder failure reproducible.

This local repair branch starts at the published `e20b0b5` baseline. It changes the input controller to request modifier-change events only. Ordinary key-down and key-up events stay with the host application's native text handling. Right Option retains its existing full-press toggle. The controller leaves Globe behavior to macOS's existing Emoji & Symbols setting, avoiding an application fallback that depends on observing ordinary keys to distinguish Fn chords.

Parakeet v2, model and dependency pins, ASR processing, insertion behavior, the horizontal panel, stable identifiers and microphone-only capabilities retain the baseline implementation. The separate stop-target/caption feature branch remains preserved and deferred.

## Evidence and remaining acceptance

The keyboard-routing fixture compiles the actual production event methods with the production modifier tracker. In-memory events cover ordinary letters, editing keys, shortcuts, Right Option, native Fn handling and typing after a toggle. The runner also typechecks the real controller/bridge against the installed InputMethodKit SDK. These fixtures establish the event contract; they require physical application acceptance.

The repair candidate requires physical typing and deletion in T3, Brave and Finder before any hotkey; then a synthetic dictation and another physical typing check. Check Right Option, Globe/Emoji and Fn shortcuts, and observe a single canonical process. Keep automatic re-selection paused until typing and dictation both pass. A failed case returns to U.S. input with FluidVoice stopped. Preserve original bundles and preference snapshots throughout. Publication remains held until qualification.
