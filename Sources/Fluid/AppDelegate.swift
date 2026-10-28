//
//  AppDelegate.swift
//  Fluid
//
//  Created by Barathwaj Anandan on 9/22/25.
//

import AppKit
import Carbon
import InputMethodKit
import PromiseKit
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var updateCheckTimer: Timer?
    private var didRevealMainWindowOnLaunch = false
    private var didRequestMainWindowReopen = false
    private var shouldSuppressNextReopenActivation = false
    private var wasLaunchedAsLoginItem = false
    private var inputMethodServer: IMKServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Bring up file logging + crash handlers immediately during launch.
        _ = FileLogger.shared
        // Must be read during the launch callback - the current Apple Event identifies
        // login-item launches (used to optionally start silently, see issue #369).
        self.wasLaunchedAsLoginItem = DirectInputMethodRuntime.isEnabled
            ? false
            : Self.detectLoginItemLaunch()
        DebugLogger.shared.info(
            "Application launched [loginItemLaunch=\(self.wasLaunchedAsLoginItem)]",
            source: "AppDelegate"
        )
        if DirectInputMethodRuntime.isEnabled == false {
            UNUserNotificationCenter.current().delegate = self
        }

        if DirectInputMethodRuntime.isEnabled {
            self.registerDirectInputSourceIfNeeded()
            let inputMethodServerReady = self.startDirectInputMethodServer()
            DirectInputSourceCoordinator.shared.start(inputMethodServerReady: inputMethodServerReady)
        }

        // Offline model preseeding: if a model is bundled in the app and the FluidAudio cache is
        // missing it, copy it into place (APFS clone) BEFORE settings/ASR read installed state,
        // so onboarding shows the model as ready without any Hugging Face contact.
        ModelPreseeder.preseedIfNeeded()

        // Input methods stay faceless and must never promote themselves into a foreground app.
        // The ordinary app continues to honor its saved Dock visibility preference.
        if DirectInputMethodRuntime.isEnabled {
            NSApp.setActivationPolicy(.accessory)
        } else {
            SettingsStore.shared.initializeAppSettings()
            LocalAPIServer.shared.start()
        }

        // Record first-open synchronously before async analytics bootstrap so
        // onboarding initialization is deterministic on brand-new installs.
        let isTrueFirstOpen: Bool
        if DirectInputMethodRuntime.isEnabled {
            isTrueFirstOpen = false
        } else {
            isTrueFirstOpen = AnalyticsIdentityStore.shared.ensureFirstOpenRecorded()
        }
        SettingsStore.shared.bootstrapOnboardingState(isTrueFirstOpen: isTrueFirstOpen)
        if DirectInputMethodRuntime.isEnabled {
            SettingsStore.shared.onboardingCompleted = true
            self.hideDirectInputSettingsWindowAfterStartup()
        }

        if DirectInputMethodRuntime.isEnabled == false {
            AnalyticsService.shared.bootstrap()
            if isTrueFirstOpen {
                AnalyticsService.shared.capture(.appFirstOpen)
            }
            AnalyticsService.shared.capture(
                .appOpen,
                properties: ["accessibility_trusted": AccessibilityTrust.isTrusted()]
            )
            // Check for updates automatically if enabled (initial check on launch).
            self.checkForUpdatesAutomatically()
            // Schedule periodic update checks every hour while app is running.
            self.schedulePeriodicUpdateChecks()
        }

        // Login Items can launch hidden; reveal the real SwiftUI window so ContentView startup runs.
        if DirectInputMethodRuntime.isEnabled == false {
            self.openMainWindowOnLaunch()
        }

        // Note: App UI is designed with dark color scheme in mind
        // All gradients and effects are optimized for dark mode
    }

    private func startDirectInputMethodServer() -> Bool {
        guard let connectionName = DirectInputMethodRuntime.connectionName,
              connectionName.isEmpty == false
        else {
            DebugLogger.shared.error(
                "Direct input mode is missing its InputMethodKit connection name",
                source: "AppDelegate"
            )
            return false
        }

        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            DebugLogger.shared.error("Direct input mode is missing its bundle identifier", source: "AppDelegate")
            return false
        }

        // The bundle-based initializer reads InputMethodServerControllerClass from the
        // signed Info.plist and follows the system input-method launch path on macOS 26.
        self.inputMethodServer = IMKServer(name: connectionName, bundleIdentifier: bundleIdentifier)
        DebugLogger.shared.info("Direct input method server started", source: "AppDelegate")
        return self.inputMethodServer != nil
    }

    /// Text Input Services can omit a newly copied per-user input method until the input-method
    /// process presents its own application bundle. Registration is local, idempotent, and adds
    /// no permissions or data transport. System Settings owns the user's enabled and selected
    /// source preferences, which avoids a transient enabled state outside the persisted list.
    private func registerDirectInputSourceIfNeeded() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let modeIdentifier = "\(bundleIdentifier).direct"
        let existingModes = Self.inputSources(
            property: kTISPropertyInputSourceID,
            value: modeIdentifier
        )
        if existingModes.isEmpty == false {
            DebugLogger.shared.info(
                "Direct input source already present in TIS catalog [modes=\(existingModes.count)]",
                source: "AppDelegate"
            )
            return
        }

        let bundleURL = Bundle.main.bundleURL as CFURL
        let status = TISRegisterInputSource(bundleURL)
        guard status == noErr else {
            DebugLogger.shared.error(
                "Direct input source self-registration failed with OSStatus \(status)",
                source: "AppDelegate"
            )
            return
        }

        let parentSources = Self.inputSources(property: kTISPropertyBundleID, value: bundleIdentifier)
        let modeSources = Self.inputSources(property: kTISPropertyInputSourceID, value: modeIdentifier)

        DebugLogger.shared.info(
            "Direct input source registered [parents=\(parentSources.count), modes=\(modeSources.count)]",
            source: "AppDelegate"
        )
    }

    private static func inputSources(property: CFString, value: String) -> [TISInputSource] {
        let filter = [property as String: value] as CFDictionary
        guard let unmanagedList = TISCreateInputSourceList(filter, true) else { return [] }

        let list = unmanagedList.takeRetainedValue()
        return (0..<CFArrayGetCount(list)).map { index in
            unsafeBitCast(CFArrayGetValueAtIndex(list, index), to: TISInputSource.self)
        }
    }

    private func hideDirectInputSettingsWindowAfterStartup() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            for window in NSApp.windows where (window is NSPanel) == false {
                window.orderOut(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DebugLogger.shared.info("Application will terminate", source: "AppDelegate")
        if DirectInputMethodRuntime.isEnabled {
            DirectInputSourceCoordinator.shared.stop()
        }
        self.shutdownPrivateAIRuntimeForTermination()
        if DirectInputMethodRuntime.isEnabled == false {
            LocalAPIServer.shared.stop()
        }
        // Clean up the update check timer
        self.updateCheckTimer?.invalidate()
        self.updateCheckTimer = nil
    }

    private func shutdownPrivateAIRuntimeForTermination() {
        var didFinishShutdown = false
        Task { @MainActor in
            await PrivateAIIntegrationService.shared.shutdownForTermination()
            didFinishShutdown = true
        }

        let deadline = Date().addingTimeInterval(8)
        while !didFinishShutdown, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        if !didFinishShutdown {
            DebugLogger.shared.warning(
                "Timed out waiting for private AI runtime shutdown during termination",
                source: "AppDelegate"
            )
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if self.shouldSuppressNextReopenActivation {
            self.shouldSuppressNextReopenActivation = false
            return true
        }

        // Ensure dock-icon reopen always foregrounds FluidVoice.
        sender.activate(ignoringOtherApps: true)

        return !self.bringMainWindowToFrontIfPresent()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if userInfo[NotificationService.UserInfoKey.kind] as? String == NotificationService.Kind.aiProcessingFallback {
            DispatchQueue.main.async {
                AppNavigationRouter.shared.request(.history)
                self.bringMainWindowToFront()
            }
        }

        completionHandler()
    }

    /// Whether this launch came from macOS Login Items. Reads the launch Apple Event,
    /// which is only valid during applicationDidFinishLaunching.
    /// FLUID_SIMULATE_LOGIN_LAUNCH=1 forces this on for testing, since real login-item
    /// launches can only be produced by logging in.
    private static func detectLoginItemLaunch() -> Bool {
        if ProcessInfo.processInfo.environment["FLUID_SIMULATE_LOGIN_LAUNCH"] == "1" {
            return true
        }
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == AEEventID(kAEOpenApplication)
            && event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
    }

    private func openMainWindowOnLaunch() {
        NSApp.setActivationPolicy(SettingsStore.shared.showInDock ? .regular : .accessory)

        // Users can opt out of showing the window for login-item launches (#369).
        // The window must still be CREATED either way - ContentView's appearance
        // bootstraps the menu bar and services - so the silent path realizes it
        // invisibly instead of skipping it.
        let revealWindow = !self.wasLaunchedAsLoginItem || SettingsStore.shared.showMainWindowAtLoginLaunch

        for delay in [0.1, 0.6, 1.2, 2.5, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                guard self.didRevealMainWindowOnLaunch == false else { return }

                if revealWindow {
                    NSApp.unhide(nil)
                    NSApp.activate(ignoringOtherApps: true)

                    if self.bringMainWindowToFrontIfPresent() {
                        self.didRevealMainWindowOnLaunch = true
                        return
                    }
                } else if self.bootMainWindowHiddenIfPresent() {
                    self.didRevealMainWindowOnLaunch = true
                    return
                }

                DebugLogger.shared.debug("Main window not ready during launch reveal retry", source: "AppDelegate")
                if delay >= 0.6 {
                    self.requestMainWindowReopenIfNeeded(activate: revealWindow)
                }
            }
        }
    }

    /// Realize the main window invisibly so ContentView's startup runs, then order it out.
    /// Used for login-item launches when "Show window when launched at login" is off.
    @discardableResult
    private func bootMainWindowHiddenIfPresent() -> Bool {
        guard let mainWindow = NSApp.windows.first(where: self.isMainWindow) else { return false }

        let originalAlpha = mainWindow.alphaValue
        mainWindow.alphaValue = 0
        mainWindow.orderFrontRegardless()

        // Give ContentView.onAppear time to finish its startup work (menu bar setup plus
        // the delayed service initialization), then put the window away. Alpha is restored
        // so opening it later from the menu bar shows it normally.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak mainWindow] in
            guard let mainWindow, mainWindow.alphaValue <= 0.01 else { return }
            mainWindow.orderOut(nil)
            mainWindow.alphaValue = originalAlpha
            DebugLogger.shared.info(
                "Main window booted hidden (show-at-login-launch disabled)",
                source: "AppDelegate"
            )
        }
        return true
    }

    private func requestMainWindowReopenIfNeeded(activate: Bool = true) {
        guard !self.didRequestMainWindowReopen else { return }
        self.didRequestMainWindowReopen = true

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activate
        if !activate {
            self.shouldSuppressNextReopenActivation = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.shouldSuppressNextReopenActivation = false
            }
        }

        DebugLogger.shared.info("Requesting LaunchServices reopen to create SwiftUI main window", source: "AppDelegate")
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error {
                DebugLogger.shared.error("LaunchServices reopen failed: \(error.localizedDescription)", source: "AppDelegate")
            }
        }
    }

    private func bringMainWindowToFront() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)

        if !self.bringMainWindowToFrontIfPresent() {
            DebugLogger.shared.debug("Main window not ready", source: "AppDelegate")
        }
    }

    @discardableResult
    private func bringMainWindowToFrontIfPresent() -> Bool {
        if let mainWindow = NSApp.windows.first(where: self.isMainWindow) {
            if mainWindow.alphaValue <= 0.01 {
                mainWindow.alphaValue = 1
            }
            mainWindow.orderFrontRegardless()
            mainWindow.makeKeyAndOrderFront(nil)
            DebugLogger.shared.debug("Brought main window to front", source: "AppDelegate")
            return true
        }

        return false
    }

    private func isMainWindow(_ window: NSWindow) -> Bool {
        guard window.level == .normal else { return false }
        guard window.styleMask.contains(.titled) else { return false }
        return window.title == "FluidVoice Local" || window.title.contains("FluidVoice Local")
    }

    // MARK: - Periodic Update Checks

    private func schedulePeriodicUpdateChecks() {
        // Schedule a timer to check for updates every hour (3600 seconds)
        // The actual check logic inside checkForUpdatesAutomatically() handles:
        // - Whether auto-updates are enabled
        // - Whether enough time has passed since last check
        // - Whether the user snoozed the prompt
        self.updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            DebugLogger.shared.debug("Periodic update check timer fired", source: "AppDelegate")
            self?.checkForUpdatesAutomatically()
        }
    }

    // MARK: - Manual Update Check

    @objc func checkForUpdatesManually() {
        // Confirm invocation
        DebugLogger.shared.info("🔎 Manual update check triggered", source: "AppDelegate")

        // Get current app version for debugging
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        DebugLogger.shared.info(
            "Manual update check requested. Current version: \(currentVersion)",
            source: "AppDelegate"
        )
        DebugLogger.shared.info("Checking repository: altic-dev/Fluid-oss", source: "AppDelegate")
        DebugLogger.shared.debug("🔍 DEBUG: Manual update check started - Current version: \(currentVersion)", source: "AppDelegate")
        DebugLogger.shared.debug("🔍 DEBUG: Repository: altic-dev/Fluid-oss", source: "AppDelegate")
        let includePrerelease = SettingsStore.shared.betaReleasesEnabled
        DebugLogger.shared.info(
            "Beta releases opt-in: \(SettingsStore.shared.betaReleasesEnabled)",
            source: "AppDelegate"
        )

        Task { @MainActor in
            do {
                // Use our tolerant updater to handle v-prefixed tags and 2-part versions
                try await SimpleUpdater.shared.checkAndUpdate(
                    owner: "altic-dev",
                    repo: "Fluid-oss",
                    includePrerelease: includePrerelease
                )
                // If we get here, an update was found; SimpleUpdater will relaunch on success
                // Show a quick heads-up before app restarts
                self.showUpdateAlert(
                    title: "Update Found!",
                    message: "A new version is available and will be installed now."
                )
            } catch {
                if let pmkError = error as? PMKError, pmkError.isCancelled {
                    DebugLogger.shared.info("App is already up-to-date", source: "AppDelegate")
                    let isBeta = SettingsStore.shared.betaReleasesEnabled
                    self.showUpdateAlert(
                        title: isBeta ? "No Beta Updates" : "No Updates",
                        message: isBeta
                            ? "You're already running the latest build available in the beta channel."
                            : "You're already running the latest version of FluidVoice Local!"
                    )
                } else {
                    DebugLogger.shared.error("Update check failed: \(error)", source: "AppDelegate")
                    self.showUpdateAlert(
                        title: "Update Check Failed",
                        message: "Unable to check for updates. Please try again later.\n\nError: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    // MARK: - Automatic Update Check

    private func checkForUpdatesAutomatically() {
        // Check if we should perform an automatic update check
        guard SettingsStore.shared.shouldCheckForUpdates() else {
            let reason = !SettingsStore.shared.autoUpdateCheckEnabled ? "disabled by user" : "checked recently"
            DebugLogger.shared.debug("Automatic update check skipped (\(reason))", source: "AppDelegate")
            return
        }

        DebugLogger.shared.info("Scheduling automatic update check...", source: "AppDelegate")

        // Delay check slightly to avoid slowing down app launch
        Task {
            // Wait 3 seconds after launch before checking
            try? await Task.sleep(nanoseconds: 3_000_000_000)

            DebugLogger.shared.info("Performing automatic update check for altic-dev/Fluid-oss", source: "AppDelegate")

            do {
                let includePrerelease = SettingsStore.shared.betaReleasesEnabled
                let result = try await SimpleUpdater.shared.checkForUpdate(
                    owner: "altic-dev",
                    repo: "Fluid-oss",
                    includePrerelease: includePrerelease
                )

                // Update the last check date regardless of result
                await MainActor.run {
                    SettingsStore.shared.updateLastCheckDate()
                }

                if result.hasUpdate {
                    DebugLogger.shared.info("✅ Update available: \(result.latestVersion)", source: "AppDelegate")

                    // Check if user snoozed this version (clicked "Later")
                    if SettingsStore.shared.shouldShowUpdatePrompt(forVersion: result.latestVersion) {
                        // Show update notification on main thread
                        await MainActor.run {
                            self.showUpdateNotification(version: result.latestVersion)
                        }
                    } else {
                        DebugLogger.shared.debug("Update prompt snoozed for \(result.latestVersion), skipping notification", source: "AppDelegate")
                    }
                } else {
                    DebugLogger.shared.info("✅ App is up to date", source: "AppDelegate")
                }
            } catch {
                // Silently log the error, don't bother the user with failed automatic checks
                DebugLogger.shared.debug("Automatic update check failed: \(error.localizedDescription)", source: "AppDelegate")

                // Still update last check date to avoid hammering the API on failure
                await MainActor.run {
                    SettingsStore.shared.updateLastCheckDate()
                }
            }
        }
    }

    @MainActor
    private func showUpdateNotification(version: String) {
        DebugLogger.shared.info("Showing update notification for version \(version)", source: "AppDelegate")

        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "FluidVoice Local \(version) is now available. Would you like to install it now?\n\nThe app will restart automatically after installation."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install Now")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            DebugLogger.shared.info("User chose to install update now", source: "AppDelegate")
            SettingsStore.shared.clearUpdateSnooze() // Clear snooze since they're installing
            self.checkForUpdatesManually()
        } else {
            DebugLogger.shared.info("User postponed update for 24 hours", source: "AppDelegate")
            SettingsStore.shared.snoozeUpdatePrompt(forVersion: version)
        }
    }

    @MainActor
    private func showUpdateAlert(title: String, message: String) {
        DebugLogger.shared.info("🔔 Showing alert: \(title)", source: "AppDelegate")
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
