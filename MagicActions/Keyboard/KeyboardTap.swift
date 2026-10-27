import AppKit
import CoreGraphics
import os

/// Active keyboard CGEventTap serving Enter Guard and Command-tap input
/// switching. Needs Accessibility to modify events (Input Monitoring may also be
/// required to observe them); creation failure degrades to "inactive" and can be
/// retried after a grant. Like ScrollTap, the run-loop source lives on the main
/// run loop, so the callback runs on the main thread.
final class KeyboardTap: @unchecked Sendable {
    struct Options: Equatable, Sendable {
        var enterGuardEnabled = false
        var enterGuardBundleIDs: Set<String> = []
        var imePassthrough = true
        var commandTapSwitchEnabled = false

        var needsTap: Bool {
            (enterGuardEnabled && !enterGuardBundleIDs.isEmpty) || commandTapSwitchEnabled
        }
    }

    private struct State {
        var options = Options()
        var frontmostBundleID: String?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var unavailable = false

    // Tap-callback-thread-only state.
    private var commandTap = CommandTapDetector()
    private var composition = CompositionTracker()
    private var returnRemaps: [Int64: EnterGuard.Remap] = [:]
    private var lastFrontmost: String?
    private let ownPID = Int64(ProcessInfo.processInfo.processIdentifier)
    /// Private source so a rewritten Return is not reconciled with the built-in
    /// keyboard's physical modifiers. Created with the tap, used only on the
    /// tap thread.
    private var rewriteSource: CGEventSource?

    var isActive: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    // MARK: - Inputs (main thread)

    func setOptions(_ options: Options) {
        state.withLock { $0.options = options }
        updateTapEnabled()
    }

    func setFrontmost(_ bundleID: String?) {
        state.withLock { $0.frontmostBundleID = bundleID }
    }

    /// Allow another creation attempt after a permission grant.
    func resetUnavailable() {
        unavailable = false
        updateTapEnabled()
    }

    // MARK: - Tap lifecycle (main thread)

    private func updateTapEnabled() {
        let needed = state.withLock { $0.options.needsTap }
        if needed, tap == nil, !unavailable {
            createTap()
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: needed)
        }
    }

    private func createTap() {
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let keyboardTap = Unmanaged<KeyboardTap>.fromOpaque(refcon).takeUnretainedValue()
                return keyboardTap.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            unavailable = true
            NSLog("MagicActions: keyboard tap unavailable (missing Accessibility / Input Monitoring?)")
            return
        }
        self.tap = tap
        if rewriteSource == nil {
            let source = CGEventSource(stateID: .privateState)
            source?.localEventsSuppressionInterval = 0
            rewriteSource = source
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    // MARK: - Event handling (tap thread)

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: state.withLock { $0.options.needsTap })
            }
            return pass
        }
        // Our own synthesized events (gesture shortcuts, Eisu/Kana, rewritten
        // Returns) stay literal. The user-data mark covers a rewritten Return
        // whose process ID was cleared on the way back through the tap.
        if event.getIntegerValueField(.eventSourceUnixProcessID) == ownPID
            || event.getIntegerValueField(.eventSourceUserData) == EnterGuard.rewrittenUserData {
            return pass
        }

        let snapshot = state.withLock { $0 }
        if snapshot.frontmostBundleID != lastFrontmost {
            lastFrontmost = snapshot.frontmostBundleID
            composition.reset()
            commandTap.cancel()
        }

        switch type {
        case .flagsChanged:
            guard snapshot.options.commandTapSwitchEnabled else { break }
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if let side = commandTap.flagsChanged(keyCode: keyCode, flags: event.flags,
                                                  at: ProcessInfo.processInfo.systemUptime) {
                switchInputSource(to: side)
            }
        case .keyDown:
            commandTap.cancel()
            if let replaced = handleKeyDown(event, options: snapshot.options, frontmost: snapshot.frontmostBundleID) {
                return Unmanaged.passRetained(replaced)
            }
        case .keyUp:
            if let replaced = handleKeyUp(event) {
                return Unmanaged.passRetained(replaced)
            }
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            commandTap.cancel()
            composition.reset()
        case .scrollWheel:
            commandTap.cancel()
        default:
            break
        }
        return pass
    }

    /// Nil keeps the hardware event. A non-nil event replaces it.
    private func handleKeyDown(_ event: CGEvent, options: Options, frontmost: String?) -> CGEvent? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard options.enterGuardEnabled,
              let frontmost, options.enterGuardBundleIDs.contains(frontmost) else {
            returnRemaps.removeValue(forKey: keyCode)
            return nil
        }

        guard KeyCodes.isReturn(keyCode) else {
            composition.noteKeyDown(
                keyCode: keyCode,
                flags: event.flags,
                producesText: Self.producesText(event),
                sourceComposes: InputSourceInspector.currentSourceComposes()
            )
            return nil
        }

        let remap: EnterGuard.Remap
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0, let held = returnRemaps[keyCode] {
            remap = held
        } else if let focused = FocusProbe.focusedAppBundleID(), !options.enterGuardBundleIDs.contains(focused) {
            remap = .passThrough
        } else {
            remap = EnterGuard.decide(
                flags: event.flags,
                imePassthrough: options.imePassthrough,
                composing: self.isComposing()
            )
        }
        returnRemaps[keyCode] = remap
        composition.reset()
        return apply(remap, keyCode: keyCode, to: event, keyDown: true)
    }

    private func handleKeyUp(_ event: CGEvent) -> CGEvent? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard KeyCodes.isReturn(keyCode), let remap = returnRemaps.removeValue(forKey: keyCode) else {
            return nil
        }
        return apply(remap, keyCode: keyCode, to: event, keyDown: false)
    }

    private func apply(_ remap: EnterGuard.Remap, keyCode: Int64, to event: CGEvent, keyDown: Bool) -> CGEvent? {
        let delivery = EnterGuard.delivery(keyCode: keyCode, flags: event.flags, remap: remap)
        guard delivery.replacesHardwareEvent else { return nil }
        if let source = rewriteSource,
           let rewritten = EnterGuard.rewrittenEvent(
            matching: event, keyDown: keyDown, delivery: delivery, source: source
           ) {
            return rewritten
        }
        // Event creation failed: still edit flags in place, which is enough
        // for Bluetooth keyboards.
        event.flags = delivery.flags
        return nil
    }

    /// Marked-text check, cheapest and most certain first: a non-composing input
    /// source settles it; then the focused element's own answer over
    /// Accessibility; only if the element cannot answer, the keystroke guess.
    private func isComposing() -> Bool {
        guard InputSourceInspector.currentSourceComposes() else { return false }
        switch FocusProbe.markedText() {
        case .marked: return true
        case .clear: return false
        case .unsupported: return composition.likelyComposing
        }
    }

    private static func producesText(_ event: CGEvent) -> Bool {
        var length = 0
        var units = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: units.count, actualStringLength: &length, unicodeString: &units)
        guard length > 0 else { return false }
        return CompositionTracker.isPrintable(units[0])
    }

    // MARK: - Input source switching

    /// Posts the JIS Eisu / Kana keys rather than calling TISSelectInputSource:
    /// the input method then switches itself, which also takes effect in the
    /// focused app (TISSelectInputSource is known to update only the menu bar
    /// for CJK input methods in some apps).
    private func switchInputSource(to side: CommandTapDetector.Side) {
        let keyCode = CGKeyCode(side == .left ? KeyCodes.jisEisu : KeyCodes.jisKana)
        // Deferred so the Command key-up that completed the tap is delivered first.
        DispatchQueue.main.async {
            Self.postKey(keyCode)
        }
    }

    private static func postKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }
        down.flags = []
        up.flags = []
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
