# FluidVoice Local

<img src="assets/branding/mark.svg" width="72" height="72" alt="FluidVoice Local microphone and privacy shield">

**Private voice input for Mac and Windows.**

Speak into editors, notes, browser fields and coding tools. FluidVoice Local transcribes speech on your computer and inserts the text into the application you choose. Cloud processing, telemetry and retained dictation history stay disabled. The receiving application controls how it stores and sends the inserted text.

Maintained by Unlock Digital at **[unlockdigital/fluidvoice-local](https://github.com/unlockdigital/fluidvoice-local)**. The `main` branch contains both native implementations.

## Choose your platform

| | Mac | Windows |
| --- | --- | --- |
| Source | Swift · Apple Silicon | C# / WinForms · Windows x64 |
| Local recognition | Parakeet v2 | Whisper large-v3-turbo |
| Dictation control | Right Option in the Direct Input candidate | F3; Ctrl+Alt+Space fallback |
| Text insertion | InputMethodKit | Win32 Unicode input |
| Start here | **[Mac setup and use](docs/MACOS.md)** | **[Windows setup and use](docs/WINDOWS.md)** |

**Current status: source preview.** Source checks and build evidence are recorded in [validation](docs/VALIDATION.md). Fresh Mac Direct Input acceptance and Windows runtime, logic-harness and host qualification remain open. Supported binary distribution is a separate milestone. Existing working installations remain preservation anchors during candidate development.

## Documentation

- [Mac setup and use](docs/MACOS.md) — requirements, build, models, installation boundaries and dictation.
- [Windows setup and use](docs/WINDOWS.md) — requirements, build, models, installation, firewall coverage and dictation.
- [Build and packaging reference](docs/BUILDING.md) · [Model attribution](models/README.md).
- [Validation and remaining work](docs/VALIDATION.md) · [Keyboard recovery](docs/KEYBOARD_RECOVERY.md) · [macOS 27 qualification](docs/MACOS_27_QUALIFICATION.md).
- [Contributing](CONTRIBUTING.md) · [Maintainer handoff](HANDOFF.md) · [Repository consolidation](docs/REPOSITORY_CONSOLIDATION.md).

## Credit and license

FluidVoice Local is an independently maintained GPLv3 fork of [FluidVoice](https://github.com/altic-dev/FluidVoice), created by altic-dev and its contributors. The Windows adaptation has its own [source provenance](platforms/windows/PROVENANCE.md) and [notices](platforms/windows/NOTICE).

[GPLv3](LICENSE) · [Project provenance](PROVENANCE.md) · [Third-party notices](THIRD_PARTY_NOTICES.md) · [Naming and compatibility](docs/BRANDING.md).
