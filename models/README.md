# Approved local speech model

Model: `FluidInference/parakeet-tdt-0.6b-v2-coreml`, based on NVIDIA Parakeet TDT 0.6B v2, with CoreML conversion and integration by FluidInference.

- Source: https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml
- Immutable source revision: `ee09c569f73759e6d44c9bd16766f477b2b36d39`.
- License: [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/).
- Approved payload: 55 files, 2,575,138,422 bytes, with SHA-256 values in `parakeet-tdt-0.6b-v2-coreml.manifest.json`.

On October 27, 2026, all 55 supplied local artifacts were matched against the public repository's immutable tree: Git blob identities for ordinary files and LFS SHA-256 values for large artifacts. The setup helper verifies every downloaded artifact against the committed SHA-256 manifest. This fork packages the approved artifacts without changing their model contents. Retain the supplied attribution and any applicable source notices when redistributing model material.

Weights stay outside Git under `vendor/models/`. Only explicit developer setup contacts the model host. The hardened runtime uses a preseeded verified copy and fails closed when it is unavailable. The public fetch uses Python's standard library and curl; it installs no Python packages or model-fetch LaunchAgent.
