import Carbon
import CoreGraphics
import XCTest
@testable import MagicActions

final class KeyboardLogicTests: XCTestCase {
    private let cmdLeft = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | ModifierBits.leftCommand)
    private let cmdRight = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | ModifierBits.rightCommand)
    private let plain = CGEventFlags(rawValue: 0x100) // NX_NONCOALSCEDMASK, present on real events

    // MARK: - Enter Guard

    func testPlainReturnBecomesShiftReturn() {
        let remap = EnterGuard.decide(flags: plain, imePassthrough: true, composing: false)
        XCTAssertEqual(remap, .addShift)
        let flags = EnterGuard.remapped(plain, remap)
        XCTAssertTrue(flags.contains(.maskShift))
        XCTAssertFalse(flags.contains(.maskCommand))
    }

    func testCommandReturnBecomesPlainReturn() {
        let remap = EnterGuard.decide(flags: cmdLeft, imePassthrough: true, composing: false)
        XCTAssertEqual(remap, .removeCommand)
        let flags = EnterGuard.remapped(cmdLeft, remap)
        XCTAssertFalse(flags.contains(.maskCommand))
        XCTAssertEqual(flags.rawValue & (ModifierBits.leftCommand | ModifierBits.rightCommand), 0)
    }

    func testOtherModifiedReturnsUntouched() {
        let modified: [CGEventFlags] = [.maskShift, .maskControl, .maskAlternate, [.maskCommand, .maskShift]]
        for flags in modified {
            XCTAssertEqual(EnterGuard.decide(flags: flags, imePassthrough: true, composing: false), .passThrough)
        }
    }

    func testComposingReturnPassesThroughWhenEnabled() {
        XCTAssertEqual(EnterGuard.decide(flags: plain, imePassthrough: true, composing: true), .passThrough)
        XCTAssertEqual(EnterGuard.decide(flags: plain, imePassthrough: false, composing: true), .addShift)
    }

    func testRemapReplacesHardwareEventSoBuiltInKeyboardKeepsFlags() {
        let plainDelivery = EnterGuard.delivery(keyCode: KeyCodes.returnKey, flags: plain, remap: .addShift)
        XCTAssertTrue(plainDelivery.replacesHardwareEvent)
        XCTAssertEqual(plainDelivery.keyCode, KeyCodes.returnKey)
        XCTAssertTrue(plainDelivery.flags.contains(.maskShift))

        let commandDelivery = EnterGuard.delivery(keyCode: KeyCodes.returnKey, flags: cmdLeft, remap: .removeCommand)
        XCTAssertTrue(commandDelivery.replacesHardwareEvent)
        XCTAssertFalse(commandDelivery.flags.contains(.maskCommand))

        let untouched = EnterGuard.delivery(keyCode: KeyCodes.returnKey, flags: plain, remap: .passThrough)
        XCTAssertFalse(untouched.replacesHardwareEvent)
        XCTAssertEqual(untouched.flags, plain)
    }

    func testRewrittenReturnKeepsKeyIdentityAndPrivateSource() {
        let hardware = CGEventSource(stateID: .hidSystemState)!
        let original = CGEvent(keyboardEventSource: hardware, virtualKey: CGKeyCode(KeyCodes.returnKey), keyDown: true)!
        original.flags = plain
        original.setIntegerValueField(.keyboardEventKeyboardType, value: 44)
        original.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        let delivery = EnterGuard.delivery(keyCode: KeyCodes.returnKey, flags: plain, remap: .addShift)
        let source = CGEventSource(stateID: .privateState)!
        let rewritten = EnterGuard.rewrittenEvent(matching: original, keyDown: true, delivery: delivery, source: source)
        let state = rewritten?.getIntegerValueField(.eventSourceStateID) ?? 0
        XCTAssertEqual(Int32(truncatingIfNeeded: state), CGEventSourceStateID.privateState.rawValue)
        XCTAssertEqual(rewritten?.getIntegerValueField(.eventSourceUserData), EnterGuard.rewrittenUserData)
        XCTAssertEqual(rewritten?.getIntegerValueField(.keyboardEventKeycode), KeyCodes.returnKey)
        XCTAssertEqual(rewritten?.getIntegerValueField(.keyboardEventKeyboardType), 44)
        XCTAssertEqual(rewritten?.getIntegerValueField(.keyboardEventAutorepeat), 1)
        XCTAssertEqual(rewritten?.timestamp, original.timestamp)
        XCTAssertTrue(rewritten?.flags.contains(.maskShift) ?? false)
        XCTAssertNil(EnterGuard.rewrittenEvent(matching: original, keyDown: true, delivery: EnterGuard.delivery(keyCode: KeyCodes.returnKey, flags: plain, remap: .passThrough), source: source))
    }

    func testComposingNotQueriedForCommandReturnOrWithoutPassthrough() {
        var queried = false
        func probe() -> Bool { queried = true; return true }
        _ = EnterGuard.decide(flags: cmdLeft, imePassthrough: true, composing: probe())
        _ = EnterGuard.decide(flags: plain, imePassthrough: false, composing: probe())
        XCTAssertFalse(queried)
    }

    // MARK: - Composition tracker

    func testTypingInComposingSourceStartsComposition() {
        var tracker = CompositionTracker()
        tracker.noteKeyDown(keyCode: 0, flags: plain, producesText: true, sourceComposes: true)
        XCTAssertTrue(tracker.likelyComposing)
        // Space (conversion) and arrows keep it.
        tracker.noteKeyDown(keyCode: KeyCodes.space, flags: plain, producesText: false, sourceComposes: true)
        tracker.noteKeyDown(keyCode: 124, flags: plain, producesText: false, sourceComposes: true)
        XCTAssertTrue(tracker.likelyComposing)
    }

    func testUncertainKeysClearComposition() {
        for keyCode in [KeyCodes.escape, KeyCodes.delete, KeyCodes.forwardDelete, KeyCodes.jisEisu] {
            var tracker = CompositionTracker()
            tracker.noteKeyDown(keyCode: 0, flags: plain, producesText: true, sourceComposes: true)
            tracker.noteKeyDown(keyCode: keyCode, flags: plain, producesText: false, sourceComposes: true)
            XCTAssertFalse(tracker.likelyComposing, "keyCode \(keyCode)")
        }
        var tracker = CompositionTracker()
        tracker.noteKeyDown(keyCode: 0, flags: plain, producesText: true, sourceComposes: true)
        tracker.noteKeyDown(keyCode: 8, flags: cmdLeft, producesText: true, sourceComposes: true)
        XCTAssertFalse(tracker.likelyComposing)
    }

    func testNonComposingSourceNeverComposes() {
        var tracker = CompositionTracker()
        tracker.noteKeyDown(keyCode: 0, flags: plain, producesText: true, sourceComposes: false)
        XCTAssertFalse(tracker.likelyComposing)
    }

    func testControlChordDoesNotStartComposition() {
        var tracker = CompositionTracker()
        tracker.noteKeyDown(keyCode: 38, flags: .maskControl, producesText: true, sourceComposes: true)
        XCTAssertFalse(tracker.likelyComposing)
    }

    func testPrintableClassification() {
        XCTAssertTrue(CompositionTracker.isPrintable(0x61)) // a
        XCTAssertTrue(CompositionTracker.isPrintable(0x31)) // 1
        XCTAssertFalse(CompositionTracker.isPrintable(0x20)) // space
        XCTAssertFalse(CompositionTracker.isPrintable(0x0D)) // return
        XCTAssertFalse(CompositionTracker.isPrintable(0x7F)) // delete
        XCTAssertFalse(CompositionTracker.isPrintable(0xF702)) // left arrow
    }

    func testComposingInputModeRule() {
        let mode = kTISTypeKeyboardInputMode as String
        let layout = kTISTypeKeyboardLayout as String
        XCTAssertTrue(InputSourceInspector.isComposingMode(type: mode, modeID: "com.apple.inputmethod.Japanese"))
        XCTAssertFalse(InputSourceInspector.isComposingMode(type: mode, modeID: "com.apple.inputmethod.Roman"))
        XCTAssertFalse(InputSourceInspector.isComposingMode(type: layout, modeID: nil))
    }

    // MARK: - Command tap

    func testLeftCommandTapDetected() {
        var detector = CommandTapDetector()
        XCTAssertNil(detector.flagsChanged(keyCode: KeyCodes.leftCommand, flags: cmdLeft, at: 1.0))
        XCTAssertEqual(detector.flagsChanged(keyCode: KeyCodes.leftCommand, flags: plain, at: 1.1), .left)
    }

    func testRightCommandTapDetected() {
        var detector = CommandTapDetector()
        _ = detector.flagsChanged(keyCode: KeyCodes.rightCommand, flags: cmdRight, at: 1.0)
        XCTAssertEqual(detector.flagsChanged(keyCode: KeyCodes.rightCommand, flags: plain, at: 1.1), .right)
    }

    func testCommandChordIsNotATap() {
        var detector = CommandTapDetector()
        _ = detector.flagsChanged(keyCode: KeyCodes.leftCommand, flags: cmdLeft, at: 1.0)
        detector.cancel() // a keyDown (e.g. C of Cmd+C) arrived
        XCTAssertNil(detector.flagsChanged(keyCode: KeyCodes.leftCommand, flags: plain, at: 1.1))
    }

    func testLongHoldIsNotATap() {
        var detector = CommandTapDetector()
        _ = detector.flagsChanged(keyCode: KeyCodes.leftCommand, flags: cmdLeft, at: 1.0)
        XCTAssertNil(detector.flagsChanged(keyCode: KeyCodes.leftCommand, flags: plain,
                                           at: 1.0 + CommandTapDetector.maxTapDuration + 0.1))
    }

    func testCommandWithOtherModifierIsNotATap() {
        var detector = CommandTapDetector()
        let cmdShift = CGEventFlags(rawValue: cmdLeft.rawValue | CGEventFlags.maskShift.rawValue)
        _ = detector.flagsChanged(keyCode: KeyCodes.leftCommand, flags: cmdShift, at: 1.0)
        XCTAssertNil(detector.flagsChanged(keyCode: KeyCodes.leftCommand, flags: .maskShift, at: 1.1))

        // Shift pressed in the middle of a Command press also cancels.
        _ = detector.flagsChanged(keyCode: KeyCodes.leftCommand, flags: cmdLeft, at: 2.0)
        _ = detector.flagsChanged(keyCode: 56, flags: cmdShift, at: 2.05)
        XCTAssertNil(detector.flagsChanged(keyCode: KeyCodes.leftCommand, flags: plain, at: 2.1))
    }

    func testBothCommandsHeldIsNotATap() {
        var detector = CommandTapDetector()
        let both = CGEventFlags(rawValue: cmdLeft.rawValue | ModifierBits.rightCommand)
        _ = detector.flagsChanged(keyCode: KeyCodes.leftCommand, flags: cmdLeft, at: 1.0)
        _ = detector.flagsChanged(keyCode: KeyCodes.rightCommand, flags: both, at: 1.05)
        XCTAssertNil(detector.flagsChanged(keyCode: KeyCodes.rightCommand, flags: cmdLeft, at: 1.1))
        XCTAssertNil(detector.flagsChanged(keyCode: KeyCodes.leftCommand, flags: plain, at: 1.15))
    }

    // MARK: - Config

    func testKeyboardFeatureDefaults() throws {
        let decoded = try JSONDecoder().decode(AppSettingsModel.self, from: Data("{}".utf8))
        XCTAssertFalse(decoded.enterGuardEnabled)
        XCTAssertFalse(decoded.commandTapInputSwitch)
        XCTAssertTrue(decoded.enterGuardIMEPassthrough)
        XCTAssertEqual(decoded.enterGuardApps.map(\.bundleID),
                       ["com.anthropic.claudefordesktop", "com.anysphere.sand"])
    }
}
