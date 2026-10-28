import AppKit
import CoreGraphics
import Foundation

private let bundleID = "com.unlockdigital.inputmethod.FluidVoiceHardened"
private let canonicalBundlePath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Input Methods/FluidVoice Direct Input.app", isDirectory: true)
    .standardizedFileURL
    .resolvingSymlinksInPath()

private let duration = max(
    1,
    CommandLine.arguments.dropFirst().first.flatMap(Double.init) ?? 30
)
private let deadline = Date().addingTimeInterval(duration)
private var previousSnapshot = ""

private func screenSnapshot() -> String {
    var lines = [
        "mouse=x=\(Int(NSEvent.mouseLocation.x)) y=\(Int(NSEvent.mouseLocation.y))",
        "screens=\(NSScreen.screens.count)",
    ]
    for (index, screen) in NSScreen.screens.enumerated() {
        let frame = screen.frame
        let visible = screen.visibleFrame
        lines.append(
            "screen[\(index)]=\(screen.localizedName) frame=x=\(Int(frame.minX)) y=\(Int(frame.minY)) width=\(Int(frame.width)) height=\(Int(frame.height)) visible=x=\(Int(visible.minX)) y=\(Int(visible.minY)) width=\(Int(visible.width)) height=\(Int(visible.height))"
        )
    }
    return lines.joined(separator: "\n")
}

private func canonicalRuntime() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { app in
        app.bundleURL?
            .standardizedFileURL
            .resolvingSymlinksInPath() == canonicalBundlePath
    }
}

private func stringValue(_ value: Any?) -> String {
    switch value {
    case let boolean as Bool:
        return String(boolean)
    case let number as NSNumber:
        return number.stringValue
    case let string as String:
        return string
    default:
        return "<unavailable>"
    }
}

private func boundsValue(_ value: Any?) -> String {
    guard let dictionary = value as? NSDictionary else { return "<unavailable>" }
    var bounds = CGRect.zero
    guard CGRectMakeWithDictionaryRepresentation(dictionary as CFDictionary, &bounds) else {
        return "<unavailable>"
    }
    return "x=\(Int(bounds.origin.x)) y=\(Int(bounds.origin.y)) width=\(Int(bounds.width)) height=\(Int(bounds.height))"
}

private func snapshot(for processID: pid_t) -> String {
    guard let rawWindows = CGWindowListCopyWindowInfo(
        [.optionAll, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]] else {
        return "windows=<unavailable>"
    }

    let windows = rawWindows
        .filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processID }
        .sorted {
            (($0[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0)
                < (($1[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0)
        }

    var lines = ["windows=\(windows.count)"]
    for window in windows {
        let number = stringValue(window[kCGWindowNumber as String])
        let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue.description
            ?? "<unavailable>"
        let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue.description
            ?? "<unavailable>"
        let onScreen = stringValue(window[kCGWindowIsOnscreen as String])
        let bounds = boundsValue(window[kCGWindowBounds as String])
        lines.append(
            "window=\(number) layer=\(layer) alpha=\(alpha) on_screen=\(onScreen) bounds=\(bounds)"
        )
    }
    return lines.joined(separator: "\n")
}

while Date() < deadline {
    guard let runtime = canonicalRuntime() else {
        if previousSnapshot != "runtime=<unavailable>" {
            print("timestamp=\(ISO8601DateFormatter().string(from: Date()))")
            print("runtime=<unavailable>")
            previousSnapshot = "runtime=<unavailable>"
        }
        Thread.sleep(forTimeInterval: 0.25)
        continue
    }

    let currentSnapshot = "pid=\(runtime.processIdentifier) activation_policy=\(runtime.activationPolicy.rawValue)\n"
        + screenSnapshot() + "\n" + snapshot(for: runtime.processIdentifier)
    if currentSnapshot != previousSnapshot {
        print("timestamp=\(ISO8601DateFormatter().string(from: Date()))")
        print(currentSnapshot)
        fflush(stdout)
        previousSnapshot = currentSnapshot
    }
    Thread.sleep(forTimeInterval: 0.25)
}
