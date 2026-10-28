import Carbon.HIToolbox
import Foundation

/// Persists the same two records macOS keeps for a mode-based keyboard input method.
///
/// On macOS 26, TISEnableInputSource can return noErr while leaving a newly registered
/// per-user input method disabled. This helper is an installer-only fallback. It edits only
/// FluidVoice's records in the current user's HIToolbox preference arrays; the installer saves
/// the complete pre-change plist before invoking it.

let domain = "com.apple.HIToolbox" as CFString
let bundleID = "com.unlockdigital.inputmethod.FluidVoiceHardened"
let modeID = "\(bundleID).direct"

let parentRecord: [String: Any] = [
    "Bundle ID": bundleID,
    "InputSourceKind": "Keyboard Input Method",
]
let modeRecord: [String: Any] = [
    "Bundle ID": bundleID,
    "Input Mode": modeID,
    "InputSourceKind": "Input Mode",
]

func records(for key: String) -> [[String: Any]] {
    (CFPreferencesCopyAppValue(key as CFString, domain) as? [[String: Any]]) ?? []
}

func belongsToFluidVoice(_ record: [String: Any]) -> Bool {
    (record["Bundle ID"] as? String) == bundleID
        || (record["Input Mode"] as? String) == modeID
}

func setRecords(_ records: [[String: Any]], for key: String) {
    CFPreferencesSetAppValue(key as CFString, records as CFArray, domain)
}

var enabled = records(for: "AppleEnabledInputSources").filter { !belongsToFluidVoice($0) }
enabled.append(parentRecord)
enabled.append(modeRecord)

setRecords(enabled, for: "AppleEnabledInputSources")

guard CFPreferencesAppSynchronize(domain) else {
    FileHandle.standardError.write(Data("Failed to synchronize com.apple.HIToolbox\n".utf8))
    exit(1)
}

let notificationCenter = DistributedNotificationCenter.default()
if let enabledNotification = kTISNotifyEnabledKeyboardInputSourcesChanged {
    notificationCenter.post(name: Notification.Name(enabledNotification as String), object: nil)
}
notificationCenter.post(
    name: Notification.Name("AppleEnabledInputSourcesChangedNotification"),
    object: nil
)

let persistedEnabled = records(for: "AppleEnabledInputSources")
guard persistedEnabled.contains(where: {
    ($0["Bundle ID"] as? String) == bundleID
        && ($0["InputSourceKind"] as? String) == "Keyboard Input Method"
}), persistedEnabled.contains(where: {
    ($0["Input Mode"] as? String) == modeID
        && ($0["InputSourceKind"] as? String) == "Input Mode"
}) else {
    FileHandle.standardError.write(Data("FluidVoice input-source records did not persist\n".utf8))
    exit(1)
}

print("Persisted FluidVoice parent and mode records in com.apple.HIToolbox")
