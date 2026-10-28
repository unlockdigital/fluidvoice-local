# Source preview validation

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
