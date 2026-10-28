# Windows security architecture

FluidVoice Local for Windows implements local push-to-dictate using a separate C#/.NET implementation. See [provenance](../PROVENANCE.md) for its source history and upstream mark attribution.

## Data flow

1. `F3` invokes the primary Win32 registered hotkey;
   `Ctrl+Alt+Space` remains a fallback. Both registrations suppress key-repeat toggles.
2. NAudio captures 16 kHz mono PCM from Windows' default input device.
3. A scalar RMS volume level drives the short-lived waveform overlay. While recording,
   the latest samples in a fixed 12-second circular PCM buffer are decoded locally at
   intervals to produce a provisional transcript preview.
4. PCM, rolling sample copies, and provisional text are held only in managed memory; no
   temporary audio or transcript file is created. The circular buffer is overwritten
   in place and zeroed at teardown; inference sample copies are zeroed after each
   preview pass.
5. Whisper.net invokes a pinned whisper.cpp CUDA 12 runtime (CPU fallback included).
   Preview and final inference are serialized so they never compete for the model.
6. The verified `large-v3-turbo-q5_0` model produces both provisional text and the
   authoritative final text locally. Only the final full-recording result is eligible
   for insertion.
7. `SendInput` inserts final Unicode text into the original focused window.
8. Audio buffers are zeroed, and all transcript UI state is cleared when the overlay
   dismisses; no audio, transcript, prompt, or history is saved.

There is no app-authored network or IPC step in the dictation data flow. The self-contained
.NET runtime exposes its default same-user diagnostic IPC endpoint unless the process is
launched with `DOTNET_EnableDiagnostics=0`; diagnostic clients running as the same user or
an administrator can request traces or dumps containing in-memory process data. This is a
local runtime observability boundary, not FluidVoice telemetry. See Microsoft's
[diagnostic-port documentation](https://learn.microsoft.com/dotnet/core/diagnostics/diagnostic-port).

The recording UI is a borderless, non-activating WinForms overlay positioned on the
target application's monitor. Its fixed bottom control rail shows a FluidVoice-derived geometric mark, elapsed time, a live level waveform, and
recording/processing/success/error states. Above it, a transient transcript pane grows
upward by wrapped-line tiers, follows the newest text at a five-line cap, and supports
mouse-wheel scrollback. The latest provisional line is visually distinguished until the
final pass completes. Ordinary Windows notification balloons are not used for the
dictation workflow. The mark geometry is ported from FluidVoice's GPLv3
`FluidIcon.swift`; no remote asset or runtime network request is used.

The overlay caches wrapped transcript lines between content, width, and DPI changes so
animation does not repeatedly process the entire transcript. When a user scrolls away
from the live tail, incoming words preserve the viewed historical anchor. The stop control
keeps a 36-DIP visual circle while exposing a 44-DIP pointer target with hover and press
feedback.

Displaying live text intentionally makes the current dictation visible on screen and to
ordinary local screen-capture/accessibility software while the overlay exists. It does
not create transcript history: preview strings remain process-local, are replaced as
recognition stabilizes, and are cleared on dismissal, abort, and disposal.

## Release gates

| Privacy goal | Windows implementation |
|---|---|
| Local recognition | Local Whisper large-v3-turbo-q5_0 via CUDA 12; CPU fallback. |
| Dictation content local | In-memory audio and transient UI transcript; direct local keystroke injection of final text only. |
| Analytics absent | No analytics package, configuration, or code. |
| History off | No history store or write implementation. |
| Debug logging off | Trace listeners removed; no app log implementation. |
| Post-processing/cloud off | No post-processing or provider implementation. |
| Apple Speech unreachable | Not applicable; no Windows/cloud speech API is used. |
| Command Mode off | No command parser or process execution implementation. |
| Local API off | No server/listener implementation; port 47733 checked. |
| Updates/feedback off | No updater or feedback implementation. |
| Network boundary | Required deployment control: exact executable inbound/outbound block rules; current host state remains unverified. |
| Integrity | Pinned SHA-256 is checked before the model is loaded on every launch. |
| Managed runtime | Self-contained .NET / Windows Desktop 9.0.18 runtime in the installed payload. |

## Threat boundaries

- The app runs as the signed-in user and intentionally does not elevate.
- Windows UIPI prevents a normal user process from inserting text into elevated apps.
  Running dictation permanently elevated would enlarge the attack surface, so that is
  not enabled.
- The build is not Authenticode-signed because no user-controlled code-signing
  certificate was supplied. File and model hashes provide integrity evidence but not
  publisher identity.
- Windows Firewall rules require administrator rights to install. The 2026-10-27 sandbox checks failed; actual host rule state remains unknown.
- Windows Error Reporting is an operating-system service outside the executable-scoped
  firewall rules. An unhandled crash could be handled by `WerFault.exe` under system policy. See Microsoft's
  [WER consent documentation](https://learn.microsoft.com/windows-hardware/customize/desktop/unattend/microsoft-windows-errorreportingcore-defaultconsent).
- The default local .NET diagnostic pipe is available to same-user and administrator
  tooling. Disabling it requires setting `DOTNET_EnableDiagnostics=0` before process
  startup; this release documents the boundary rather than changing user-wide runtime
  settings.
- The install is per-user under `%LOCALAPPDATA%\Programs`; it is available across
  ordinary apps in that interactive user's desktop session, not at the Windows secure
  desktop, login screen, UAC prompts, or other users' sessions.

## Renamed executable boundary

The current executable is `FluidVoice Local.exe`, with a default installation path of `%LOCALAPPDATA%\Programs\FluidVoice Local\FluidVoice Local.exe`. Firewall configuration and privacy checks use **FluidVoice Local - Block Inbound** and **FluidVoice Local - Block Outbound**, and require that exact new executable path. Old executable-scoped rules continue to protect the old path. New path coverage must be provisioned and verified before launching a renamed candidate in a separately scoped Windows deployment.

The HKCU Run value `FluidVoiceHardened` remains the startup identity and is repointed by installation to the quoted new executable path. The existing single-instance mutex also remains shared with the legacy build. See [Windows rename and deployment](../README.md#windows-rename-and-deployment) for process, preservation and rollback considerations. Historical installed-payload observations above describe the pre-rename build; renamed source validation currently covers static checks only.
