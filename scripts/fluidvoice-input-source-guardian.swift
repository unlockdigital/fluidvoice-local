import AppKit
import Carbon.HIToolbox
import Darwin
import Foundation
import IOKit
import OSLog

/// Restores FluidVoice after its InputMethodKit process exits and macOS falls back to U.S.
///
/// The helper runs briefly under launchd, uses documented Text Input Services APIs, and exits.
/// It pauses during Secure Event Input and leaves every non-U.S. input source unchanged.
private let bundleID = "com.unlockdigital.inputmethod.FluidVoiceHardened"
private let modeID = "com.unlockdigital.inputmethod.FluidVoiceHardened.direct"
private let fallbackID = "com.apple.keylayout.US"
private let logger = Logger(subsystem: bundleID, category: "InputSourceGuardian")
private let canonicalInputSourceURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Input Methods/FluidVoice Direct Input.app", isDirectory: true)
    .standardizedFileURL
    .resolvingSymlinksInPath()
private let staleSecureRecoveryMarkerURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(
        "Library/Application Support/FluidVoiceHardened/InputSourceGuardian/stale-secure-recovery-owner.txt",
        isDirectory: false
    )

private func fail(_ message: String, code: Int32) -> Never {
    logger.error("\(message, privacy: .public); exitCode=\(code, privacy: .public)")
    FileHandle.standardError.write(Data("FluidVoice guardian: \(message) [\(code)]\n".utf8))
    exit(code)
}

private func sourceProperty(_ source: TISInputSource, _ key: CFString) -> AnyObject? {
    guard let rawValue = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<AnyObject>.fromOpaque(rawValue).takeUnretainedValue()
}

private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
    sourceProperty(source, key) as? String
}

private func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
    (sourceProperty(source, key) as? Bool) == true
}

private func currentSourceID() -> String? {
    guard let unmanagedSource = TISCopyCurrentKeyboardInputSource() else { return nil }
    return stringProperty(unmanagedSource.takeRetainedValue(), kTISPropertyInputSourceID)
}

private func runtimeIsRunning() -> Bool {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains { app in
        app.bundleURL?
            .standardizedFileURL
            .resolvingSymlinksInPath() == canonicalInputSourceURL
    }
}

private func secureInputOwnerPID() -> pid_t? {
    let registryRoot = IORegistryGetRootEntry(kIOMainPortDefault)
    guard registryRoot != 0 else { return nil }
    defer { IOObjectRelease(registryRoot) }

    var unmanagedProperties: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(
        registryRoot,
        &unmanagedProperties,
        kCFAllocatorDefault,
        0
    ) == KERN_SUCCESS,
          let registryProperties = unmanagedProperties?.takeRetainedValue() as? [String: Any],
          let consoleUsers = registryProperties["IOConsoleUsers"] as? [[String: Any]],
          let activeConsoleUser = consoleUsers.first(where: {
              ($0["kCGSSessionOnConsoleKey"] as? Bool) == true
          }),
          let ownerNumber = activeConsoleUser["kCGSSessionSecureInputPID"] as? NSNumber
    else {
        return nil
    }

    let ownerPID = ownerNumber.int32Value
    return ownerPID > 0 ? ownerPID : nil
}

private func processIsAlive(_ pid: pid_t) -> Bool {
    errno = 0
    return kill(pid, 0) == 0 || errno != ESRCH
}

private func processName(_ pid: pid_t) -> String {
    NSRunningApplication(processIdentifier: pid)?.localizedName ?? "<unavailable>"
}

private func previouslyAttemptedStaleOwnerPID() -> pid_t? {
    guard let marker = try? String(contentsOf: staleSecureRecoveryMarkerURL, encoding: .utf8) else {
        return nil
    }
    return pid_t(marker.trimmingCharacters(in: .whitespacesAndNewlines))
}

private func recordStaleOwnerRecoveryAttempt(_ pid: pid_t) -> Bool {
    do {
        try "\(pid)\n".write(
            to: staleSecureRecoveryMarkerURL,
            atomically: true,
            encoding: .utf8
        )
        return true
    } catch {
        logger.error(
            "Guardian could not persist the bounded stale-owner recovery marker; error=\(error.localizedDescription, privacy: .public)"
        )
        return false
    }
}

private func clearStaleOwnerRecoveryMarker() {
    guard FileManager.default.fileExists(atPath: staleSecureRecoveryMarkerURL.path) else { return }
    do {
        try FileManager.default.removeItem(at: staleSecureRecoveryMarkerURL)
        logger.notice("Guardian cleared the stale Secure Input recovery marker")
    } catch {
        logger.error(
            "Guardian could not clear the stale Secure Input recovery marker; error=\(error.localizedDescription, privacy: .public)"
        )
    }
}

private func launchRuntime() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    // Launch without taking keyboard focus while preserving the custom transcription panel.
    // `open -j` marks the application hidden, which lets the input method keep recording but
    // prevents AppKit from ordering FluidVoice's nonactivating overlay panel onscreen.
    process.arguments = ["-g", canonicalInputSourceURL.path]
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        fail("canonical input method launch failed", code: 17)
    }
    guard process.terminationStatus == 0 else {
        fail("canonical input method launch returned \(process.terminationStatus)", code: 18)
    }
    logger.notice("Guardian launched the FluidVoice input-method runtime")
}

private func inputSources(property: CFString, value: String) -> [TISInputSource] {
    let filter = [property as String: value] as CFDictionary
    guard let unmanagedList = TISCreateInputSourceList(filter, true) else { return [] }

    let list = unmanagedList.takeRetainedValue()
    return (0..<CFArrayGetCount(list)).map { index in
        unsafeBitCast(CFArrayGetValueAtIndex(list, index), to: TISInputSource.self)
    }
}

private func parentSources() -> [TISInputSource] {
    inputSources(property: kTISPropertyBundleID, value: bundleID).filter {
        stringProperty($0, kTISPropertyInputSourceType)
            == (kTISTypeKeyboardInputMethodModeEnabled as String)
    }
}

private func modeSources() -> [TISInputSource] {
    inputSources(property: kTISPropertyInputSourceID, value: modeID).filter {
        stringProperty($0, kTISPropertyBundleID) == bundleID
            && stringProperty($0, kTISPropertyInputSourceType)
                == (kTISTypeKeyboardInputMode as String)
    }
}

private func enableForCurrentOS(parent: TISInputSource, mode: TISInputSource) -> Bool {
    let operatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    guard operatingSystemVersion.majorVersion == 26 else {
        let parentStatus = TISEnableInputSource(parent)
        let modeStatus = TISEnableInputSource(mode)
        guard parentStatus == noErr, modeStatus == noErr else {
            fail(
                "public activation failed with parent=\(parentStatus) mode=\(modeStatus)",
                code: 20
            )
        }
        return true
    }

    // macOS 26 requires the same guarded activation option used by Keyboard Settings. The main
    // FluidVoice app remains linked only to public TIS APIs; this short-lived guardian owns the
    // compatibility boundary and verifies the system symbol image before calling it.
    let carbonFrameworkPath = "/System/Library/Frameworks/Carbon.framework/Versions/A/Carbon"
    let hitoolboxFrameworkPath =
        "/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/HIToolbox"
    guard let carbonHandle = dlopen(carbonFrameworkPath, RTLD_LAZY | RTLD_LOCAL),
          let enableSymbol = dlsym(carbonHandle, "TISEnableInputSourceWithOptions")
    else {
        fail("macOS 26 activation symbol is unavailable", code: 21)
    }
    defer { dlclose(carbonHandle) }

    var symbolInfo = Dl_info()
    guard dladdr(enableSymbol, &symbolInfo) != 0,
          let loadedImagePath = symbolInfo.dli_fname.map({ String(cString: $0) }),
          loadedImagePath == carbonFrameworkPath || loadedImagePath == hitoolboxFrameworkPath
    else {
        fail("macOS 26 activation symbol image is invalid", code: 22)
    }

    typealias EnableInputSourceWithOptions = @convention(c) (TISInputSource, CFOptionFlags) -> OSStatus
    let enableWithOptions = unsafeBitCast(enableSymbol, to: EnableInputSourceWithOptions.self)
    let parentStatus = enableWithOptions(parent, 2)
    let modeStatus = enableWithOptions(mode, 2)
    guard parentStatus == noErr, modeStatus == noErr else {
        fail(
            "macOS 26 activation failed with parent=\(parentStatus) mode=\(modeStatus)",
            code: 23
        )
    }
    return true
}


guard let currentID = currentSourceID() else {
    fail("current input source is unavailable", code: 10)
}
let secureInputEnabled = IsSecureEventInputEnabled()
let secureOwnerPID = secureInputEnabled ? secureInputOwnerPID() : nil
let secureOwnerIsAlive = secureOwnerPID.map(processIsAlive)
if secureInputEnabled == false {
    clearStaleOwnerRecoveryMarker()
}
logger.notice(
    "Guardian observed state; current=\(currentID, privacy: .public) secure=\(secureInputEnabled, privacy: .public) ownerPID=\(secureOwnerPID ?? 0, privacy: .public) ownerAlive=\(secureOwnerIsAlive ?? false, privacy: .public)"
)

guard FileManager.default.fileExists(atPath: canonicalInputSourceURL.path) else {
    fail("canonical input method is missing", code: 11)
}
if runtimeIsRunning() == false {
    launchRuntime()
}

guard currentID != modeID else { exit(0) }
guard currentID == fallbackID else { exit(0) }
if secureInputEnabled {
    guard let secureOwnerPID, secureOwnerIsAlive == false else {
        let ownerDescription = secureOwnerPID.map(processName) ?? "<unavailable>"
        logger.notice(
            "Guardian paused source restoration during Secure Event Input; ownerPID=\(secureOwnerPID ?? 0, privacy: .public) owner=\(ownerDescription, privacy: .public)"
        )
        exit(0)
    }
    guard previouslyAttemptedStaleOwnerPID() != secureOwnerPID else {
        logger.error(
            "Guardian paused after one bounded stale-owner recovery attempt; deadOwnerPID=\(secureOwnerPID, privacy: .public); a macOS session restart is required"
        )
        exit(0)
    }
    guard recordStaleOwnerRecoveryAttempt(secureOwnerPID) else {
        exit(0)
    }
    logger.error(
        "Guardian detected a stale Secure Event Input owner and will make one bounded restoration attempt; deadOwnerPID=\(secureOwnerPID, privacy: .public)"
    )
}

let registerStatus = TISRegisterInputSource(canonicalInputSourceURL as CFURL)
guard registerStatus == noErr else {
    fail("registration failed with OSStatus \(registerStatus)", code: 12)
}

let parents = parentSources()
let modes = modeSources()
guard parents.count == 1, modes.count == 1,
      let parent = parents.first, let mode = modes.first
else {
    fail("expected exactly one FluidVoice parent and mode", code: 13)
}
guard enableForCurrentOS(parent: parent, mode: mode),
      boolProperty(parent, kTISPropertyInputSourceIsEnabled),
      boolProperty(mode, kTISPropertyInputSourceIsEnabled),
      boolProperty(mode, kTISPropertyInputSourceIsSelectCapable)
else {
    fail("FluidVoice parent and mode did not become enabled", code: 14)
}

let selectStatus = TISSelectInputSource(mode)
guard selectStatus == noErr else {
    fail("selection failed with OSStatus \(selectStatus)", code: 15)
}

guard currentSourceID() == modeID,
      boolProperty(mode, kTISPropertyInputSourceIsSelected)
else {
    fail("selection did not become current", code: 16)
}

logger.notice("Guardian restored FluidVoice Direct Input")
