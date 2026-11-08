# Mac setup and use

[Project home](../README.md) · [Windows guide](WINDOWS.md) · [Build reference](BUILDING.md)

FluidVoice Local for Mac uses local Parakeet v2 recognition. The Direct Input candidate uses InputMethodKit to insert text and Right Option to toggle dictation. Its original horizontal panel displays live text while you speak.

## Requirements and status

- Apple Silicon Mac, macOS 26, full Xcode 26.2 and selected command-line tools.
- Python 3, curl and jq for model verification and packaging.
- Space for the approximately 2.6 GB approved model plus dependencies and build outputs.
- Network access during explicit dependency and model preparation; runtime recognition uses the local model.

This is a source preview. The current Direct Input keyboard repair requires fresh physical acceptance in T3, Brave and Finder. The preserved working standalone installation has its own acceptance record and Accessibility authorization. Keep that installation and its permissions intact while preparing the microphone-only Direct Input candidate. See [keyboard recovery](KEYBOARD_RECOVERY.md).

The activation compatibility helper currently accepts macOS 26. Follow the separate [macOS 27 qualification guide](MACOS_27_QUALIFICATION.md) for that platform.

## Prepare and build

Clone into a fresh development directory, or use your existing canonical checkout:

```sh
git clone --branch hardened https://github.com/unlockdigital/fluidvoice-local.git
cd fluidvoice-local
./build.sh resolve
./build.sh unsigned
```

The build uses pinned dependencies and produces an application under `build/`. These commands prepare source and build artifacts. Installation is a separate step. The unsigned build still needs the approved model for offline use.

## Prepare the offline model and bundles

From the repository root:

```sh
./scripts/fetch-parakeet-model.sh
./scripts/package-release.sh
./scripts/package-direct-input-method.sh
```

The model helper verifies 55 approved files against an immutable revision and committed hashes. Model weights stay in ignored `vendor/` storage. See [model attribution](../models/README.md) for the source and license.

Packaging produces `build/FluidVoice Local.app` and `build/FluidVoice Local Direct Input.app`. The default signing identity is ad hoc; `SIGN_IDENTITY` selects an authorized local identity. The release packager replaces its staged base app; archive any needed prior outputs first. The Direct Input packager requires its output path to be clear. See [build and packaging](BUILDING.md) for isolated output options and artifact verification.

## Install a qualified trial candidate

Installation belongs to a separately scoped native trial. Read [HANDOFF.md](../HANDOFF.md) and the [keyboard recovery guide](KEYBOARD_RECOVERY.md), preserve the working signed application outside the scanned Input Methods directory, and verify a rollback route with the U.S. keyboard available.

The trial installer is:

```sh
./scripts/install-direct-input-method.sh "build/FluidVoice Local Direct Input.app"
```

It installs to `~/Library/Input Methods/FluidVoice Direct Input.app`, preserving the established compatibility path. It changes input-source registration, Globe configuration and guardian startup state, and saves input-source preferences and prior bundles. Its automatic recovery covers specific failure paths; the trial plan must also cover keyboard and startup recovery after installation. On the currently preserved standalone operating route, keep the guardian disabled until the candidate's typing and dictation checks pass.

The Direct Input candidate uses microphone permission and microphone-only signed capability. Its runtime keeps external networking, content logs, history, cloud processing, Command Mode and the Local API disabled. The existing standalone app uses its separate permission profile.

## Dictate with Direct Input

After installation and selection under the trial plan:

1. Select **FluidVoice Local Direct Input** from the macOS input menu.
2. Focus an ordinary editable text field and place the caret where text should appear.
3. Press and release **Right Option** to start recording. Speak while the horizontal panel shows live text.
4. Press and release **Right Option** again to stop and insert the final transcription.
5. Verify insertion once at the caret, then check ordinary typing, deletion and shortcuts.

macOS handles Globe / Emoji & Symbols and Fn shortcuts. Secure Input can pause input-source recovery; follow the documented recovery route before resuming. If typing fails, return to the U.S. keyboard and use the scoped recovery plan to stop the candidate and pause its guardian. Preserve the working standalone installation throughout.

## Verify a source candidate

Run from the repository root:

```sh
bash scripts/verify-hardening.sh
bash scripts/test-hardened-network-policy.sh
bash scripts/test-hardened-preference-checks.sh
bash scripts/test-direct-input-modifier-gestures.sh
bash scripts/test-direct-input-keyboard-routing.sh
python3 scripts/test-pinned-model.py
```

These source scans and synthetic fixtures use isolated outputs; preference fixtures use a temporary domain. Physical acceptance additionally covers typing in the target applications, a unique synthetic phrase inserted once, Right Option, Globe/Fn, panel behavior, permissions, sockets, crashes, relaunch/login and Secure Input recovery. [Validation](VALIDATION.md) records the evidence and remaining gates.
