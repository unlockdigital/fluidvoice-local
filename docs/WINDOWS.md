# Windows setup and use

[Project home](../README.md) · [Mac guide](MACOS.md) · [Windows technical reference](../platforms/windows/README.md)

FluidVoice Local for Windows is an independent C# / WinForms implementation included in `platforms/windows`. It uses local Whisper recognition, Win32 hotkeys and Unicode text insertion. Its [provenance](../platforms/windows/PROVENANCE.md), [GPL license](../platforms/windows/LICENSE), [notices](../platforms/windows/NOTICE) and synthetic tests are included in this repository.

## Requirements and status

- Windows x64 development host with PowerShell and a .NET 9 SDK.
- Space for build outputs, self-contained runtime dependencies and the approximately 574 MB approved model.
- CUDA 12 runtime support for the GPU route; the dependency set also includes a CPU fallback.
- Network access during explicit dependency and model preparation. Recognition uses the local model.

This is experimental source. Runtime migration, logic-harness repair and fresh Windows host acceptance remain open. CI builds the application source with SDK 9.0.316. The dependency helper selects the .NET 9 GA channel, so it has a broader SDK selection than CI. Review the [technical reference](../platforms/windows/README.md) for runtime lifecycle, deployment compatibility and historical build evidence.

## Prepare and build

Use a fresh development checkout to preserve existing installations, models and build artifacts:

```powershell
git clone --branch hardened https://github.com/unlockdigital/fluidvoice-local.git
Set-Location fluidvoice-local\platforms\windows
.\scripts\Get-BuildDependencies.ps1
.\scripts\Build-FluidVoice.ps1
```

Review scripts before execution. The dependency helper downloads a checkout-local SDK into `.tools\dotnet`. The build script uses locked package restores and publishes the app and verifier to `.artifacts\publish` and `.artifacts\verify`. It clears both output directories before building. Run it in the fresh checkout; preserve any existing outputs you need first.

Open `FluidVoice.Local.Windows.slnx` for the solution. The application executable is **FluidVoice Local.exe**. Core/Verify assembly names and internal compatibility identifiers retain their established names.

## Prepare the model

From `platforms\windows`:

```powershell
.\scripts\Get-ApprovedModel.ps1
```

The helper downloads `ggml-large-v3-turbo-q5_0.bin` into `vendor\models` from a pinned revision and verifies its size and SHA-256. An unapproved existing destination is preserved and reported as a failure. The expected hash is `394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2`. Model and runtime payloads stay outside the public source tree.

## Install a qualified trial candidate

Installation, startup and firewall changes belong to a separately scoped Windows trial. Preserve the old application directory, model cache, HKCU startup value and executable-specific firewall rules, and establish how to restore them. Quit the prior application through the trial plan: the old and new names share a single-instance mutex.

From `platforms\windows`, in the intended user's session:

```powershell
.\scripts\Install-FluidVoice.ps1
.\scripts\Set-FluidVoiceFirewall.ps1
.\scripts\Test-FluidVoicePrivacy.ps1
```

Complete and verify firewall provisioning in the same session before launching, logging off or rebooting. The installer enables login startup before the firewall step; the firewall script requests administrator elevation. Keep that elevation associated with the intended executable path.

The default destination is `%LOCALAPPDATA%\Programs\FluidVoice Local`. The installer copies the model, writes policy and integrity manifests, and repoints the existing `FluidVoiceHardened` HKCU Run value. Directory rollback covers the chosen installation directory; the trial plan must also restore startup and firewall state when needed.

The firewall script configures inbound and outbound blocks for the exact **FluidVoice Local.exe** path. Legacy rules continue to cover the legacy path. For a custom destination, pass the same installation path to the installer and privacy checker with `-InstallDirectory`, and its full executable path to the firewall script with `-Executable`. Keep the prior payload and rules preserved. See [rename and deployment details](../platforms/windows/README.md#windows-rename-and-deployment).

## Dictate on Windows

After installation and privacy checks under the trial plan:

1. Launch **FluidVoice Local.exe** in the ordinary user's desktop session. Both hotkeys must register successfully.
2. Focus an editable field and place the caret at the intended insertion point.
3. Press **F3** to start recording; **Ctrl+Alt+Space** is the fallback toggle.
4. Speak English into the default microphone. The overlay shows a temporary live preview.
5. Press the toggle again to stop. The final local transcription is inserted into the original target using Unicode input.

The tray menu provides dictation, privacy status and exit. Audio and previews stay in memory and are cleared with the session. The receiving application controls storage and transmission of inserted text.

Use ordinary desktop targets for qualification. Windows UIPI restricts insertion into elevated applications; secure desktops, login screens and other users' sessions have separate access boundaries. OS crash handling, same-user .NET diagnostics and screen capture remain documented privacy boundaries in the [security architecture](../platforms/windows/docs/WINDOWS_SECURITY_ARCHITECTURE.md).

## Verification and remaining acceptance

The GitHub workflow performs a locked restore and Release application source build on Windows. Synthetic logic fixtures live in `tests\logic`; their harness requires repair before its execution can be counted as passed.

A qualified host trial also verifies model and installed-file integrity, startup path, exact firewall coverage, sockets, F3 and fallback behavior, default microphone capture, local inference, overlay lifecycle and insertion into approved targets. Keep source scans, fixture execution, builds and physical acceptance results separately recorded. The historical installed-payload comparison describes the pre-rename app; a renamed candidate needs fresh build and host evidence.
