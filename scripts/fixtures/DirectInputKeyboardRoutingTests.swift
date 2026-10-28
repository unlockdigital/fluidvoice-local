import AppKit

// Actual production event methods are injected below. Events stay in memory and
// are never posted to the keyboard or another application.
private final class DirectInputMethodBridge {
    static let shared = DirectInputMethodBridge()
    var toggles = 0
    func requestToggle() { self.toggles += 1 }
}
private final class Controller {
    private var modifierGestures = DirectInputModifierGestureTracker()
    // PRODUCTION_EVENT_METHODS
}
private func expect(_ value: @autoclosure () -> Bool, _ description: String) {
    guard value() else { fatalError("FAIL: \(description)") }
}
private func event(_ type: NSEvent.EventType, _ code: UInt16, _ flags: NSEvent.ModifierFlags = [], _ text: String = "") -> NSEvent {
    NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
                    windowNumber: 0, context: nil, characters: text,
                    charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
}
@main
private enum DirectInputKeyboardRoutingTests {
    static func main() {
        let c = Controller()
        let mask = NSEvent.EventTypeMask(rawValue: UInt64(c.recognizedEvents(nil)))
        expect(mask == .flagsChanged, "Advertised mask leaves all ordinary keyboard events to macOS")
        let ordinary: [(UInt16, NSEvent.ModifierFlags, String)] = [
            (0, [], "a"), (0, .shift, "A"), (0, .option, "å"), (0, .command, "a"),
            (0, .control, "a"), (49, [], " "), (36, [], "\r"), (51, [], "\u{7f}"),
            (48, [], "\t"), (53, [], "\u{1b}"), (123, .function, ""), (0, [], "é"),
        ]
        for (code, flags, text) in ordinary {
            expect(!c.handle(event(.keyDown, code, flags, text), client: nil), "Unexpected key-down passes through")
            expect(!c.handle(event(.keyUp, code, flags, text), client: nil), "Unexpected key-up passes through")
        }
        expect(DirectInputMethodBridge.shared.toggles == 0, "Letters, editing keys and shortcuts never toggle dictation")
        expect(c.handle(event(.flagsChanged, 61, .option), client: nil), "Right Option down is consumed")
        expect(DirectInputMethodBridge.shared.toggles == 0, "Right Option down alone does not toggle")
        expect(c.handle(event(.flagsChanged, 61), client: nil), "Right Option release is consumed")
        expect(DirectInputMethodBridge.shared.toggles == 1, "Complete Right Option press toggles once")
        expect(!c.handle(event(.keyDown, 0, [], "a"), client: nil), "Typing after toggle stays unhandled")
        expect(!c.handle(event(.flagsChanged, 63, .function), client: nil), "Globe down stays native")
        expect(!c.handle(event(.keyDown, 123, .function), client: nil), "Fn navigation stays native")
        expect(!c.handle(event(.flagsChanged, 63), client: nil), "Globe release stays native")
        expect(!c.handle(event(.flagsChanged, 56, .shift), client: nil), "Unrelated modifier stays native")
        expect(DirectInputMethodBridge.shared.toggles == 1, "Native modifier paths do not toggle dictation")
        expect(!c.handle(nil, client: nil), "Missing event is unhandled")
        print("PASS: production keyboard routing (letters, editing, shortcuts, Right Option, Globe/Fn and post-toggle typing)")
    }
}
