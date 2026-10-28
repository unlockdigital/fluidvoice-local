import AppKit
import Foundation

private func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard condition() else {
        fputs("FAIL: \(message) [\(file):\(line)]\n", stderr)
        exit(1)
    }
}

@main
private enum ModifierGestureTests {
    static func main() {
        var tracker = DirectInputModifierGestureTracker()

        var result = tracker.handleFlagsChanged(keyCode: 61, modifierFlags: [.option])
        expect(result == .init(action: .none, consumesEvent: true), "Right Option down must be consumed")
        result = tracker.handleFlagsChanged(keyCode: 61, modifierFlags: [])
        expect(result == .init(action: .toggleDictation, consumesEvent: true), "Right Option release must toggle dictation")
        result = tracker.handleFlagsChanged(keyCode: 61, modifierFlags: [])
        expect(result == .passThrough, "A stray Right Option release must pass through")

        result = tracker.handleFlagsChanged(keyCode: 63, modifierFlags: [.function])
        expect(result == .passThrough, "Globe down must pass through")
        result = tracker.handleFlagsChanged(keyCode: 63, modifierFlags: [])
        expect(result == .init(action: .showCharacterPalette, consumesEvent: false), "An isolated Globe tap must show the character palette and pass through")

        _ = tracker.handleFlagsChanged(keyCode: 63, modifierFlags: [.function])
        tracker.observeKeyDown(keyCode: 0)
        result = tracker.handleFlagsChanged(keyCode: 63, modifierFlags: [])
        expect(result == .passThrough, "Fn plus a character key must suppress the palette")

        _ = tracker.handleFlagsChanged(keyCode: 63, modifierFlags: [.function])
        _ = tracker.handleFlagsChanged(keyCode: 56, modifierFlags: [.function, .shift])
        result = tracker.handleFlagsChanged(keyCode: 63, modifierFlags: [])
        expect(result == .passThrough, "Fn plus another modifier must suppress the palette")

        result = tracker.handleFlagsChanged(keyCode: 56, modifierFlags: [.shift])
        expect(result == .passThrough, "Unrelated modifiers must pass through")

        _ = tracker.handleFlagsChanged(keyCode: 63, modifierFlags: [.function])
        tracker.reset()
        result = tracker.handleFlagsChanged(keyCode: 63, modifierFlags: [])
        expect(result == .passThrough, "Deactivation reset must cancel a pending Globe tap")

        print("PASS: Direct input modifier gesture regression tests")
    }
}
