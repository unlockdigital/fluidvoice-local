import AppKit
import Carbon
import Darwin
import Foundation
import IOKit
import OSLog

extension Notification.Name {
    static let fluidVoiceDirectInputSourceStateChanged = Notification.Name(
        "FluidVoiceDirectInputSourceStateChanged"
    )
}

/// Keeps the dedicated FluidVoice input mode current after macOS temporarily switches to the
/// underlying U.S. layout.
///
/// The coordinator uses documented Text Input Services APIs inside the existing input-method
/// process. It pauses while Secure Event Input is active, then restores FluidVoice after secure
/// input clears. Repair attempts are coalesced, stability-checked, and bounded. This adds no
/// process, entitlement, event tap, Accessibility request, Input Monitoring request, or network
/// surface.
@MainActor
final class DirectInputSourceCoordinator {
    enum State: Equatable {
        case active
        case secureInput
        case restoring
        case inactive
        case unavailable
    }

    struct SecureInputOwner: Equatable {
        let processIdentifier: pid_t
        let applicationName: String
        let bundleIdentifier: String?
        let bundleURL: URL?
        let isRunning: Bool
    }

    static let shared = DirectInputSourceCoordinator()

    private let bundleID = "com.unlockdigital.inputmethod.FluidVoiceHardened"
    private let modeID = "com.unlockdigital.inputmethod.FluidVoiceHardened.direct"
    private let knownFallbackSourceIDs: Set<String> = ["com.apple.keylayout.US"]
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.unlockdigital.inputmethod.FluidVoiceHardened",
        category: "DirectInputSource"
    )
    private let healthCheckInterval: TimeInterval = 5
    private let stabilityCheckDelay: TimeInterval = 1.5
    private let repairAttemptWindow: TimeInterval = 30
    private let maximumRepairAttempts = 3

    private var healthTimer: Timer?
    private var distributedObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pendingReconcileTask: Task<Void, Never>?
    private var stabilityCheckTask: Task<Void, Never>?
    private var repairAttemptTimes: [TimeInterval] = []
    private var repairInFlight = false
    private var sessionIsActive = true
    private var hasStarted = false

    private(set) var state: State = .restoring {
        didSet {
            guard self.state != oldValue else { return }
            NotificationCenter.default.post(
                name: .fluidVoiceDirectInputSourceStateChanged,
                object: self
            )
        }
    }

    private init() {}

    var menuStatusTitle: String? {
        switch self.state {
        case .active:
            return nil
        case .secureInput:
            if let owner = self.secureInputOwner() {
                return owner.isRunning
                    ? "Paused by \(owner.applicationName) Secure Input"
                    : "macOS Secure Input Is Stuck"
            }
            return "Paused by macOS Secure Input"
        case .restoring:
            return "Restoring FluidVoice Local Input..."
        case .inactive:
            return "FluidVoice Local Input Source Not Selected"
        case .unavailable:
            return "FluidVoice Local Input Source Unavailable"
        }
    }

    func start(inputMethodServerReady: Bool) {
        guard DirectInputMethodRuntime.isEnabled, self.hasStarted == false else { return }
        self.hasStarted = true
        self.logger.notice(
            "Direct input source coordinator started; inputMethodServerReady=\(inputMethodServerReady, privacy: .public)"
        )

        if let notificationName = kTISNotifySelectedKeyboardInputSourceChanged {
            self.distributedObserver = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(notificationName as String),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.repairInFlight == false else { return }
                    self.scheduleReconcile(reason: "selected-source-changed", delay: 0.1)
                }
            }
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        self.workspaceObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.resumeAndReconcile(reason: "workspace-woke")
                }
            }
        )
        self.workspaceObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.sessionDidBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.sessionIsActive = true
                    self?.resumeAndReconcile(reason: "session-became-active")
                }
            }
        )
        self.workspaceObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.sessionDidResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.pauseForInactiveSession()
                }
            }
        )

        let timer = Timer(timeInterval: self.healthCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.repairInFlight == false else { return }
                self.reconcile(reason: "health-check")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.healthTimer = timer

        // Selection repair remains useful when the first IMKServer construction returns nil.
        // Selecting the enabled mode asks macOS to reconnect the installed input-method server.
        self.scheduleReconcile(reason: "startup", delay: 0.25)
    }

    func stop() {
        self.healthTimer?.invalidate()
        self.healthTimer = nil
        self.pendingReconcileTask?.cancel()
        self.pendingReconcileTask = nil
        self.stabilityCheckTask?.cancel()
        self.stabilityCheckTask = nil
        self.repairInFlight = false

        if let distributedObserver = self.distributedObserver {
            DistributedNotificationCenter.default().removeObserver(distributedObserver)
            self.distributedObserver = nil
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in self.workspaceObservers {
            workspaceCenter.removeObserver(observer)
        }
        self.workspaceObservers.removeAll()
        self.hasStarted = false
    }

    /// Refreshes menu state without changing the system input source.
    @discardableResult
    func refreshState(reason: String) -> Bool {
        guard DirectInputMethodRuntime.isEnabled else { return false }

        let currentID = self.currentInputSourceID()
        if currentID == self.modeID {
            if self.repairInFlight == false {
                self.state = .active
            }
            return true
        }

        if IsSecureEventInputEnabled() {
            self.state = .secureInput
            return false
        }

        if self.state != .unavailable {
            self.state = .inactive
        }
        self.logger.debug(
            "Direct input source observed inactive; reason=\(reason, privacy: .public) current=\(currentID ?? "<unavailable>", privacy: .public)"
        )
        return false
    }

    /// Requests a user-initiated restore and resets the bounded automatic-repair budget.
    func requestRestore() {
        self.resetRepairBudget()
        self.scheduleReconcile(reason: "manual-restore", delay: 0)
    }

    var secureInputIsActive: Bool {
        IsSecureEventInputEnabled()
    }

    /// Identifies the application recorded by the active macOS GUI session as the Secure Input
    /// owner. This is read-only process context used to give the owner a concrete recovery path.
    func secureInputOwner() -> SecureInputOwner? {
        guard self.secureInputIsActive, let ownerPID = self.secureInputOwnerPID() else {
            return nil
        }

        let application = NSRunningApplication(processIdentifier: ownerPID)
        return SecureInputOwner(
            processIdentifier: ownerPID,
            applicationName: application?.localizedName ?? "Application (PID \(ownerPID))",
            bundleIdentifier: application?.bundleIdentifier,
            bundleURL: application?.bundleURL,
            isRunning: self.processIsAlive(ownerPID) && application?.isTerminated != true
        )
    }

    /// Reconciles the live TIS source. Returns true only when FluidVoice is already current.
    @discardableResult
    func reconcile(reason: String) -> Bool {
        guard DirectInputMethodRuntime.isEnabled, self.sessionIsActive else { return false }

        let currentID = self.currentInputSourceID()
        if currentID == self.modeID {
            if self.repairInFlight == false {
                self.state = .active
                self.resetRepairBudget()
            }
            return true
        }

        guard IsSecureEventInputEnabled() == false else {
            self.cancelPendingRepairs()
            self.state = .secureInput
            return false
        }

        let isManualRestore = reason == "manual-restore"
        guard isManualRestore || currentID.map(self.knownFallbackSourceIDs.contains) == true else {
            self.state = .inactive
            return false
        }

        guard self.repairInFlight == false else { return false }
        self.pruneRepairAttempts()
        guard self.repairAttemptTimes.count < self.maximumRepairAttempts else {
            self.state = .unavailable
            self.logger.error(
                "Direct input restoration paused after bounded attempts; current=\(currentID ?? "<unavailable>", privacy: .public)"
            )
            return false
        }

        self.repairAttemptTimes.append(ProcessInfo.processInfo.systemUptime)
        let attemptNumber = self.repairAttemptTimes.count
        self.repairInFlight = true
        self.state = .restoring

        guard IsSecureEventInputEnabled() == false else {
            self.repairInFlight = false
            self.state = .secureInput
            return false
        }

        guard let mode = self.directModeSource() else {
            self.finishFailedAttempt(
                "Direct input mode is unavailable in the TIS catalog",
                observedCurrentID: currentID
            )
            return false
        }

        let selectStatus = TISSelectInputSource(mode)
        guard selectStatus == noErr else {
            self.finishFailedAttempt(
                "Direct input source restoration failed with OSStatus \(selectStatus)",
                observedCurrentID: currentID
            )
            return false
        }

        self.logger.notice(
            "Direct input restoration requested; reason=\(reason, privacy: .public) attempt=\(attemptNumber) current=\(currentID ?? "<unavailable>", privacy: .public)"
        )
        self.scheduleStabilityCheck(reason: reason, attemptNumber: attemptNumber)
        return false
    }

    private func resumeAndReconcile(reason: String) {
        self.sessionIsActive = true
        self.resetRepairBudget()
        self.scheduleReconcile(reason: reason, delay: 0.25)
    }

    private func pauseForInactiveSession() {
        self.sessionIsActive = false
        self.cancelPendingRepairs()
        self.state = .inactive
    }

    private func scheduleReconcile(reason: String, delay: TimeInterval) {
        self.pendingReconcileTask?.cancel()
        self.pendingReconcileTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            } catch {
                return
            }
            guard Task.isCancelled == false, let self else { return }
            self.pendingReconcileTask = nil
            self.reconcile(reason: reason)
        }
    }

    private func scheduleStabilityCheck(reason: String, attemptNumber: Int) {
        self.stabilityCheckTask?.cancel()
        self.stabilityCheckTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(self.stabilityCheckDelay * 1_000_000_000)
                )
            } catch {
                return
            }
            guard Task.isCancelled == false else { return }
            self.stabilityCheckTask = nil
            self.completeStabilityCheck(reason: reason, attemptNumber: attemptNumber)
        }
    }

    private func completeStabilityCheck(reason: String, attemptNumber: Int) {
        guard self.repairInFlight else { return }

        if IsSecureEventInputEnabled() {
            self.repairInFlight = false
            self.state = .secureInput
            return
        }

        let currentID = self.currentInputSourceID()
        if currentID == self.modeID, self.directModeIsSelected() {
            self.repairInFlight = false
            self.resetRepairBudget()
            self.state = .active
            self.logger.notice(
                "Direct input source stable; reason=\(reason, privacy: .public) attempt=\(attemptNumber)"
            )
            return
        }

        self.finishFailedAttempt(
            "Direct input source did not remain stable",
            observedCurrentID: currentID
        )
    }

    private func finishFailedAttempt(_ message: String, observedCurrentID: String?) {
        self.repairInFlight = false
        self.pruneRepairAttempts()
        let attemptCount = self.repairAttemptTimes.count
        self.logger.error(
            "\(message, privacy: .public); attempt=\(attemptCount) current=\(observedCurrentID ?? "<unavailable>", privacy: .public)"
        )

        guard attemptCount < self.maximumRepairAttempts else {
            self.state = .unavailable
            return
        }

        guard observedCurrentID.map(self.knownFallbackSourceIDs.contains) == true else {
            self.state = .inactive
            return
        }

        self.state = .restoring
        let backoff = TimeInterval(1 << max(0, attemptCount - 1))
        self.scheduleReconcile(reason: "stability-retry", delay: backoff)
    }

    private func cancelPendingRepairs() {
        self.pendingReconcileTask?.cancel()
        self.pendingReconcileTask = nil
        self.stabilityCheckTask?.cancel()
        self.stabilityCheckTask = nil
        self.repairInFlight = false
    }

    private func resetRepairBudget() {
        self.repairAttemptTimes.removeAll()
    }

    private func pruneRepairAttempts() {
        let cutoff = ProcessInfo.processInfo.systemUptime - self.repairAttemptWindow
        self.repairAttemptTimes.removeAll(where: { $0 < cutoff })
    }

    private func currentInputSourceID() -> String? {
        guard let unmanagedSource = TISCopyCurrentKeyboardInputSource() else { return nil }
        return self.stringProperty(unmanagedSource.takeRetainedValue(), kTISPropertyInputSourceID)
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

    private func directModeIsSelected() -> Bool {
        guard let mode = self.directModeSource() else { return false }
        return self.boolProperty(mode, kTISPropertyInputSourceIsSelected)
    }

    private func directModeSource() -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: self.modeID] as CFDictionary
        guard let unmanagedList = TISCreateInputSourceList(filter, true) else { return nil }

        let list = unmanagedList.takeRetainedValue()
        let sources = (0..<CFArrayGetCount(list)).map { index in
            unsafeBitCast(CFArrayGetValueAtIndex(list, index), to: TISInputSource.self)
        }

        return sources.first { source in
            self.stringProperty(source, kTISPropertyBundleID) == self.bundleID
                && self.stringProperty(source, kTISPropertyInputSourceType)
                    == (kTISTypeKeyboardInputMode as String)
                && self.boolProperty(source, kTISPropertyInputSourceIsEnabled)
                && self.boolProperty(source, kTISPropertyInputSourceIsSelectCapable)
        }
    }

    private func sourceProperty(_ source: TISInputSource, _ key: CFString) -> AnyObject? {
        guard let rawValue = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(rawValue).takeUnretainedValue()
    }

    private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        self.sourceProperty(source, key) as? String
    }

    private func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
        (self.sourceProperty(source, key) as? Bool) == true
    }
}
