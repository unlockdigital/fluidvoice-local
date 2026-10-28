//
//  OverlayScreenResolver.swift
//  Fluid
//

import AppKit
import OSLog

@MainActor
enum OverlayScreenResolver {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.unlockdigital.inputmethod.FluidVoiceHardened",
        category: "Overlay"
    )

    static func screenForActiveContext() -> NSScreen? {
        if DirectInputMethodRuntime.isEnabled,
           let clientScreen = DirectInputMethodBridge.shared.activeClientScreen()
        {
            self.logger.notice(
                "Overlay screen resolved from InputMethodKit client; screen=\(clientScreen.localizedName, privacy: .public)"
            )
            return clientScreen
        }

        if DirectInputMethodRuntime.isEnabled, let mainScreen = NSScreen.main {
            self.logger.notice(
                "Overlay screen used direct-input main-screen fallback; screen=\(mainScreen.localizedName, privacy: .public)"
            )
            return mainScreen
        }

        return self.screenForCurrentPointer()
    }

    static func screenForCurrentPointer() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(location)
        } ?? NSScreen.main ?? NSScreen.screens.first
    }
}
