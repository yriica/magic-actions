import AppKit
import CoreGraphics
import os

/// Single active CGEventTap over scroll-wheel events, serving two features:
/// swallowing scrolls while a stroke is drawn, and multiplying scroll deltas
/// per device class (scroll speed override). Requires the Input Monitoring
/// permission; on failure it degrades gracefully and can retry after a grant.
///
/// Device attribution uses this app's own touch data: whichever device had
/// fingers on it most recently is the source of the current (and momentum)
/// scroll stream.
final class ScrollTap: @unchecked Sendable {
    private struct State {
        var suppress = false
        var multiplierEnabled = false
        var trackpadMultiplier = 1.0
        var mouseMultiplier = 1.0
        var lastTouchKind: DeviceKind?
        var lastTouchTime: Double = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var unavailable = false

    /// Attribution window: momentum scrolling keeps flowing after the fingers
    /// lift, so recent touch activity stays authoritative for a few seconds.
    private static let attributionWindow = 5.0

    // MARK: - Inputs (setters: main thread; noteTouches: any thread)

    func setSuppress(_ suppress: Bool) {
        state.withLock { $0.suppress = suppress }
        updateTapEnabled()
    }

    func setMultipliers(enabled: Bool, trackpad: Double, mouse: Double) {
        state.withLock {
            $0.multiplierEnabled = enabled
            $0.trackpadMultiplier = trackpad
            $0.mouseMultiplier = mouse
        }
        updateTapEnabled()
    }

    /// Called from the touch-callback thread whenever a frame carries touches.
    func noteTouches(kind: DeviceKind, at time: Double) {
        state.withLock {
            $0.lastTouchKind = kind
            $0.lastTouchTime = time
        }
    }

    /// Allow another creation attempt after a permission grant.
    func resetUnavailable() {
        unavailable = false
    }

    // MARK: - Tap lifecycle (main thread)

    private var needsTap: Bool {
        state.withLock {
            $0.suppress || ($0.multiplierEnabled && ($0.trackpadMultiplier != 1.0 || $0.mouseMultiplier != 1.0))
        }
    }

    private func updateTapEnabled() {
        let needed = needsTap
        if needed, tap == nil, !unavailable {
            createTap()
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: needed)
        }
    }

    private func createTap() {
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let scrollTap = Unmanaged<ScrollTap>.fromOpaque(refcon).takeUnretainedValue()
                return scrollTap.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            unavailable = true
            NSLog("MagicActions: scroll tap unavailable (missing Input Monitoring?)")
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    // MARK: - Event handling (tap thread)

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables taps that stall; re-enable and pass through.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: needsTap) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }

        let snapshot = state.withLock { $0 }
        if snapshot.suppress {
            return nil
        }
        guard snapshot.multiplierEnabled else { return Unmanaged.passUnretained(event) }
        // Classic wheel mice have their own System Settings scaling; leave them alone.
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 else {
            return Unmanaged.passUnretained(event)
        }

        let now = ProcessInfo.processInfo.systemUptime
        let attributedKind: DeviceKind? =
            (now - snapshot.lastTouchTime) < Self.attributionWindow ? snapshot.lastTouchKind : nil

        let multiplier: Double
        switch attributedKind {
        case .magicMouse:
            multiplier = snapshot.mouseMultiplier
        case .magicTrackpad, .builtInTrackpad:
            multiplier = snapshot.trackpadMultiplier
        case .unknown, nil:
            // Continuous scroll without touch attribution is almost always a trackpad.
            multiplier = snapshot.trackpadMultiplier
        }
        guard multiplier != 1.0 else { return Unmanaged.passUnretained(event) }

        scaleAxis(event, line: .scrollWheelEventDeltaAxis1,
                  point: .scrollWheelEventPointDeltaAxis1,
                  fixed: .scrollWheelEventFixedPtDeltaAxis1, by: multiplier)
        scaleAxis(event, line: .scrollWheelEventDeltaAxis2,
                  point: .scrollWheelEventPointDeltaAxis2,
                  fixed: .scrollWheelEventFixedPtDeltaAxis2, by: multiplier)
        return Unmanaged.passUnretained(event)
    }

    private func scaleAxis(_ event: CGEvent, line: CGEventField, point: CGEventField,
                           fixed: CGEventField, by multiplier: Double) {
        let fixedValue = event.getDoubleValueField(fixed)
        if fixedValue != 0 {
            event.setDoubleValueField(fixed, value: fixedValue * multiplier)
        }
        let pointValue = event.getIntegerValueField(point)
        if pointValue != 0 {
            event.setIntegerValueField(point, value: Int64((Double(pointValue) * multiplier).rounded()))
        }
        let lineValue = event.getIntegerValueField(line)
        if lineValue != 0 {
            event.setIntegerValueField(line, value: Int64((Double(lineValue) * multiplier).rounded()))
        }
    }
}
