# Building and packaging the Mac source

Use an Apple Silicon Mac with full Xcode 26.2 selected. The current build uses the Xcode project/scheme `Fluid`, Release configuration, and the two matching `Package.resolved` files. Exact direct package requirements are also recorded in Package.swift. Source builds require the pinned dependencies; model setup is a separate explicit step.

```sh
./build.sh resolve
./build.sh unsigned
```

The default build is ad-hoc signed. `SIGN_IDENTITY` selects a locally authorized identity; no identity or team is committed. `FLUIDVOICE_DERIVED_DATA_PATH` and `FLUIDVOICE_PACKAGE_DIRECTORY` can select isolated build/cache locations. Default outputs live under `build/`. No build command launches or installs the product.

The root Swift package describes the source/dependency graph; the supported macOS application bundle is produced by Xcode. Changes to the two lockfiles must be reviewed together. The application target compiles with `HARDENED` and `ARCH_ARM64`.

## Offline-ready bundle

Run `scripts/fetch-parakeet-model.sh` during an explicit setup window, or stage an independently supplied model and verify it with `scripts/fetch-pinned-model.py --verify-only`. The committed immutable revision and hashes supply the approval boundary. The helper preserves an invalid existing model destination. No package installation, credential lookup or persistent download agent is involved.

Then run `scripts/package-release.sh` followed by `scripts/package-direct-input-method.sh`. Both produce separate local artifacts under build/. The former verifies the model against the committed manifest and copies its approved files, embeds frameworks and signs the bundle; the latter applies InputMethodKit identity and microphone-only entitlements. Both run relevant artifact checks. Keep any existing staged direct-input artifact archived before making another one at the same output path.

## Installation boundary

The current `scripts/install-direct-input-method.sh` replaces a per-user bundle and alters input-source, keyboard and startup/guardian state. It is an experimental local installation route. Preserve a verified existing application outside the scanned Input Methods directory and establish recovery before any trial. The version-specific activation compatibility helper currently permits macOS 26. macOS 27 has a separate read-only readiness path and acceptance guide.

Physical release acceptance includes Right Option start/stop/final insertion, the original horizontal panel with live text, permissions/network observations, Secure Input recovery, relaunch/login and rollback. Build and fixture success establish their narrower boundaries. New candidate artifacts from this repository are not automatically equivalent to the preserved installed app.
