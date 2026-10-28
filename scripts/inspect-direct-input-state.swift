import Carbon.HIToolbox
import Foundation

private let bundleID = "com.unlockdigital.inputmethod.FluidVoiceHardened"
private let modeID = "com.unlockdigital.inputmethod.FluidVoiceHardened.direct"
private let requireReady = CommandLine.arguments.dropFirst().contains("--require-ready")

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

private func inputSources(property: CFString, value: String) -> [TISInputSource] {
    let filter = [property as String: value] as CFDictionary
    guard let unmanagedList = TISCreateInputSourceList(filter, true) else { return [] }

    let list = unmanagedList.takeRetainedValue()
    return (0..<CFArrayGetCount(list)).map { index in
        unsafeBitCast(CFArrayGetValueAtIndex(list, index), to: TISInputSource.self)
    }
}

private func currentSourceID() -> String? {
    guard let unmanagedSource = TISCopyCurrentKeyboardInputSource() else { return nil }
    return stringProperty(unmanagedSource.takeRetainedValue(), kTISPropertyInputSourceID)
}

private func describe(_ label: String, _ sources: [TISInputSource]) {
    if sources.isEmpty {
        print("\(label).count=0")
        return
    }

    print("\(label).count=\(sources.count)")
    for (index, source) in sources.enumerated() {
        print("\(label)[\(index)].id=\(stringProperty(source, kTISPropertyInputSourceID) ?? "<unavailable>")")
        print("\(label)[\(index)].name=\(stringProperty(source, kTISPropertyLocalizedName) ?? "<unavailable>")")
        print("\(label)[\(index)].enabled=\(boolProperty(source, kTISPropertyInputSourceIsEnabled))")
        print("\(label)[\(index)].selectable=\(boolProperty(source, kTISPropertyInputSourceIsSelectCapable))")
        print("\(label)[\(index)].selected=\(boolProperty(source, kTISPropertyInputSourceIsSelected))")
    }
}

let parentSources = inputSources(property: kTISPropertyBundleID, value: bundleID).filter {
    stringProperty($0, kTISPropertyInputSourceType)
        == (kTISTypeKeyboardInputMethodModeEnabled as String)
}
let modeSources = inputSources(property: kTISPropertyInputSourceID, value: modeID).filter {
    stringProperty($0, kTISPropertyBundleID) == bundleID
        && stringProperty($0, kTISPropertyInputSourceType) == (kTISTypeKeyboardInputMode as String)
}
let currentID = currentSourceID()
let secureInputEnabled = IsSecureEventInputEnabled()

print("current.id=\(currentID ?? "<unavailable>")")
print("secure_input=\(secureInputEnabled)")
describe("parent", parentSources)
describe("mode", modeSources)

let parentReady = parentSources.count == 1
    && boolProperty(parentSources[0], kTISPropertyInputSourceIsEnabled)
let modeReady = modeSources.count == 1
    && boolProperty(modeSources[0], kTISPropertyInputSourceIsEnabled)
    && boolProperty(modeSources[0], kTISPropertyInputSourceIsSelectCapable)
    && boolProperty(modeSources[0], kTISPropertyInputSourceIsSelected)
let ready = parentReady && modeReady && currentID == modeID && !secureInputEnabled

print("ready=\(ready)")
if requireReady && !ready {
    exit(1)
}
