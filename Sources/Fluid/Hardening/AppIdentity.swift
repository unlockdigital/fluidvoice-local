import Foundation

/// Single source of truth for the hardened build's storage identity.
///
/// The hardened app must never read or write data that belongs to an upstream
/// FluidVoice install (settings, provider API keys, dictation history, logs).
/// `UserDefaults.standard` is already isolated by the hardened bundle identifier
/// (`com.unlockdigital.FluidVoiceHardened`); these constants scope the remaining
/// hardcoded on-disk and Keychain locations to match.
///
/// Non-sensitive, large model caches (FluidAudio / Whisper model binaries) are
/// intentionally NOT re-scoped: they contain no private content and sharing them
/// with an upstream install avoids multi-gigabyte re-downloads.
enum AppIdentity {
    /// Subfolder under `~/Library/Application Support` for app-private data
    /// (dictation audio history, custom vocabulary, local AI model storage).
    static let appSupportFolderName = "FluidVoiceHardened"

    /// Subfolder under `~/Library/Logs` for diagnostic logs.
    static let logsFolderName = "FluidVoiceHardened"

    /// Keychain generic-password service used for provider API keys.
    static let keychainService = "com.unlockdigital.fluidvoicehardened.provider-api-keys"
}
