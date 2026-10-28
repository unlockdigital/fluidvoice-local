import AppKit
import Foundation
import InputMethodKit
import OSLog

/// Runtime switch and in-process handoff used by the dedicated macOS input-source build.
///
/// The direct-input build receives a focused app's `IMKTextInput` client from macOS. Final
/// transcripts travel from ASR to that client inside this process. This path uses the
/// InputMethodKit client for insertion and caret context, with no global event tap or transcript IPC.
enum DirectInputMethodRuntime {
    static let isEnabled =
        Bundle.main.object(forInfoDictionaryKey: "FluidVoiceDirectInputMode") as? Bool == true

    static let connectionName =
        Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String
}

/// Centralizes legacy Accessibility trust checks so the input-source runtime can fail closed.
enum AccessibilityTrust {
    static func isTrusted() -> Bool {
        guard DirectInputMethodRuntime.isEnabled == false else { return false }
        return AXIsProcessTrusted()
    }
}

extension Notification.Name {
    static let fluidVoiceDirectInputClientAvailabilityChanged = Notification.Name(
        "FluidVoiceDirectInputClientAvailabilityChanged"
    )
}

final class DirectInputMethodBridge {
    static let shared = DirectInputMethodBridge()

    private let lock = NSLock()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.unlockdigital.inputmethod.FluidVoiceHardened",
        category: "DirectInput"
    )
    private weak var activeController: FluidVoiceInputController?
    private var toggleHandler: (() -> Void)?

    private init() {}

    var hasActiveClient: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.activeController != nil
    }

    func configureToggleHandler(_ handler: @escaping () -> Void) {
        self.lock.lock()
        self.toggleHandler = handler
        self.lock.unlock()
        self.logger.notice("Direct-input toggle handler configured")
    }

    func activate(_ controller: FluidVoiceInputController) {
        self.lock.lock()
        self.activeController = controller
        self.lock.unlock()
        self.logger.notice("Direct-input client activated")
        NotificationCenter.default.post(name: .fluidVoiceDirectInputClientAvailabilityChanged, object: nil)
    }

    func deactivate(_ controller: FluidVoiceInputController) {
        self.lock.lock()
        if self.activeController === controller {
            self.activeController = nil
        }
        self.lock.unlock()
        self.logger.notice("Direct-input client deactivated")
        NotificationCenter.default.post(name: .fluidVoiceDirectInputClientAvailabilityChanged, object: nil)
    }

    /// Inserts at the current selection through the active InputMethodKit client.
    /// Returns true once the transcript has been accepted for main-thread delivery.
    @discardableResult
    func insert(_ text: String) -> Bool {
        self.lock.lock()
        let controller = self.activeController
        self.lock.unlock()

        guard let controller else { return false }

        self.logger.notice("Direct-input transcript accepted for delivery; characters=\(text.count, privacy: .public)")

        let deliver: () -> Void = { [weak controller] in
            guard let controller else { return }
            controller.insertTranscript(text)
        }
        if Thread.isMainThread {
            deliver()
        } else {
            DispatchQueue.main.async(execute: deliver)
        }
        return true
    }

    /// Reads a bounded amount of document context through the active input-method client.
    /// Clients that do not expose document access simply return an empty string.
    func textBeforeCursor(maximumUTF16Length: Int = 512) -> String {
        guard Thread.isMainThread else { return "" }

        self.lock.lock()
        let controller = self.activeController
        self.lock.unlock()

        return controller?.textBeforeCursor(maximumUTF16Length: maximumUTF16Length) ?? ""
    }

    /// Returns the screen that contains the active InputMethodKit client's insertion point.
    /// Callers use this to keep visual feedback with the field receiving the final transcript.
    @MainActor
    func activeClientScreen() -> NSScreen? {
        self.lock.lock()
        let controller = self.activeController
        self.lock.unlock()

        return controller?.insertionPointScreen()
    }

    /// Returns the active client's insertion rectangle in global screen coordinates so an
    /// InputMethodKit-owned candidate window can recover from an automatic placement failure.
    @MainActor
    func activeClientInsertionRect() -> NSRect? {
        self.lock.lock()
        let controller = self.activeController
        self.lock.unlock()

        return controller?.insertionPointRect()
    }

    func requestToggle() {
        self.lock.lock()
        let handler = self.toggleHandler
        self.lock.unlock()

        guard let handler else {
            self.logger.error("Direct-input toggle received before handler configuration")
            return
        }
        self.logger.notice("Direct-input toggle requested")
        if Thread.isMainThread {
            handler()
        } else {
            DispatchQueue.main.async(execute: handler)
        }
    }
}
