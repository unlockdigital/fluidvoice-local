import Carbon.HIToolbox
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: register-direct-input-source /path/to/InputMethod.app\n".utf8))
    exit(2)
}

let inputSourceURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let status = TISRegisterInputSource(inputSourceURL as CFURL)
guard status == noErr else {
    FileHandle.standardError.write(Data("TISRegisterInputSource failed with OSStatus \(status)\n".utf8))
    exit(1)
}

print("Registered input source: \(inputSourceURL.path)")

let modeID = "com.unlockdigital.inputmethod.FluidVoiceHardened.direct"
let bundleID = "com.unlockdigital.inputmethod.FluidVoiceHardened"

func sourceProperty(_ source: TISInputSource, _ key: CFString) -> AnyObject? {
    guard let rawValue = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<AnyObject>.fromOpaque(rawValue).takeUnretainedValue()
}

func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
    (sourceProperty(source, key) as? Bool) == true
}

func stringProperty(_ source: TISInputSource, _ key: CFString) -> String {
    (sourceProperty(source, key) as? String) ?? "<unknown>"
}

func describe(_ label: String, _ sources: [TISInputSource]) {
    for (index, source) in sources.enumerated() {
        print(
            "\(label)[\(index)] id=\(stringProperty(source, kTISPropertyInputSourceID)) "
                + "category=\(stringProperty(source, kTISPropertyInputSourceCategory)) "
                + "type=\(stringProperty(source, kTISPropertyInputSourceType)) "
                + "enableCapable=\(boolProperty(source, kTISPropertyInputSourceIsEnableCapable)) "
                + "enabled=\(boolProperty(source, kTISPropertyInputSourceIsEnabled)) "
                + "selectCapable=\(boolProperty(source, kTISPropertyInputSourceIsSelectCapable)) "
                + "selected=\(boolProperty(source, kTISPropertyInputSourceIsSelected))"
        )
    }
}

func inputSources(property: CFString?, value: String) -> [TISInputSource] {
    guard let property,
          let unmanagedList = TISCreateInputSourceList([property as String: value] as CFDictionary, true)
    else { return [] }

    let list = unmanagedList.takeRetainedValue()
    return (0..<CFArrayGetCount(list)).map { index in
        unsafeBitCast(CFArrayGetValueAtIndex(list, index), to: TISInputSource.self)
    }
}

let parentSources = inputSources(property: kTISPropertyBundleID, value: bundleID).filter {
    stringProperty($0, kTISPropertyInputSourceType) == (kTISTypeKeyboardInputMethodModeEnabled as String)
}
guard parentSources.isEmpty == false else {
    FileHandle.standardError.write(Data("Registered input method was not returned by Text Input Services\n".utf8))
    exit(1)
}

describe("parent-before", parentSources)

for source in parentSources {
    let parentEnableStatus = TISEnableInputSource(source)
    guard parentEnableStatus == noErr else {
        FileHandle.standardError.write(Data("TISEnableInputSource failed for the parent with OSStatus \(parentEnableStatus)\n".utf8))
        exit(1)
    }
}


let enabledParentSources = inputSources(property: kTISPropertyBundleID, value: bundleID).filter {
    stringProperty($0, kTISPropertyInputSourceType) == (kTISTypeKeyboardInputMethodModeEnabled as String)
}
describe("parent-after", enabledParentSources)
guard enabledParentSources.contains(where: { boolProperty($0, kTISPropertyInputSourceIsEnabled) }) else {
    FileHandle.standardError.write(Data("Text Input Services returned success but the parent remains disabled\n".utf8))
    exit(1)
}

let modeSources = inputSources(property: kTISPropertyInputSourceID, value: modeID).filter {
    stringProperty($0, kTISPropertyInputSourceType) == (kTISTypeKeyboardInputMode as String)
        && stringProperty($0, kTISPropertyBundleID) == bundleID
}
guard modeSources.isEmpty == false else {
    FileHandle.standardError.write(Data("Registered input mode was not returned by Text Input Services\n".utf8))
    exit(1)
}


describe("mode-before", modeSources)

for source in modeSources {
    let modeEnableStatus = TISEnableInputSource(source)
    guard modeEnableStatus == noErr else {
        FileHandle.standardError.write(Data("TISEnableInputSource failed for the mode with OSStatus \(modeEnableStatus)\n".utf8))
        exit(1)
    }
}


let enabledModeSources = inputSources(property: kTISPropertyInputSourceID, value: modeID).filter {
    stringProperty($0, kTISPropertyInputSourceType) == (kTISTypeKeyboardInputMode as String)
        && stringProperty($0, kTISPropertyBundleID) == bundleID
}
describe("mode-after", enabledModeSources)
guard let enabledMode = enabledModeSources.first(where: {
    boolProperty($0, kTISPropertyInputSourceIsEnabled)
        && boolProperty($0, kTISPropertyInputSourceIsSelectCapable)
}) else {
    FileHandle.standardError.write(Data("Text Input Services returned success but the mode is not enabled/selectable\n".utf8))
    exit(1)
}

let selectStatus = TISSelectInputSource(enabledMode)
guard selectStatus == noErr else {
    FileHandle.standardError.write(Data("TISSelectInputSource failed with OSStatus \(selectStatus)\n".utf8))
    exit(1)
}

let selectedModeSources = inputSources(property: kTISPropertyInputSourceID, value: modeID).filter {
    stringProperty($0, kTISPropertyInputSourceType) == (kTISTypeKeyboardInputMode as String)
        && stringProperty($0, kTISPropertyBundleID) == bundleID
}
describe("mode-selected", selectedModeSources)
guard selectedModeSources.contains(where: { boolProperty($0, kTISPropertyInputSourceIsSelected) }) else {
    FileHandle.standardError.write(Data("Text Input Services returned success but the mode is not selected\n".utf8))
    exit(1)
}

print("Enabled and selected input mode through Text Input Services: \(modeID)")
