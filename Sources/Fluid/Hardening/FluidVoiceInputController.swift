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
        // Ordinary typing stays with the host application's native text system.
        Int(NSEvent.EventTypeMask.flagsChanged.rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .flagsChanged else { return false }
        let result = self.modifierGestures.handleFlagsChanged(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags
        )
        if result.action == .toggleDictation {
            DirectInputMethodBridge.shared.requestToggle()
        }
        // macOS owns Globe behavior through the existing Emoji & Symbols setting.
        // Without ordinary key-down observation, an application fallback could mistake
        // an Fn chord for an isolated tap. Passing it through preserves native shortcuts.
        return result.consumesEvent
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
