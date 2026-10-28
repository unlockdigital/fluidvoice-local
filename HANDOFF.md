# FluidVoice Hardened Development Handoff

This community fork preserves the owner's local-first Mac implementation on real altic-dev/FluidVoice ancestry. The source baseline is fba0d3156037ee4ddeb5b8e34d1faf838ad37c7b. Local hardening and InputMethodKit changes were imported from 7f4850cc61ca3594e552031cfe38e240b914bb1f plus its preserved working files.

The working installations remain separate preservation anchors. New builds belong in build/ or another isolated output path. Keep runtime permission and input-source state preserved while developing.

The Mac Direct Input path uses Right Option press/release to toggle dictation, local Parakeet ASR and IMKTextInput insertion. The signed direct-input capability is microphone input only. Preserve disabled Accessibility/Input Monitoring/Apple Events paths and the external-network/history/content-log/cloud/Command Mode/Local API boundary.

The live transcription UI uses the original horizontal FluidVoice panel. Preserve LSUIElement=true, the nonactivating panel route and guardian open -g behavior. Hidden launch with -j suppresses the panel.

The activation compatibility helper currently accepts macOS 26. macOS 27 qualification is a separate work stream. Keep that guard until a documented route and physical test prove the candidate.

Before any later installation replacement, archive and verify the working bundle outside the directory scanned by Input Methods, preserve startup/keyboard configuration, and verify rollback. TCC resets require explicit user authorization and a tested recovery path.

Physical release acceptance requires Right Option start/stop, a unique fake phrase inserted once at the caret, the original horizontal panel with live text, and post-test checks of permissions, sockets, process classification and crashes. Repeat through relaunch/login and Secure Input recovery. Compilation and unit fixtures establish their own narrower results.

Detailed original operational records remain in the owner's private preserved handoff. Public provenance and current validation are recorded in PROVENANCE.md and docs/.
