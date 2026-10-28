# Source provenance

The community project adopted the **FluidVoice Local** name on October 28, 2026. Its previous publication name was FluidVoice Hardened. Branding changes update current documentation, UI text and new build products. Source-origin hashes, historical commit metadata, original attribution and third-party references continue to describe the preserved inputs. Stable OS and storage identifiers retain compatibility values as documented in [BRANDING.md](docs/BRANDING.md).

## Mac lineage

The maintained Mac branch descends from the real `altic-dev/FluidVoice` commit `fba0d3156037ee4ddeb5b8e34d1faf838ad37c7b` (June 22, 2026). Its original upstream history remains intact. The upstream project and contributors retain their original credit and GPLv3 notices.

The owner's separate local history began at `e6659f1bd49ee4f49a8467242c4c19dee8f8b62b`, a source import of that upstream snapshot with local planning material. Subsequent local hardening reached `0ae4daefffeb43afee1287f1c320298c06c6b752`; the direct-input commit was `7f4850cc61ca3594e552031cfe38e240b914bb1f`. The October 27 capture included 17 tracked modifications and 16 useful untracked files beyond that direct-input HEAD. These include lifecycle, shortcut/Globe, overlay and Secure Input recovery work.

This community branch imports that reviewed production source onto the real upstream base. It records the source-origin commit sequence in [MAC_HISTORY.json](docs/provenance/MAC_HISTORY.json) and captured imported-file hashes in [MAC_SOURCE_ORIGIN.json](docs/provenance/MAC_SOURCE_ORIGIN.json). Local origin IDs identify the preserved source history; new integration commits have their own identities. Public build routing, lock reconciliation, model pinning and community documentation are subsequent maintained changes.

The preserved source handoff ZIP SHA-256 was `bba4fac7ffca6758c6ab23caab72093b8dad84d3103579e85f1ba5c9f7d931ce`. It was a curated snapshot with normalized home paths, cleared inherited signing-team assignments and removed analytics credentials. Private runtime state, operational reports, installed binaries, credentials, models and raw local Git objects remain excluded from the community import. The original working repositories and installations were preserved.

## Windows lineage

[platforms/windows/PROVENANCE.md](platforms/windows/PROVENANCE.md) records the independent Windows C#/.NET history, original author, root/HEAD, filtered patch identities and source-origin hashes. Its source is imported as a separate native adaptation. The reviewed upstream icon reference establishes component context; historical whole-program Swift ancestry is unverified. The owner authorized GPLv3 treatment of their authored Windows adaptation with retained upstream and third-party notices.

## M5 evidence

The supplied M5 handoff provided verified public upstream `v1.6.9` source at `6f0684e694828b44fc643b7373f2a22d1e24eafa`, configuration observations and installed-app fingerprints. It did not recover the source used for the installed app. The public reference's 264 original blobs and three sanitization transformations were independently verified. Its ZIP SHA-256 was `eafe0363d6ed0888a3729b156a4fafd61f6bbb6c1a4fa2ffbd78aa8836676a63`.

No M5-specific source delta, private Fluid Intelligence helper or installed binary is imported here. macOS 27 qualification remains separate from the Mac source import. Signature investigation and actual-source recovery remain open on that host.
