# FluidVoice repository consolidation — November 8, 2026

The canonical local source repository is ~/Documents/CODEX/FLUIDVOICE-LOCAL, with origin https://github.com/unlockdigital/fluidvoice-local.git and upstream https://github.com/altic-dev/FluidVoice.git. The initial consolidation advanced local `hardened` with the keyboard pass-through repair and this record. The subsequent source review prepares `main` as the single maintained public branch, with Mac and Windows setup guides and matching CI triggers. Historical branch names below describe the consolidation inputs.

## Assessment and retained work

| Former folder | Finding | Disposition |
| --- | --- | --- |
| FLUIDVOICE-LOCAL | Main checkout and owner of the shared .git directory, at e20b0b50a16feba94733beb7e426d002cb6d49c6 | Retained as the single repository. Local hardened advances through the keyboard-repair commits. |
| FLUIDVOICE-KEYBOARD-REPAIR | Clean worktree on fix/keyboard-pass-through, at 8e5723bf9811fb3cc1be8357c09fc3745098da75 | Repair incorporated into local hardened; original branch retained; redundant checkout removed. |
| FLUIDVOICE-LOCAL-CANDIDATE | Clean worktree on feature/stop-target-captions, at 60a3d1e84c660332d7b5ff439b81a92aa0387aa5 | Branch retained for future native qualification; redundant checkout removed. The ignored default.profraw is preserved in local recovery. |
| FLUIDVOICE | Independent older hardening repository, at 0ae4daefffeb43afee1287f1c320298c06c6b752, with 24 commits and local model payload | Full history imported as archive/legacy-hardened-local-first and archive/legacy-main; vendor moved intact to the canonical repository; remaining files archived and redundant folder removed. |

The keyboard repair limits the input controller to modifier events and leaves ordinary typing to the host application. It is the latest focused recovery source. The stop-target/caption branch changes delivery and presentation substantially and has a failed native trial followed by an unqualified correction. Its complete source, tests and STOP_TARGET_ACCEPTANCE.md remain on that branch. Further integration belongs to its native acceptance work.

The older hardening plans, audits, daemon helpers and upstream README remain available through the archive branches and original-folder recovery archive. Their earlier canonical-folder claim and model-fetch daemon describe the historical implementation. Current preparation uses the pinned-model tooling in this repository. Licensing, upstream attribution, independent Windows provenance and the complete current Windows subtree remain retained.

## Observed operating installation

Read-only inspection found one running standalone executable at ~/Applications/FluidVoice Hardened.app/Contents/MacOS/FluidVoice Hardened. Its SHA-256 is fe578faeb6f4c82c9d9c6aed64e9e407e0c3e42e244650611dbe7d530eade29a, matching the owner's October 28 working-installation recovery record. That record describes the standalone global-hotkey route with its matching Accessibility authorization and U.S. keyboard. The guardian launchd service is disabled and unloaded. The selected input source is U.S.; the on-disk preference file also retains historical FluidVoice input-source entries.

This source consolidation preserves that operating installation, its signed recovery anchor, startup/keyboard preferences, permissions and external FluidAudio model cache. The Direct Input source remains subject to HANDOFF.md's microphone-only boundary and native qualification. The working standalone installation and the Direct Input candidate have separate acceptance records.

## Models and local recovery

The original vendor directory now lives at FLUIDVOICE-LOCAL/vendor. All 55 approved model artifacts match the committed immutable model manifest, totaling 2,575,138,422 bytes. The original local manifest, attribution files and all additional vendor entries are retained. The payload stays ignored by Git.

Private recovery material lives in .local/recovery/2026-11-08/. It contains:

- Four original-folder archives, verified against a per-file SHA-256 inventory before removal.
- The complete legacy Git bundle, original refs/status records and file inventory.
- Deterministic-check logs, consolidation scripts and a recovery guide.

The legacy archive delegates its vendor subtree to the intact canonical vendor directory, avoiding another multi-gigabyte model copy. The other archives include their original .git files or directory. The canonical Git database, remotes, refs, existing reflogs and partial-clone configuration remain retained. The original clone already has promised historical objects: the local source branches have 2,011 missing historical objects and origin/main has 6,061. Their existing promisor relationship with origin remains available for historical reads; this consolidation preserves all locally present Git objects. The legacy history bundle is complete and self-contained.

Both .gitignore and the shared .git/info/exclude protect .local recovery material. Local archive branches and recovery files remain private until the owner chooses to share them.

## Validation and remaining acceptance

All six deterministic checks passed during preparation:

- Static hardening source scan.
- Compiled hardened network-policy fixtures.
- Temporary-domain preference fixtures.
- Compiled Direct Input modifier fixtures.
- Production keyboard-routing fixtures and real InputMethodKit SDK typecheck.
- Pinned-model integrity and setup failure fixtures.

Repository/file checks verify original archives, retained refs and legacy commits, unchanged production source against the keyboard-repair tree, the moved model payload and a single final Git worktree. Local Git object checks use the existing promisor configuration.

This work performs source and filesystem consolidation. New app builds, installation replacement, microphone trials and physical dictation/keyboard acceptance remain separate scoped work. The keyboard repair and stop-target/caption candidate retain their documented native acceptance gates.
