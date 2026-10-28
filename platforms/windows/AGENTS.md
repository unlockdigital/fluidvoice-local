# Windows contributor instructions

Read the root handoff and this subtree's README, security architecture, NOTICE and provenance before changing the Windows implementation. Preserve existing installations, user state, model caches and unrelated changes; use isolated build outputs.

- Keep speech recognition local and preserve the existing production privacy profile: no app-authored networking, telemetry, updates, cloud providers, transcript history, audio persistence, clipboard output, local servers or debug logging.
- Do not commit build outputs, tools, downloaded models, binaries, credentials, recordings, transcripts, or runtime state.
- Review scripts before use. Install, startup and firewall operations alter host state and need a separately scoped installation plan. Do not run capture, inference, or application launch as part of source-only review.
- Keep original provenance, GPL and third-party notices. Report source scans, fixture tests, builds and physical Windows acceptance separately.
- Preserve independent Windows and Mac application state and installation directories.
