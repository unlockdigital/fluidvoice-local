import AppKit
import InputMethodKit

/// InputMethodKit controller for FluidVoice's least-privilege direct-insertion build.
///
/// While this input source is selected, a tap of the right Option key toggles dictation.
/// Ordinary keyboard events pass through to the focused application unchanged.
@objc(FluidVoiceInputController)
final class FluidVoiceInputController: IMKInputController {
    private var modifierGestures = DirectInputModifierGestureTracker()

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        DirectInputMethodBridge.shared.activate(self)
    }

    override func deactivateServer(_ sender: Any!) {
        DirectInputMethodBridge.shared.deactivate(self)
        self.modifierGestures.reset()
        super.deactivateServer(sender)
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(
            NSEvent.EventTypeMask.flagsChanged
                .union(.keyDown)
                .rawValue
        )
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else { return false }
        switch event.type {
        case .keyDown:
            // Observing key-down lets an Fn chord suppress the isolated Globe action. Returning
            // false preserves the original event for the focused application.
            self.modifierGestures.observeKeyDown(keyCode: event.keyCode)
            return false

        case .flagsChanged:
            let result = self.modifierGestures.handleFlagsChanged(
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags
            )
            switch result.action {
            case .toggleDictation:
                DirectInputMethodBridge.shared.requestToggle()
            case .showCharacterPalette:
                DebugLogger.shared.info(
                    "Direct-input Globe key requested the character palette",
                    source: "FluidVoiceInputController"
                )
                DispatchQueue.main.async {
                    // Public AppKit action; opens the system emoji and symbols interface without
                    // Accessibility, Apple Events, synthetic input, or foreground activation.
                    NSApp.orderFrontCharacterPalette(nil)
                }
            case .none:
                break
            }
            return result.consumesEvent

        default:
            return false
        }
    }

    func insertTranscript(_ text: String) {
        guard text.isEmpty == false, let inputClient = self.client() else { return }

        inputClient.insertText(
            text as NSString,
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
    }

    func textBeforeCursor(maximumUTF16Length: Int) -> String {
        guard maximumUTF16Length > 0, let inputClient = self.client() else { return "" }

        let selection = inputClient.selectedRange()
        guard selection.location != NSNotFound else { return "" }

        let contextLength = min(selection.location, maximumUTF16Length)
        guard contextLength > 0 else { return "" }

        let range = NSRange(location: selection.location - contextLength, length: contextLength)
        return inputClient.attributedSubstring(from: range)?.string ?? ""
    }

    /// Resolves the display containing the active insertion point through the existing
    /// InputMethodKit client. The returned rectangle is the same screen-space geometry input
    /// methods use to place candidate windows and requires no Accessibility or screen capture.
    func insertionPointScreen() -> NSScreen? {
        guard let lineRect = self.insertionPointRect() else { return nil }

        let insertionPoint = NSPoint(x: lineRect.midX, y: lineRect.midY)
        return NSScreen.screens.first { screen in
            NSMouseInRect(insertionPoint, screen.frame, false)
        }
    }

    func insertionPointRect() -> NSRect? {
        guard let inputClient = self.client() else { return nil }

        let selection = inputClient.selectedRange()
        let characterIndex = selection.location == NSNotFound ? 0 : selection.location
        var lineRect = NSRect.zero
        _ = inputClient.attributes(
            forCharacterIndex: characterIndex,
            lineHeightRectangle: &lineRect
        )
        guard lineRect.isNull == false,
              lineRect.isInfinite == false,
              lineRect.height > 0,
              lineRect.minX.isFinite,
              lineRect.minY.isFinite
        else {
            return nil
        }
        return lineRect
    }
}
