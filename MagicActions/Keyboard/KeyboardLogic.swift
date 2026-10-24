import CoreGraphics

/// Device-dependent modifier bits (IOLLEvent.h NX_DEVICE*KEYMASK). The
/// device-independent CGEventFlags cannot tell left from right.
enum ModifierBits {
    static let leftShift: UInt64 = 0x0000_0002
    static let leftCommand: UInt64 = 0x0000_0008
    static let rightCommand: UInt64 = 0x0000_0010
}

enum KeyCodes {
    static let returnKey: Int64 = 36
    static let keypadEnter: Int64 = 76
    static let tab: Int64 = 48
    static let space: Int64 = 49
    static let delete: Int64 = 51
    static let escape: Int64 = 53
    static let rightCommand: Int64 = 54
    static let leftCommand: Int64 = 55
    static let jisEisu: Int64 = 102
    static let jisKana: Int64 = 104
    static let forwardDelete: Int64 = 117

    static func isReturn(_ keyCode: Int64) -> Bool {
        keyCode == returnKey || keyCode == keypadEnter
    }
}

/// Enter Guard: in chat apps where Return sends and Shift+Return breaks the line,
/// plain Return becomes Shift+Return and Cmd+Return becomes plain Return.
enum EnterGuard {
    enum Remap: Equatable, Sendable {
        case passThrough
        case addShift
        case removeCommand
    }

    /// `composing` is only evaluated for a plain Return with IME passthrough on,
    /// because it may cost an Accessibility round-trip.
    static func decide(flags: CGEventFlags, imePassthrough: Bool, composing: @autoclosure () -> Bool) -> Remap {
        let modifiers = flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate])
        if modifiers == .maskCommand {
            return .removeCommand
        }
        guard modifiers.isEmpty else { return .passThrough }
        if imePassthrough && composing() {
            return .passThrough
        }
        return .addShift
    }

    static func remapped(_ flags: CGEventFlags, _ remap: Remap) -> CGEventFlags {
        switch remap {
        case .passThrough:
            return flags
        case .addShift:
            return CGEventFlags(rawValue: flags.rawValue | CGEventFlags.maskShift.rawValue | ModifierBits.leftShift)
        case .removeCommand:
            let cleared = CGEventFlags.maskCommand.rawValue | ModifierBits.leftCommand | ModifierBits.rightCommand
            return CGEventFlags(rawValue: flags.rawValue & ~cleared)
        }
    }
}

/// Keystroke-based guess of whether an input method holds marked text. Only
/// consulted when the focused element cannot answer over Accessibility
/// (Chromium/Electron). Every uncertain key clears the guess: a wrong "not
/// composing" costs at most a stray newline, while a wrong "composing" lets a
/// plain Return through, which is exactly the accidental send we guard against.
struct CompositionTracker: Equatable, Sendable {
    private(set) var likelyComposing = false

    mutating func reset() {
        likelyComposing = false
    }

    mutating func noteKeyDown(keyCode: Int64, flags: CGEventFlags, producesText: Bool, sourceComposes: Bool) {
        guard sourceComposes, !flags.contains(.maskCommand) else {
            likelyComposing = false
            return
        }
        switch keyCode {
        case KeyCodes.escape, KeyCodes.delete, KeyCodes.forwardDelete, KeyCodes.jisEisu, KeyCodes.jisKana:
            likelyComposing = false
        default:
            // Space, arrows, Tab and Ctrl-chords drive conversion of existing
            // marked text but never start it.
            if producesText && !flags.contains(.maskControl) {
                likelyComposing = true
            }
        }
    }

    /// Printable per the event's own layout translation (control characters,
    /// space and the U+F700 function-key block excluded).
    static func isPrintable(_ firstUnit: UInt16) -> Bool {
        firstUnit > 0x20 && firstUnit != 0x7F && !(0xF700...0xF8FF).contains(firstUnit)
    }
}

/// Detects a lone tap of the left or right Command key: press and release with
/// no other key, modifier, click or scroll in between, within `maxTapDuration`.
struct CommandTapDetector: Equatable, Sendable {
    enum Side: Equatable, Sendable {
        case left
        case right
    }

    static let maxTapDuration = 0.6

    private var pendingSide: Side?
    private var pendingSince = 0.0

    mutating func cancel() {
        pendingSide = nil
    }

    /// Feed every flagsChanged event; returns the side when a tap completes.
    mutating func flagsChanged(keyCode: Int64, flags: CGEventFlags, at time: Double) -> Side? {
        let side: Side
        switch keyCode {
        case KeyCodes.leftCommand: side = .left
        case KeyCodes.rightCommand: side = .right
        default:
            pendingSide = nil
            return nil
        }

        let raw = flags.rawValue
        let sideBit = side == .left ? ModifierBits.leftCommand : ModifierBits.rightCommand
        let otherBit = side == .left ? ModifierBits.rightCommand : ModifierBits.leftCommand
        let hasDeviceBits = raw & (ModifierBits.leftCommand | ModifierBits.rightCommand) != 0
        let isDown = hasDeviceBits ? raw & sideBit != 0 : flags.contains(.maskCommand)

        if isDown {
            let otherModifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskSecondaryFn]
            if flags.intersection(otherModifiers).isEmpty && raw & otherBit == 0 {
                pendingSide = side
                pendingSince = time
            } else {
                pendingSide = nil
            }
            return nil
        }

        defer { pendingSide = nil }
        guard pendingSide == side, time - pendingSince <= Self.maxTapDuration else { return nil }
        return side
    }
}
