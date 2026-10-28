# FluidVoice Local for Windows

**Private voice input for the applications you choose.**

Local, privacy-preserving transcription and dictation brings spoken instructions, LLM prompts and drafts into everyday Windows applications. The hardened design keeps recognition on this computer and excludes cloud transcription, enhancement, telemetry and retained dictation history.

The [FluidVoice Local repository](https://github.com/unlockdigital/fluidvoice-local) includes this independently maintained Windows adaptation. It provides local dictation using WinForms and Whisper.net. It shares the FluidVoice name and a ported geometric mark with [altic-dev/FluidVoice](https://github.com/altic-dev/FluidVoice); this project is maintained independently. See [NOTICE](NOTICE) and [PROVENANCE.md](PROVENANCE.md) for credit, license, and source history.

Press F3 to start and stop dictation; Ctrl+Alt+Space is the fallback. The overlay displays a temporary preview while recognition runs locally, and the final transcription is inserted into the original target using Unicode input. Both hotkeys must register successfully. Capture uses the default device and English. The tray menu offers dictation, privacy status, and exit.

The production profile keeps audio and previews in memory, avoids clipboard output and app-authored network, telemetry, update, cloud, history, server and logging features, and checks the model hash before loading. Screen capture, accessibility software, the destination application, Windows Error Reporting, and same-user .NET diagnostics remain privacy boundaries. See [security architecture](docs/WINDOWS_SECURITY_ARCHITECTURE.md).

## Why we maintain this adaptation

The goal is convenient voice input across ordinary editable desktop targets with an explicit local-processing boundary. Speak into an editor, browser text field, LLM chat or coding agent while the audio-to-text step stays local. The receiving application's storage, networking and submission behavior governs the inserted text afterward. Local LLM destinations can keep that next step local too.

Win32 Unicode insertion operates in the current user's ordinary desktop session. Elevated applications and secure desktops have different access boundaries; see the security architecture and qualification gates.

## Source and build

- `src/FluidVoice.Core`: audio capture, local recognition and model verification.
- `src/FluidVoice.App`: tray app, hotkeys, overlay and text insertion.
- `src/FluidVoice.Verify`: offline verification utility; some modes capture audio or run inference.
- `scripts`: build, model provisioning, installation, firewall and privacy checks.
- `tests/logic`: recovered synthetic text and PCM fixtures.

Open `FluidVoice.Local.Windows.slnx` for the Windows solution. The source targets Windows x64 and .NET 9. The observed build used SDK 9.0.316 and self-contained runtime 9.0.18; the SDK and runtime packs are not fully pinned. .NET 9 reaches end of support on 2026-11-10. A runtime upgrade is a separate task. On a designated Windows development host, inspect the scripts and use `scripts/Build-FluidVoice.ps1` with existing dependencies; `scripts/Get-BuildDependencies.ps1` downloads an SDK when needed. Build output belongs in an isolated directory. Installation and firewall scripts change host state and require a separately scoped installation plan.

The pinned model is `ggml-large-v3-turbo-q5_0.bin`, 574,041,195 bytes, SHA-256 `394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2`, revision `98aa99a0a9db05ae2342309f5096248665f7cba3`. The model and runtime binaries are excluded. See `scripts/Get-ApprovedModel.ps1` for the pinned source.

On 2026-10-27, an agent reported successful offline locked restores and isolated publishes of the pre-rename FluidVoice Hardened build, with all 299 rebuilt publish files matching the then-installed payload. That historical comparison applies to the pre-rename build; the renamed sources require a fresh isolated publish and validation. The logic harness build failed before any cases ran. Startup and firewall checks failed inside the sandbox; actual host state remains unknown. The installed build was unsigned. No fresh microphone, inference, UI, or end-to-end acceptance was performed. Future binary distribution requires native CUDA, model, and dependency licensing review, signing decisions, and Windows host acceptance.

## Windows rename and deployment

The current product is **FluidVoice Local for Windows**, with app assembly and executable `FluidVoice Local` / `FluidVoice Local.exe`. Installation and privacy-check scripts default to `%LOCALAPPDATA%\Programs\FluidVoice Local`; the firewall script defaults to that directory's new executable. Existing `FluidVoice Hardened` directories and payloads remain preservation anchors. Build outputs stay in `.artifacts/publish` and `.artifacts/verify`; use a fresh publish so stale files from the previous assembly name are cleared by the build script.

Compatibility identities remain `FluidVoice.Hardened` / `FluidVoice.Hardened.Windows` namespaces, the manifest assembly identity, `Local\FluidVoiceHardenedWindows` mutex, hidden hotkey-window captions, and the `FluidVoiceHardened` HKCU Run value. Project paths, Core/Verify assembly names and overlay control name also stay stable. The logic fixture loads the renamed app assembly while retaining the original type namespace. Versions remain unchanged; identify a renamed candidate with its publish hashes and product metadata.

A future, separately scoped Windows deployment must account for these path changes:

- Preserve the prior directory, model cache, startup value and firewall configuration, and quit the prior process through the approved host plan. The shared mutex prevents simultaneous old/new instances; an old process still running makes the new process exit. The installer stops processes named `FluidVoice Local` and leaves the legacy process alone.
- Installing to the new default preserves the old directory and repoints the existing `FluidVoiceHardened` Run value to the quoted new executable path. This replaces that login entry. The installer enables login startup before the separate firewall script runs; complete firewall provisioning in the same session before logoff, reboot or application launch. An explicit `-InstallDirectory` changes the target; use a preservation and rollback plan before selecting any existing directory. Directory rollback in the installer covers its selected directory; restoring prior startup and firewall state belongs in the deployment plan.
- Firewall blocks are scoped to an exact executable path. Legacy rules for `FluidVoice Hardened.exe` cover the legacy executable. Configure and verify **FluidVoice Local - Block Inbound/Outbound** for the new path before launch. The firewall script manages the new display names and preserves the legacy rules. Pass matching `-InstallDirectory` and `-Executable` values when using a custom destination. Reusing the new rule names for another destination replaces those rules, so each candidate needs a deliberate firewall plan.
- Validate the new payload, policy, integrity manifest, startup path and exact inbound/outbound blocks with the matching privacy script under that host plan, then perform the Windows acceptance checks. Rollback must restore the saved startup path as well as its matching payload and firewall coverage.

The rename review used source-only consistency, XML/JSON and preservation checks. The review host had neither .NET nor PowerShell, so compilation, PowerShell parsing, fixture execution and Windows host acceptance remain pending. Installation, application launch, audio capture, inference, registry and firewall operations were excluded from this review.
