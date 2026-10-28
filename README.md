# FluidVoice Hardened

FluidVoice Hardened is an independently maintained GPLv3 fork of [FluidVoice](https://github.com/altic-dev/FluidVoice), created by altic-dev and its contributors. Unlock Digital maintains a strict local-dictation profile and native Mac and Windows implementations. Original notices and [GPLv3](LICENSE) are preserved. See [provenance](PROVENANCE.md) and [third-party notices](THIRD_PARTY_NOTICES.md).

The `hardened` branch is the product source branch. This is a source preview; platform acceptance and supported binary distribution are separate milestones.

## Platform status

| Platform | Implementation | Current status |
| --- | --- | --- |
| Apple Silicon / macOS 26 | Native Swift, local Parakeet v2, InputMethodKit direct insertion and Right Option toggle | Preserved working source; public Release build and deterministic checks verified on M2 Max. New physical candidate acceptance remains pending |
| Windows x64 | Independent C# WinForms adaptation, local Whisper, Win32 hotkeys and Unicode insertion | [Source imported with independent provenance and GPLv3 licensing](platforms/windows/README.md). Runtime upgrade, test-harness repair and host acceptance remain open |
| macOS 27 / M5 | Separate qualification track for this fork | [Read-only probe and acceptance guide](docs/MACOS_27_QUALIFICATION.md). The supplied M5 package was public reference/configuration evidence; actual installed source remains unknown |

## Privacy profile

The Mac hardened build selects local Parakeet transcription and enforces disabled telemetry, cloud ASR/enhancement, content logs, transcript/audio history, Command Mode, the Local API and update checks. Prompt/rewrite and AI enhancement paths remain off. The direct-input bundle uses InputMethodKit and microphone-only signed capability, preserving the original horizontal live-text panel. Dependencies and model setup use network access during explicit preparation; runtime model acquisition fails closed.

The [Windows subtree](platforms/windows/docs/WINDOWS_SECURITY_ARCHITECTURE.md) documents its separate native boundary. OS crash handling, runtime diagnostics, on-screen text and the destination application remain part of the threat model. Source scans and fixture tests support specific checks; physical privacy acceptance requires the native release matrix.

## Build the Mac source

Use an Apple Silicon Mac with full Xcode 26.2 and its command-line tools selected. Dependency revisions are recorded in the identical root and Xcode `Package.resolved` files. The Xcode app-bundle route is the supported build entrypoint. `Package.swift` describes the same dependency pins and source path; it is not the distribution bundle route.

```sh
./build.sh resolve
./build.sh unsigned
```

`./build.sh` uses ad-hoc signing by default; `SIGN_IDENTITY` can select an authorized local identity. Builds stay under `build/` and are never launched or installed by this command. A compile-only app does not yet contain the offline model. See [build and packaging](docs/BUILDING.md).

## Verification

```sh
bash scripts/verify-hardening.sh
bash scripts/test-hardened-network-policy.sh
bash scripts/test-hardened-preference-checks.sh
bash scripts/test-direct-input-modifier-gestures.sh
python3 scripts/test-pinned-model.py
```

These use synthetic fixtures and isolated outputs. The preference fixture writes a temporary test domain instead of the live app domain. [Validation and remaining gates](docs/VALIDATION.md) distinguishes source checks, builds, packaging and physical acceptance.

## Offline model and packaging

The approved CoreML model is [FluidInference Parakeet TDT v2](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml), based on NVIDIA Parakeet and converted by FluidInference under CC BY 4.0. This repository includes its approved 55-file hash manifest and an immutable source revision, while weights stay excluded from Git.

```sh
# Explicit setup window; downloads approximately 2.6 GB into vendor/.
./scripts/fetch-parakeet-model.sh
# Build separate offline-ready artifacts; these commands do not install them.
./scripts/package-release.sh
./scripts/package-direct-input-method.sh
```

A separately supplied model can be checked with `python3 scripts/fetch-pinned-model.py --verify-only /path/to/model`. The fetch uses curl and Python's standard library, an immutable revision and committed SHA-256 values. It preserves an invalid existing destination and reports failure. Packaging copies only the approved files. [Model attribution and source](models/README.md) records the revision.

## Installation and compatibility

Keep a working installation preserved while validating a new candidate. Read [HANDOFF.md](HANDOFF.md), [build/installation boundaries](docs/BUILDING.md) and the [macOS 27 guide](docs/MACOS_27_QUALIFICATION.md) first. The current compatibility helper accepts macOS 26 only. Installation scripts alter input-source registration, keyboard/startup state and the per-user bundle; use a scoped trial with a verified rollback artifact. No supported binary release is published from this source preview.

## Contributing

Use [CONTRIBUTING.md](CONTRIBUTING.md). Focused reusable fixes can also be proposed to [FluidVoice upstream](https://github.com/altic-dev/FluidVoice/blob/main/CONTRIBUTING.md) after current-upstream reproduction and its issue/discussion requirements. Keep platform privacy and provenance boundaries explicit.
