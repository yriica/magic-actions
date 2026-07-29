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
        var adaptive = true
        var trackpadMultiplier = 1.0
        var mouseMultiplier = 1.0
        var lastTouchKind: DeviceKind?
        var lastTouchTime: Double = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var unavailable = false

    // Tap-callback-thread-only state (single-threaded; no lock needed).
    private var velocityEMA = 0.0
    private var lastScrollEventAt = 0.0
    private var carryPoint1 = 0.0, carryPoint2 = 0.0
    private var carryLine1 = 0.0, carryLine2 = 0.0

    /// Attribution window: momentum scrolling keeps flowing after the fingers
    /// lift, so recent touch activity stays authoritative for a few seconds.
    private static let attributionWindow = 5.0

    // MARK: - Inputs (setters: main thread; noteTouches: any thread)

    func setSuppress(_ suppress: Bool) {
        state.withLock { $0.suppress = suppress }
        updateTapEnabled()
    }

    func setMultipliers(enabled: Bool, adaptive: Bool, trackpad: Double, mouse: Double) {
        state.withLock {
            $0.multiplierEnabled = enabled
            $0.adaptive = adaptive
            $0.trackpadMultiplier = trackpad
            $0.mouseMultiplier = mouse
        }
        updateTapEnabled()
    }

    /// Velocity-adaptive gain: 1x for slow, precise scrolling; ramps toward the
    /// configured multiplier for fast swipes; decays back to 1x with momentum,
    /// which keeps individual scroll steps small exactly when steps are visible.
    static func gain(velocity: Double, maxMultiplier: Double) -> Double {
        guard maxMultiplier > 1 else { return maxMultiplier }
        let vLow = 600.0   // points/sec: below this, native feel untouched
        let vHigh = 2600.0 // points/sec: full multiplier from here up
        let t = min(max((velocity - vLow) / (vHigh - vLow), 0), 1)
        let smooth = t * t * (3 - 2 * t)
        return 1 + (maxMultiplier - 1) * smooth
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

        let maxMultiplier: Double
        switch attributedKind {
        case .magicMouse:
            maxMultiplier = snapshot.mouseMultiplier
        case .magicTrackpad, .builtInTrackpad:
            maxMultiplier = snapshot.trackpadMultiplier
        case .unknown, nil:
            // Continuous scroll without touch attribution is almost always a trackpad.
            maxMultiplier = snapshot.trackpadMultiplier
        }
        guard maxMultiplier != 1.0 else { return Unmanaged.passUnretained(event) }

        let multiplier: Double
        if snapshot.adaptive {
            updateVelocity(from: event, at: now)
            multiplier = Self.gain(velocity: velocityEMA, maxMultiplier: maxMultiplier)
        } else {
            multiplier = maxMultiplier
        }
        guard abs(multiplier - 1.0) > 0.001 else { return Unmanaged.passUnretained(event) }

        scaleAxis(event, line: .scrollWheelEventDeltaAxis1,
                  point: .scrollWheelEventPointDeltaAxis1,
                  fixed: .scrollWheelEventFixedPtDeltaAxis1, by: multiplier,
                  carryPoint: &carryPoint1, carryLine: &carryLine1)
        scaleAxis(event, line: .scrollWheelEventDeltaAxis2,
                  point: .scrollWheelEventPointDeltaAxis2,
                  fixed: .scrollWheelEventFixedPtDeltaAxis2, by: multiplier,
                  carryPoint: &carryPoint2, carryLine: &carryLine2)
        return Unmanaged.passUnretained(event)
    }

    private func updateVelocity(from event: CGEvent, at now: Double) {
        let p1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let p2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        let magnitude = Double(abs(p1) + abs(p2))
        let dt = now - lastScrollEventAt
        lastScrollEventAt = now
        if dt > 0.25 {
            // New scroll stream: start fresh so a slow start stays 1x.
            velocityEMA = 0
            carryPoint1 = 0; carryPoint2 = 0; carryLine1 = 0; carryLine2 = 0
            return
        }
        let instantaneous = magnitude / max(dt, 0.004)
        velocityEMA = velocityEMA * 0.7 + instantaneous * 0.3
    }

    private func scaleAxis(_ event: CGEvent, line: CGEventField, point: CGEventField,
                           fixed: CGEventField, by multiplier: Double,
                           carryPoint: inout Double, carryLine: inout Double) {
        let fixedValue = event.getDoubleValueField(fixed)
        if fixedValue != 0 {
            event.setDoubleValueField(fixed, value: fixedValue * multiplier)
        }
        let pointValue = event.getIntegerValueField(point)
        if pointValue != 0 {
            event.setIntegerValueField(point, value: scaleWithCarry(pointValue, by: multiplier, carry: &carryPoint))
        }
        let lineValue = event.getIntegerValueField(line)
        if lineValue != 0 {
            event.setIntegerValueField(line, value: scaleWithCarry(lineValue, by: multiplier, carry: &carryLine))
        }
    }

    /// Integer scaling that carries the fractional remainder to the next event,
    /// so no distance is lost or duplicated by per-event rounding.
    private func scaleWithCarry(_ value: Int64, by multiplier: Double, carry: inout Double) -> Int64 {
        let exact = Double(value) * multiplier + carry
        let rounded = exact.rounded()
        carry = exact - rounded
        return Int64(rounded)
    }
}
