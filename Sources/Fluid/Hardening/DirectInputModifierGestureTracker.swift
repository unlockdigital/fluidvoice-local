import AppKit

/// Tracks the two modifier-only gestures owned by the direct-input runtime.
///
/// Right Option is Fluid Voice's dictation toggle and consumes its complete press. Globe/Fn
/// remains a system key: an isolated tap requests the character palette while every event passes
/// through. Key and modifier chords suppress the palette request so Fn shortcuts keep working.
struct DirectInputModifierGestureTracker {
    static let rightOptionKeyCode: UInt16 = 61
    static let globeKeyCode: UInt16 = 63

    enum Action: Equatable {
        case none
        case toggleDictation
        case showCharacterPalette
    }

    struct Result: Equatable {
        let action: Action
        let consumesEvent: Bool

        static let passThrough = Result(action: .none, consumesEvent: false)
    }

    private var rightOptionIsDown = false
    private var globeIsDown = false
    private var globeWasCombined = false

    mutating func observeKeyDown(keyCode: UInt16) {
        if self.globeIsDown, keyCode != Self.globeKeyCode {
            self.globeWasCombined = true
        }
    }

    mutating func handleFlagsChanged(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Result {
        if self.globeIsDown, keyCode != Self.globeKeyCode {
            self.globeWasCombined = true
        }

        switch keyCode {
        case Self.rightOptionKeyCode:
            return self.handleRightOption(modifierFlags: modifierFlags)
        case Self.globeKeyCode:
            return self.handleGlobe(modifierFlags: modifierFlags)
        default:
            return .passThrough
        }
    }

    mutating func reset() {
        self.rightOptionIsDown = false
        self.globeIsDown = false
        self.globeWasCombined = false
    }

    private mutating func handleRightOption(
        modifierFlags: NSEvent.ModifierFlags
    ) -> Result {
        let isDown = modifierFlags.contains(.option)
        if isDown {
            self.rightOptionIsDown = true
            return Result(action: .none, consumesEvent: true)
        }

        let shouldToggle = self.rightOptionIsDown
        self.rightOptionIsDown = false
        if shouldToggle {
            return Result(action: .toggleDictation, consumesEvent: true)
        }
        return .passThrough
    }

    private mutating func handleGlobe(
        modifierFlags: NSEvent.ModifierFlags
    ) -> Result {
        let isDown = modifierFlags.contains(.function)
        if isDown {
            if self.globeIsDown == false {
                self.globeIsDown = true
                self.globeWasCombined = false
            }
            return .passThrough
        }

        let shouldShowPalette = self.globeIsDown && self.globeWasCombined == false
        self.globeIsDown = false
        self.globeWasCombined = false
        if shouldShowPalette {
            return Result(action: .showCharacterPalette, consumesEvent: false)
        }
        return .passThrough
    }
}
