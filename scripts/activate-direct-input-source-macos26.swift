import Carbon.HIToolbox
import Darwin
import Foundation

/// Installer-only compatibility helper for macOS 26.
///
/// Keyboard Settings in macOS 26 invokes TISEnableInputSourceWithOptions(source, 2) when the
/// user adds a source. The public TISEnableInputSource API currently returns noErr for newly
/// registered per-user input methods while leaving them disabled. This helper dynamically calls
/// the same system routine used by Keyboard Settings, verifies every state transition, and exits.
/// The FluidVoice app runtime does not link or call this routine. A separately signed, short-lived
/// source guardian uses the same guarded macOS 26 compatibility boundary after process loss.

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: activate-direct-input-source-macos26 /path/to/InputMethod.app\n".utf8))
    exit(2)
}

let bundleID = "com.unlockdigital.inputmethod.FluidVoiceHardened"
let modeID = "\(bundleID).direct"
let inputSourceURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    .standardizedFileURL
    .resolvingSymlinksInPath()
let expectedInputSourceURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Input Methods/FluidVoice Direct Input.app", isDirectory: true)
    .standardizedFileURL
    .resolvingSymlinksInPath()
guard inputSourceURL == expectedInputSourceURL else {
    FileHandle.standardError.write(
        Data("Refusing activation outside the canonical per-user Input Methods path\n".utf8)
    )
    exit(1)
}

let operatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
guard operatingSystemVersion.majorVersion == 26 else {
    FileHandle.standardError.write(
        Data("This installer compatibility path is restricted to macOS 26.x\n".utf8)
    )
    exit(1)
}

func property(_ source: TISInputSource, _ key: CFString) -> AnyObject? {
    guard let rawValue = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<AnyObject>.fromOpaque(rawValue).takeUnretainedValue()
}

func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
    (property(source, key) as? Bool) == true
}

func stringProperty(_ source: TISInputSource, _ key: CFString) -> String {
    (property(source, key) as? String) ?? "<unknown>"
}

func inputSources(property key: CFString, value: String) -> [TISInputSource] {
    let filter = [key as String: value] as CFDictionary
    guard let unmanagedList = TISCreateInputSourceList(filter, true) else { return [] }
    let list = unmanagedList.takeRetainedValue()
    return (0..<CFArrayGetCount(list)).map { index in
        unsafeBitCast(CFArrayGetValueAtIndex(list, index), to: TISInputSource.self)
    }
}

func parentSources() -> [TISInputSource] {
    inputSources(property: kTISPropertyBundleID, value: bundleID).filter {
        stringProperty($0, kTISPropertyInputSourceType) == (kTISTypeKeyboardInputMethodModeEnabled as String)
    }
}

func modeSources() -> [TISInputSource] {
    inputSources(property: kTISPropertyInputSourceID, value: modeID).filter {
        stringProperty($0, kTISPropertyInputSourceType) == (kTISTypeKeyboardInputMode as String)
            && stringProperty($0, kTISPropertyBundleID) == bundleID
    }
}

let registerStatus = TISRegisterInputSource(inputSourceURL as CFURL)
guard registerStatus == noErr else {
    FileHandle.standardError.write(Data("TISRegisterInputSource failed with OSStatus \(registerStatus)\n".utf8))
    exit(1)
}

let carbonFrameworkPath = "/System/Library/Frameworks/Carbon.framework/Versions/A/Carbon"
guard let carbonHandle = dlopen(carbonFrameworkPath, RTLD_LAZY | RTLD_LOCAL),
      let enableSymbol = dlsym(carbonHandle, "TISEnableInputSourceWithOptions") else {
    FileHandle.standardError.write(Data("macOS 26 Text Input Services activation routine is unavailable\n".utf8))
    exit(1)
}
defer { dlclose(carbonHandle) }

var symbolInfo = Dl_info()
let hitoolboxFrameworkPath =
    "/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/HIToolbox"
guard dladdr(enableSymbol, &symbolInfo) != 0,
      let loadedImagePath = symbolInfo.dli_fname.map({ String(cString: $0) }),
      loadedImagePath == carbonFrameworkPath
        || loadedImagePath == hitoolboxFrameworkPath
else {
    let imageDescription = symbolInfo.dli_fname.map { String(cString: $0) } ?? "<unresolved>"
    FileHandle.standardError.write(
        Data("Refusing an interposed Text Input Services activation routine from \(imageDescription)\n".utf8)
    )
    exit(1)
}

typealias EnableInputSourceWithOptions = @convention(c) (TISInputSource, CFOptionFlags) -> OSStatus
let enableWithOptions = unsafeBitCast(enableSymbol, to: EnableInputSourceWithOptions.self)

let initialParentSources = parentSources()
guard initialParentSources.count == 1, let parent = initialParentSources.first else {
    FileHandle.standardError.write(Data("Expected exactly one FluidVoice parent in the TIS catalog\n".utf8))
    exit(1)
}
let parentStatus = enableWithOptions(parent, 2)
guard parentStatus == noErr else {
    FileHandle.standardError.write(Data("Parent activation failed with OSStatus \(parentStatus)\n".utf8))
    exit(1)
}

guard let enabledParent = parentSources().first(where: {
    boolProperty($0, kTISPropertyInputSourceIsEnabled)
}) else {
    FileHandle.standardError.write(Data("Parent remains disabled after macOS 26 activation\n".utf8))
    exit(1)
}
print("Enabled parent: \(stringProperty(enabledParent, kTISPropertyInputSourceID))")

let initialModeSources = modeSources()
guard initialModeSources.count == 1, let mode = initialModeSources.first else {
    FileHandle.standardError.write(Data("Expected exactly one FluidVoice mode in the TIS catalog\n".utf8))
    exit(1)
}
let modeStatus = enableWithOptions(mode, 2)
guard modeStatus == noErr else {
    FileHandle.standardError.write(Data("Mode activation failed with OSStatus \(modeStatus)\n".utf8))
    exit(1)
}

guard let enabledMode = modeSources().first(where: {
    boolProperty($0, kTISPropertyInputSourceIsEnabled)
        && boolProperty($0, kTISPropertyInputSourceIsSelectCapable)
}) else {
    FileHandle.standardError.write(Data("Direct-input mode remains disabled after macOS 26 activation\n".utf8))
    exit(1)
}
print("Enabled mode: \(stringProperty(enabledMode, kTISPropertyInputSourceID))")

let selectStatus = TISSelectInputSource(enabledMode)
guard selectStatus == noErr else {
    FileHandle.standardError.write(Data("TISSelectInputSource failed with OSStatus \(selectStatus)\n".utf8))
    exit(1)
}

guard modeSources().contains(where: { boolProperty($0, kTISPropertyInputSourceIsSelected) }) else {
    FileHandle.standardError.write(Data("Direct-input mode was enabled but did not become selected\n".utf8))
    exit(1)
}

print("Selected FluidVoice Local Direct Input")
