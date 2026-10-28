# Third party notices

The app source derives from [altic-dev/FluidVoice](https://github.com/altic-dev/FluidVoice) under the retained [GNU GPLv3](LICENSE). Original source headers and contributor credit remain intact. Windows adaptation and mark notices appear in [platforms/windows/NOTICE](platforms/windows/NOTICE).

The Mac dependency graph is pinned in both resolved files. Full license texts from the resolved source checkouts are retained under [licenses/dependencies](licenses/dependencies), with revisions and SHA-256 values in [DEPENDENCY_LICENSES.json](docs/DEPENDENCY_LICENSES.json). Direct components include AppUpdater (Unlicense/public-domain dedication), FluidAudio (Apache 2.0), DynamicNotchKit (MIT), SwiftWhisper (MIT), PromiseKit (MIT), and the MCP Swift SDK (MIT). Each notice applies to its own component; the app's license preserves those rights.

The approved speech model is a separate [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) work, credited to NVIDIA and FluidInference. [models/README.md](models/README.md) records its source and immutable revision. Model weights and dependency/native-runtime binaries are excluded from this source repository.

A future binary distribution requires a complete artifact-specific dependency/native/model license and notice review. Windows native CUDA/runtime and model terms remain that platform's binary gate. Private Fluid Intelligence executables/resources are excluded from this fork's public build and import.
