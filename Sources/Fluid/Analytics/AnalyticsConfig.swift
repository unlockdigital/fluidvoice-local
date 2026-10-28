import Foundation

struct AnalyticsConfig {
    let postHogApiKey: String
    let postHogHost: String

    nonisolated static func fromBundle() -> AnalyticsConfig {
#if HARDENED
        // Hardened build: telemetry is compiled out. There is no bundled key or host,
        // so the config is always unconfigured and `isConfigured` is always false.
        return AnalyticsConfig(postHogApiKey: "", postHogHost: "")
#else
        let info = Bundle.main.infoDictionary ?? [:]
        let key = (info["POSTHOG_API_KEY"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Fail closed: with no host configured in the bundle there is no telemetry endpoint.
        let host = (info["POSTHOG_HOST"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return AnalyticsConfig(postHogApiKey: key, postHogHost: host)
#endif
    }

    /// Telemetry is only active when BOTH a non-empty key and a non-empty host are present.
    nonisolated var isConfigured: Bool { !self.postHogApiKey.isEmpty && !self.postHogHost.isEmpty }
}
