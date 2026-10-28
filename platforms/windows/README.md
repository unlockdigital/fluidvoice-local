# FluidVoice Hardened for Windows

This independently maintained Windows adaptation provides local dictation using WinForms and Whisper.net. It shares the FluidVoice name and a ported geometric mark with [altic-dev/FluidVoice](https://github.com/altic-dev/FluidVoice); this project is maintained independently. See [NOTICE](NOTICE) and [PROVENANCE.md](PROVENANCE.md) for credit, license, and source history.

Press F3 to start and stop dictation; Ctrl+Alt+Space is the fallback. The overlay displays a temporary preview while recognition runs locally, and the final transcription is inserted into the original target using Unicode input. Both hotkeys must register successfully. Capture uses the default device and English. The tray menu offers dictation, privacy status, and exit.

The production profile keeps audio and previews in memory, avoids clipboard output and app-authored network, telemetry, update, cloud, history, server and logging features, and checks the model hash before loading. Screen capture, accessibility software, the destination application, Windows Error Reporting, and same-user .NET diagnostics remain privacy boundaries. See [security architecture](docs/WINDOWS_SECURITY_ARCHITECTURE.md).

## Source and build

- `src/FluidVoice.Core`: audio capture, local recognition and model verification.
- `src/FluidVoice.App`: tray app, hotkeys, overlay and text insertion.
- `src/FluidVoice.Verify`: offline verification utility; some modes capture audio or run inference.
- `scripts`: build, model provisioning, installation, firewall and privacy checks.
- `tests/logic`: recovered synthetic text and PCM fixtures.

The source targets Windows x64 and .NET 9. The observed build used SDK 9.0.316 and self-contained runtime 9.0.18; the SDK and runtime packs are not fully pinned. .NET 9 reaches end of support on 2026-11-10. A runtime upgrade is a separate task. On a designated Windows development host, inspect the scripts and use `scripts/Build-FluidVoice.ps1` with existing dependencies; `scripts/Get-BuildDependencies.ps1` downloads an SDK when needed. Build output belongs in an isolated directory. Installation and firewall scripts change host state and require a separately scoped installation plan.

The pinned model is `ggml-large-v3-turbo-q5_0.bin`, 574,041,195 bytes, SHA-256 `394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2`, revision `98aa99a0a9db05ae2342309f5096248665f7cba3`. The model and runtime binaries are excluded. See `scripts/Get-ApprovedModel.ps1` for the pinned source.

On 2026-10-27, an agent reported successful offline locked restores and isolated publishes, with all 299 rebuilt publish files matching the installed payload. The logic harness build failed before any cases ran. Startup and firewall checks failed inside the sandbox; actual host state remains unknown. The installed build was unsigned. No fresh microphone, inference, UI, or end-to-end acceptance was performed. Future binary distribution requires native CUDA, model, and dependency licensing review, signing decisions, and Windows host acceptance.
