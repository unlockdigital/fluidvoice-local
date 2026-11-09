# Source preview validation

## Keyboard recovery candidate — October 28, 2026

Native testing exposed a physical-typing failure in Brave and Finder with the original FluidVoice mode selected. T3 physical typing continued working. U.S. input with the runtime stopped restored all three. A clean runtime and a per-user IMK service restart reproduced the application-specific failure. The local `fix/keyboard-pass-through` branch prepares a modifier-events-only routing candidate from `e20b0b5`; its [recovery guide](KEYBOARD_RECOVERY.md) records the scope and remaining native acceptance. The original app stays preserved and the U.S. keyboard remains the operating recovery state during preparation.

Validated October 27, 2026 on Apple M2 Max, 32 GB, macOS 26.5 (25F71), Xcode 26.2 (17C52). Checks used an isolated integration checkout and preserved the original source repositories and installed input method. Pinned dependency source checkouts were reused; application build intermediates were new.

| Check | Result and scope |
| --- | --- |
| Real upstream ancestry | Verified fba0d3156037ee4ddeb5b8e34d1faf838ad37c7b is an ancestor of this product branch |
| Preserved Mac source import | Committed hardening/Direct Input source with the captured working changes; public provenance retains origin identities and hashes |
| Public Xcode Release build | Passed through ./build.sh unsigned; no app launch or installation |
| Root Swift package manifest | dump-package passed after repairing source layout, pins and the inherited macOS-version manifest API mismatch; bundle distribution uses Xcode |
| Lockfile agreement | Root and Xcode Package.resolved files match |
| Static hardening | Passed |
| Network/redirect boundary fixtures | Passed |
| Temporary preference checker fixtures | Passed |
| Right Option/Globe gesture fixtures | Passed |
| Model integrity failure fixtures | Passed for corrupt, missing, unsafe and symlinked model files |
| Approved model source | All 55 local files match immutable public revision ee09c569f73759e6d44c9bd16766f477b2b36d39 by source-tree/LFS identities and the committed SHA-256 manifest |
| Setup helper fixture path | Synthetic download verifies immutable URL selection, approved reuse and preservation of invalid existing files. A fresh full network model download was not run |
| Offline-ready base packaging | Passed: model manifest/attribution, embedded dependencies, hardening metadata and deep strict signature |
| InputMethodKit packaging | Passed: canonical identity/metadata, UI-agent route, microphone-only signed entitlement and deep strict signature |
| Gatekeeper assessment | Rejected as expected for ad-hoc local candidates; these artifacts are not a notarized distribution |
| macOS 27 reporting fixtures | Passed self-tests and deterministic report cases; simulated outcomes stay labelled |
| Live readiness on this macOS 26 host | Exit 3, HOST-MISMATCH, PENDING_PHYSICAL_ACCEPTANCE; no activation or permission changes |
| Windows source import | Source-origin ledger and reviewed GPL/icon identities verified; implementation/scripts/projects/tests retain intake bytes |
| Windows license/provenance review | Independent review found no source-publication blocker with retained notices and separately documented history |
| GitHub CI | Configured for scoped Mac fixtures/build and experimental legacy Windows source build; first remote results are reported separately |

## Remaining native and distribution work

A new physical Mac candidate cycle, hardware/application matrix, Secure Input lifecycle and receiving-host installation remain pending. The local artifacts were packaged and verified without being launched or installed. The macOS 26 activation guard remains intact; macOS 27 needs the separate documented activation and physical qualification path. The M5 installed application's actual source and signature failure remain unresolved.

Windows .NET/runtime migration and SDK pinning, the failed logic harness, actual-account startup/firewall checks, meaningful live egress evidence, transactional installation, inference/backend and UX/accessibility acceptance remain open. Its reported 299-file installed match is supplied agent evidence from the Windows host. No Windows runtime tests were performed on this Mac. Native/runtime/model redistribution and signing remain binary-release gates.

Public source preview, source-build checks and supported binary qualification retain these distinct scopes. See HANDOFF.md, MACOS_27_QUALIFICATION.md and platforms/windows/README.md before any installation trial.

## November 8, 2026 — consolidation PR source review

PR #2 at `7e04b656e6542a54dcf86e8fd26016d0bd1b48cb` passed GitHub run [42537393360](https://github.com/unlockdigital/fluidvoice-local/actions/runs/42537393360): Mac source scans, deterministic fixtures, dependency resolution and unsigned application build; Windows locked restore and Release application source build. Fresh local execution also passed all six deterministic checks, including production keyboard routing and the real InputMethodKit SDK typecheck.

The review covered every changed source/script path and the platform guides. Changed-file credential-pattern scanning, public-artifact exclusions, lockfile agreement, shell syntax and local documentation-link checks passed. Mac Direct Input entitlements, insertion bridge, horizontal panel, activation helper, guardian behavior and dependency pins retain the base implementation. Windows application/Core/Verify source, scripts, tests, origin ledger, GPL and notices retain the base bytes. README navigation and the platform setup guides describe the separate installation and usage paths.

Review identified branch references that needed migration with the requested single public `main`: README, clone commands, naming documentation and CI filters. The final revision's GitHub checks provide the merge gate. Source review supports merging the source preview; the native and distribution gates above remain open, including physical keyboard/dictation stability and Windows logic-harness/runtime work. The source review includes no installation, application launch, microphone capture, permission reset or host-state changes.
