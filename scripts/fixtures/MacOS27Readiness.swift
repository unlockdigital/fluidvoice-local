// Standalone read-only probe and deterministic report fixtures. No production imports.
import Carbon.HIToolbox
import Darwin
import Foundation
import Security

private let bundleID = "com.unlockdigital.inputmethod.FluidVoiceHardened"
private let modeID = "com.unlockdigital.inputmethod.FluidVoiceHardened.direct"

private enum State: String { case observed = "OBSERVED", attention = "ATTENTION", unavailable = "UNAVAILABLE" }
private struct Check {
    let name: String
    let state: State
    let detail: String
}
private enum Installation { case matching, missing, unavailable, mismatch, redirected }
private enum Integrity { case valid, invalid, unavailable, skipped }
private struct Catalog {
    var count: Int?
    var enabled: Bool?
    var selectable: Bool?
    var selected: Bool?
}
private struct Facts {
    var version: OperatingSystemVersion
    var installation: Installation
    var metadata: Bool?
    var integrity: Integrity
    var microphoneOnly: Bool?
    var knownPrivateHelperAbsent: Bool?
    var parent: Catalog
    var mode: Catalog
}

private func booleanCheck(_ name: String, _ value: Bool?, yes: String, no: String) -> Check {
    guard let value else { return Check(name: name, state: .unavailable, detail: "Observation unavailable or prerequisite unmet.") }
    return Check(name: name, state: value ? .observed : .attention, detail: value ? yes : no)
}

private func checks(_ facts: Facts) -> [Check] {
    let version = facts.version
    var rows = [Check(name: "host", state: version.majorVersion == 27 ? .observed : .attention,
                      detail: "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion); "
                        + (version.majorVersion == 27 ? "target major observed." : "host mismatch; macOS 27 required."))]
    let install: Check
    switch facts.installation {
    case .matching: install = Check(name: "installation", state: .observed, detail: "Canonical per-user bundle and identifier observed.")
    case .missing: install = Check(name: "installation", state: .attention, detail: "Canonical per-user bundle absent.")
    case .unavailable: install = Check(name: "installation", state: .unavailable, detail: "Canonical per-user bundle inspection unavailable.")
    case .mismatch: install = Check(name: "installation", state: .attention, detail: "Canonical location has unexpected bundle metadata.")
    case .redirected: install = Check(name: "installation", state: .attention, detail: "Canonical bundle or inspected component redirects outside its expected location; inspection skipped.")
    }
    rows.append(install)
    rows.append(booleanCheck("imk-metadata", facts.metadata,
                             yes: "Canonical mode, connection, controller and UI-agent metadata observed.",
                             no: "InputMethodKit or UI-agent metadata requires review."))
    switch facts.integrity {
    case .valid: rows.append(Check(name: "signature-integrity", state: .observed, detail: "Strict static signature check succeeded for all architectures and nested code in standard locations; canonical signing identifier matched."))
    case .invalid: rows.append(Check(name: "signature-integrity", state: .attention, detail: "Static signature integrity or canonical signing identifier check failed."))
    case .unavailable, .skipped: rows.append(Check(name: "signature-integrity", state: .unavailable, detail: "Static signature inspection unavailable or prerequisite unmet."))
    }
    rows.append(booleanCheck("signed-entitlements", facts.microphoneOnly,
                             yes: "Inspected native-slice entitlement dictionary contains only microphone input.",
                             no: "Inspected entitlement dictionary differs from the microphone-only boundary."))
    rows.append(booleanCheck("known-private-helper", facts.knownPrivateHelperAbsent,
                             yes: "Known private FI helper path absent; complete artifact inventory review remains required.",
                             no: "Known private FI helper path present; OSS artifact review required."))
    for (label, catalog) in [("parent", facts.parent), ("mode", facts.mode)] {
        if let count = catalog.count {
            rows.append(Check(name: "\(label)-catalog", state: count == 1 ? .observed : .attention,
                              detail: "Canonical matches: \(count); exactly one required."))
        } else {
            rows.append(Check(name: "\(label)-catalog", state: .unavailable, detail: "Filtered Text Input Services query unavailable."))
        }
        rows.append(booleanCheck("\(label)-enabled", catalog.count == 1 ? catalog.enabled : nil,
                                 yes: "Canonical source enabled flag observed.", no: "Canonical source enabled flag is false."))
    }
    rows.append(booleanCheck("mode-selectable", facts.mode.count == 1 ? facts.mode.selectable : nil,
                             yes: "Canonical mode select-capable flag observed.", no: "Canonical mode select-capable flag is false."))
    rows.append(booleanCheck("mode-selected", facts.mode.count == 1 ? facts.mode.selected : nil,
                             yes: "Canonical mode selected flag observed at this instant.", no: "Canonical mode selected flag is false."))
    return rows
}

private func report(_ facts: Facts, fixture: String?) -> String {
    let rows = checks(facts)
    let summary = rows.allSatisfy { $0.state == .observed } ? "observations-complete" : "attention-or-unavailable"
    let versionMatches = facts.version.majorVersion == 27
    return ([
        "# FluidVoice Local macOS 27 readiness",
        "",
        "Evidence: \(fixture.map { "SIMULATED fixture \($0); host checks skipped" } ?? "LIVE read-only observations")",
        "Bundle: \(bundleID)",
        "Mode: \(modeID)",
        "Host scope: \(versionMatches ? "target-major-observed" : "HOST-MISMATCH")",
        "Read-only readiness: \(summary)",
        "Qualification: PENDING_PHYSICAL_ACCEPTANCE",
        "",
        "| Check | Status | Observation |",
        "| --- | --- | --- |"
    ] + rows.map { "| \($0.name) | \($0.state.rawValue) | \($0.detail) |" } + [
        "",
        "UNAVAILABLE: catalog-to-bundle-path binding, complete artifact provenance, trusted publisher/notarization, cross-slice entitlement equivalence and full private-runtime inventory require separate review.",
        "UNAVAILABLE: documented macOS 27 activation route and guardian lifecycle compatibility require target-host validation.",
        "REQUIRED: native Right Option toggle, horizontal live panel, insertion once, Globe, Secure Input, relaunch/login/sleep, VoiceOver, application/device matrix and rollback acceptance.",
        "Permission boundary: microphone-only. Permission state and document/keyboard contents are outside this probe's observations.",
        "Snapshot limits: catalog and bundle reads are separate observations; concurrent changes can invalidate them. Process presence and source scans establish no physical acceptance.",
        "Exit 3: qualification pending."
    ]).joined(separator: "\n") + "\n"
}

private func property(_ source: TISInputSource, _ key: CFString) -> AnyObject? {
    guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
}

private func catalog(mode: Bool) -> Catalog {
    let filter = [kTISPropertyBundleID as String: bundleID]
        .merging(mode ? [kTISPropertyInputSourceID as String: modeID] : [:]) { _, new in new }
    guard let raw = TISCreateInputSourceList(filter as CFDictionary, true) else {
        return Catalog()
    }
    let list = raw.takeRetainedValue()
    let sources: [TISInputSource] = (0..<CFArrayGetCount(list)).map {
        unsafeBitCast(CFArrayGetValueAtIndex(list, $0), to: TISInputSource.self)
    }.filter {
        (property($0, kTISPropertyBundleID) as? String) == bundleID
            && (property($0, kTISPropertyInputSourceType) as? String)
                == ((mode ? kTISTypeKeyboardInputMode : kTISTypeKeyboardInputMethodModeEnabled) as String)
            && (!mode || (property($0, kTISPropertyInputSourceID) as? String) == modeID)
    }
    guard sources.count == 1, let source = sources.first else { return Catalog(count: sources.count) }
    return Catalog(count: 1,
                   enabled: property(source, kTISPropertyInputSourceIsEnabled) as? Bool,
                   selectable: property(source, kTISPropertyInputSourceIsSelectCapable) as? Bool,
                   selected: property(source, kTISPropertyInputSourceIsSelected) as? Bool)
}

private func missing(_ error: Error) -> Bool {
    let value = error as NSError
    return value.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(value.code)
}

private func inspectInstallation(_ facts: inout Facts) {
    let app = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
        .appendingPathComponent("Library/Input Methods/FluidVoice Direct Input.app", isDirectory: true)
        .standardizedFileURL
    guard app.resolvingSymlinksInPath() == app else { facts.installation = .redirected; return }
    do {
        guard try app.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            facts.installation = .mismatch; return
        }
    } catch { facts.installation = missing(error) ? .missing : .unavailable; return }
    let plist = app.appendingPathComponent("Contents/Info.plist")
    guard plist.resolvingSymlinksInPath().path.hasPrefix(app.path + "/") else {
        facts.installation = .redirected; return
    }
    let info: [String: Any]
    do {
        guard let parsed = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as? [String: Any] else {
            facts.installation = .mismatch; return
        }
        info = parsed
    } catch { facts.installation = .unavailable; return }
    guard info["CFBundleIdentifier"] as? String == bundleID else { facts.installation = .mismatch; return }
    facts.installation = .matching
    let component = info["ComponentInputModeDict"] as? [String: Any]
    let modes = component?["tsInputModeListKey"] as? [String: Any]
    let direct = modes?[modeID] as? [String: Any]
    facts.metadata = info["FluidVoiceDirectInputMode"] as? Bool == true
        && info["LSUIElement"] as? Bool == true && info["LSBackgroundOnly"] == nil
        && info["InputMethodConnectionName"] as? String == bundleID + "_Connection"
        && info["InputMethodServerControllerClass"] as? String == "FluidVoiceInputController"
        && info["InputMethodServerDelegateClass"] as? String == "FluidVoiceInputController"
        && direct?["TISInputSourceID"] as? String == modeID

    let helper = app.appendingPathComponent("Contents/Helpers/fluid-intelligence-mlx")
    do {
        _ = try helper.resourceValues(forKeys: [.isRegularFileKey])
        facts.knownPrivateHelperAbsent = false
    } catch { facts.knownPrivateHelperAbsent = missing(error) ? true : nil }

    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else {
        facts.integrity = .unavailable; return
    }
    var requirement: SecRequirement?
    guard SecRequirementCreateWithString("identifier \"\(bundleID)\"" as CFString, [], &requirement) == errSecSuccess,
          let requirement else { facts.integrity = .unavailable; return }
    // Public static APIs; no network access, launches, trust prompts or signing changes.
    let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode
                           | kSecCSStrictValidate).union(.noNetworkAccess)
    facts.integrity = SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess ? .valid : .invalid
    var signingInfo: CFDictionary?
    if SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInfo) == errSecSuccess,
       let signing = signingInfo as? [String: Any],
       let entitlements = signing[kSecCodeInfoEntitlementsDict as String] as? [String: Any] {
        facts.microphoneOnly = entitlements.count == 1
            && entitlements["com.apple.security.device.audio-input"] as? Bool == true
    }
}

private func liveFacts() -> Facts {
    var facts = Facts(version: ProcessInfo.processInfo.operatingSystemVersion,
                      installation: .unavailable, integrity: .skipped, parent: Catalog(), mode: Catalog())
    inspectInstallation(&facts)
    facts.parent = catalog(mode: false)
    facts.mode = catalog(mode: true)
    return facts
}

private let fixtureNames = ["host26", "observed27", "missing27", "invalid27", "unavailable27", "duplicate27", "incomplete27", "disabled27"]
private func fixture(_ name: String) -> Facts {
    var facts = Facts(version: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1),
                      installation: .matching, metadata: true, integrity: .valid, microphoneOnly: true,
                      knownPrivateHelperAbsent: true,
                      parent: Catalog(count: 1, enabled: true),
                      mode: Catalog(count: 1, enabled: true, selectable: true, selected: true))
    switch name {
    case "host26": facts.version = OperatingSystemVersion(majorVersion: 26, minorVersion: 5, patchVersion: 0)
    case "missing27": facts.installation = .missing; facts.metadata = nil; facts.integrity = .skipped
        facts.microphoneOnly = nil; facts.knownPrivateHelperAbsent = nil
        facts.parent = Catalog(count: 0); facts.mode = Catalog(count: 0)
    case "invalid27": facts.integrity = .invalid; facts.microphoneOnly = false; facts.knownPrivateHelperAbsent = false
    case "unavailable27": facts.installation = .unavailable; facts.metadata = nil; facts.integrity = .unavailable
        facts.microphoneOnly = nil; facts.knownPrivateHelperAbsent = nil; facts.parent = Catalog(); facts.mode = Catalog()
    case "duplicate27": facts.parent.count = 2; facts.mode.count = 2
    case "incomplete27": facts.mode.selectable = nil; facts.mode.selected = nil
    case "disabled27": facts.parent.enabled = false; facts.mode.enabled = false
        facts.mode.selectable = false; facts.mode.selected = false
    default: break
    }
    return facts
}

private func selfTest() -> Bool {
    for name in fixtureNames {
        let facts = fixture(name)
        let text = report(facts, fixture: name)
        guard text == report(facts, fixture: name), text.contains("SIMULATED fixture \(name)"),
              text.contains("Qualification: PENDING_PHYSICAL_ACCEPTANCE"), !text.contains("PASS"),
              !text.contains("/Users/"), !text.contains("file://"),
              text.contains(name == "host26" ? "Host scope: HOST-MISMATCH" : "Host scope: target-major-observed"),
              text.contains(name == "observed27" ? "Read-only readiness: observations-complete" : "Read-only readiness: attention-or-unavailable") else { return false }
    }
    let unavailable = checks(fixture("unavailable27"))
    guard unavailable.contains(where: { $0.name == "mode-catalog" && $0.state == .unavailable }),
          checks(fixture("missing27")).contains(where: { $0.name == "mode-catalog" && $0.state == .attention }),
          checks(fixture("incomplete27")).contains(where: { $0.name == "mode-selected" && $0.state == .unavailable }),
          checks(fixture("disabled27")).contains(where: { $0.name == "mode-selected" && $0.state == .attention }),
          checks(fixture("duplicate27")).contains(where: { $0.name == "mode-selected" && $0.state == .unavailable }) else { return false }
    for installation in [Installation.mismatch, .redirected] {
        var facts = fixture("observed27"); facts.installation = installation
        guard checks(facts).contains(where: { $0.name == "installation" && $0.state == .attention }) else { return false }
    }
    return true
}

@main
private enum MacOS27Readiness {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--self-test"] {
            guard selfTest() else { print("Deterministic readiness report checks failed."); exit(2) }
            print("Deterministic readiness report checks succeeded (8 scenarios plus installation warning cases).")
            exit(0)
        }
        if args.count == 2, args[0] == "--fixture", fixtureNames.contains(args[1]) {
            print(report(fixture(args[1]), fixture: args[1]), terminator: ""); exit(3)
        }
        guard args.isEmpty else { exit(2) }
        print(report(liveFacts(), fixture: nil), terminator: "")
        exit(3)
    }
}
