import Foundation

/// Single fail-closed source of truth for whether diagnostic (non-crash) logging may
/// write anything — to the on-disk log file, to stdout, or to the in-app log panel.
///
/// Reads `UserDefaults` directly (NOT `SettingsStore`) on purpose: `DebugLogger` can be
/// invoked during `SettingsStore.init()`, and routing through the store would risk a
/// recursive singleton deadlock.
///
/// Posture:
/// - Defaults to OFF when the key is unset (fail closed).
/// - Crash diagnostics (exception metadata + stack traces) are written through a separate
///   path in `FileLogger` and are intentionally NOT gated by this flag.
enum DiagnosticLogging {
    /// UserDefaults key mirrored from `SettingsStore.Keys.enableDebugLogs`.
    static let enableKey = "EnableDebugLogs"

    /// Whether diagnostic logging is permitted to write. Fails closed when unset.
    static var isEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: enableKey) != nil else { return false }
        return defaults.bool(forKey: enableKey)
    }
}
