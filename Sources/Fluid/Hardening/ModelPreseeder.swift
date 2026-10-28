import CryptoKit
import Foundation
#if canImport(FluidAudio)
import FluidAudio
#endif

/// First-launch offline model preseeding.
///
/// The hardened Release embeds the Parakeet TDT v2 CoreML model inside the app at
/// `Contents/Resources/PreseededModels/` (placed there by `scripts/package-release.sh`).
/// On first launch, if the FluidAudio model cache is missing the model, this copies the
/// bundled copy into place and validates it — so speech recognition works with NO network
/// and NO Hugging Face contact. The hardened ASR path fails closed when the bundled model
/// or its manifest is unavailable.
enum ModelPreseeder {
    /// Copy the bundled model into the FluidAudio cache when needed and verify every file
    /// before ASR initialization proceeds. Existing caches receive the same verification on
    /// every launch so another process cannot silently replace model artifacts between runs.
    static func preseedIfNeeded() {
#if canImport(FluidAudio)
        preseedParakeet(folder: "parakeet-tdt-0.6b-v2-coreml", version: .v2)
#endif
    }

#if canImport(FluidAudio)
    private enum PreseedError: Error { case validationFailed(String) }

    private static func preseedParakeet(folder: String, version: AsrModelVersion) {
        let target = AsrModels.defaultCacheDirectory(for: version)

        guard let bundledDir = bundledModelDir(folder: folder) else {
            DebugLogger.shared.error(
                "ModelPreseeder: required bundled model is missing for \(folder)",
                source: "ModelPreseeder"
            )
            return
        }
        guard let manifest = bundledManifest(folder: folder) else {
            DebugLogger.shared.error(
                "ModelPreseeder: required checksum manifest is missing for \(folder)",
                source: "ModelPreseeder"
            )
            return
        }

        let fm = FileManager.default
        var existingCacheFailedValidation = false
        if AsrModels.modelsExist(at: target, version: version) {
            do {
                try validateChecksums(target: target, manifest: manifest)
                DebugLogger.shared.info(
                    "ModelPreseeder: launch integrity audit passed for \(folder)",
                    source: "ModelPreseeder"
                )
                return
            } catch {
                DebugLogger.shared.error(
                    "ModelPreseeder: cached model integrity audit failed; restoring bundled copy",
                    source: "ModelPreseeder"
                )
                existingCacheFailedValidation = true
            }
        } else if fm.fileExists(atPath: target.path) {
            existingCacheFailedValidation = true
        }

        var staging: URL?
        do {
            let parent = target.deletingLastPathComponent()
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            let staged = parent.appendingPathComponent(
                ".\(folder).preseed-\(UUID().uuidString)",
                isDirectory: true
            )
            staging = staged
            try fm.copyItem(at: bundledDir, to: staged)

            // Validate the complete staged copy before it can replace the active cache.
            try validateChecksums(target: staged, manifest: manifest)
            let requiredArtifacts = [
                "Preprocessor.mlmodelc",
                "Encoder.mlmodelc",
                "Decoder.mlmodelc",
                "JointDecision.mlmodelc",
                "parakeet_vocab.json",
            ]
            guard requiredArtifacts.allSatisfy({
                fm.fileExists(atPath: staged.appendingPathComponent($0).path)
            }) else {
                throw PreseedError.validationFailed("required artifacts missing from staged copy")
            }

            if fm.fileExists(atPath: target.path) {
                _ = try fm.replaceItemAt(target, withItemAt: staged)
            } else {
                try fm.moveItem(at: staged, to: target)
            }
            staging = nil

            // Confirm FluidAudio accepts the installed layout and recheck the signed manifest.
            guard AsrModels.modelsExist(at: target, version: version) else {
                try? fm.removeItem(at: target)
                throw PreseedError.validationFailed("required artifacts missing after copy")
            }
            try validateChecksums(target: target, manifest: manifest)
            DebugLogger.shared.info(
                "ModelPreseeder: preseeded and verified \(folder) offline",
                source: "ModelPreseeder"
            )
        } catch {
            DebugLogger.shared.error(
                "ModelPreseeder: failed to preseed a verified model for \(folder)",
                source: "ModelPreseeder"
            )
            if let staging, fm.fileExists(atPath: staging.path) {
                try? fm.removeItem(at: staging)
            }
            if existingCacheFailedValidation, fm.fileExists(atPath: target.path) {
                try? fm.removeItem(at: target)
            }
            return
        }
    }

    private static func preseededRoot() -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent("PreseededModels", isDirectory: true)
    }

    private static func bundledModelDir(folder: String) -> URL? {
        guard let dir = preseededRoot()?.appendingPathComponent(folder, isDirectory: true) else { return nil }
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    /// Reads `<folder>.manifest.json` (the `files` map of relativePath -> sha256) from the bundle.
    private static func bundledManifest(folder: String) -> [String: String]? {
        guard let url = preseededRoot()?.appendingPathComponent("\(folder).manifest.json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = obj["files"] as? [String: String]
        else { return nil }
        return files
    }

    private static func validateChecksums(target: URL, manifest: [String: String]) throws {
        guard manifest.isEmpty == false else {
            throw PreseedError.validationFailed("empty checksum manifest")
        }

        let root = target.standardizedFileURL.path
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: target,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else {
            throw PreseedError.validationFailed("unable to enumerate model directory")
        }

        var actualPaths = Set<String>()
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true {
                throw PreseedError.validationFailed("symbolic link found in model directory")
            }
            guard values.isRegularFile == true else { continue }
            let relativePath = String(fileURL.standardizedFileURL.path.dropFirst(root.count + 1))
            actualPaths.insert(relativePath)
        }

        guard actualPaths == Set(manifest.keys) else {
            throw PreseedError.validationFailed("model file set differs from checksum manifest")
        }

        for (relativePath, expected) in manifest {
            let fileURL = target.appendingPathComponent(relativePath).standardizedFileURL
            guard fileURL.path.hasPrefix(root + "/") else {
                throw PreseedError.validationFailed("manifest path escaped model root")
            }
            let actual = try sha256(of: fileURL)
            if actual != expected {
                throw PreseedError.validationFailed("checksum mismatch for \(relativePath)")
            }
        }
    }

    /// Streaming SHA-256 so large model weights are not loaded fully into memory.
    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
#endif
}
