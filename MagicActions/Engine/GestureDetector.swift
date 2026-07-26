import Foundation
import CoreGraphics

/// Pure, synchronous gesture recognition state machine.
/// Fed with TouchFrames (plus button/scroll notes); returns GestureEvents.
/// No GCD, no timers: the owner drives time via process()/flush() so it is unit-testable.
final class GestureDetector {
    var settings: EngineSettings
    /// True when at least one enabled stroke binding exists (arms the trigger zone).
    var strokeEnabled = false
    /// Template-recording mode: every touch path is captured and emitted raw.
    var captureAllStrokes = false
    /// Returns the matched template ID for a raw path, or nil.
    var strokeMatcher: (([CGPoint]) -> UUID?)?
    /// Raw path emission for template recording.
    var onRawStroke: (([CGPoint], DeviceKind) -> Void)?

    private struct PathKey: Hashable {
        let deviceID: UInt64
        let touchID: Int32
    }

    private struct TouchPath {
        let key: PathKey
        let deviceKind: DeviceKind
        let startTime: Double
        let startX: Double
        let startY: Double
        var lastX: Double
        var lastY: Double
        var lastTime: Double
        var maxDisplacement: Double = 0
        var pathLength: Double = 0
        var samples: [CGPoint]
        var ignored: Bool
        var strokeCandidate = false
        var dwellEvaluated = false
    }

    private struct PendingMember {
        let startTime: Double
        let endTime: Double
        let x: Double
        let y: Double
    }

    private struct PendingGroup {
        let kind: GestureKind
        let deviceKind: DeviceKind
        let direction: SwipeDirection?
        var members: [PendingMember]
        var deadline: Double
        var earliestStart: Double { members.map(\.startTime).min() ?? 0 }
    }

    private var paths: [PathKey: TouchPath] = [:]
    private var pending: PendingGroup?
    private var clickTimes: [Double] = []
    private var scrollEvents: [(time: Double, amount: Double)] = []

    init(settings: EngineSettings = .standard) {
        self.settings = settings
    }

    /// When a pending multi-finger group exists, the owner should call flush(at:)
    /// once this deadline passes (touch frames stop arriving after the last lift).
    var nextFlushDeadline: Double? { pending?.deadline }

    /// True while a stroke is being drawn (owner may suppress scroll events).
    var wantsScrollSuppression: Bool {
        paths.values.contains { $0.strokeCandidate && !$0.ignored }
    }

    func noteButtonClick(at time: Double) {
        clickTimes.append(time)
        prune(now: time)
    }

    func noteScroll(amount: Double, at time: Double) {
        scrollEvents.append((time, amount))
        prune(now: time)
    }

    private func prune(now: Double) {
        clickTimes.removeAll { now - $0 > 3 }
        scrollEvents.removeAll { now - $0.time > 3 }
    }

    func process(_ frame: TouchFrame) -> [GestureEvent] {
        var events: [GestureEvent] = []
        let t = frame.timestamp
        var seen = Set<Int32>()
        var endedPaths: [TouchPath] = []

        for touch in frame.touches {
            guard touch.phase != .hover else { continue }
            seen.insert(touch.id)
            let key = PathKey(deviceID: frame.deviceID, touchID: touch.id)

            if touch.phase == .ended {
                if var p = paths.removeValue(forKey: key) {
                    advance(&p, to: touch, at: t)
                    endedPaths.append(p)
                }
                continue
            }

            if var p = paths[key] {
                advance(&p, to: touch, at: t)
                evaluateDwell(&p, at: t)
                paths[key] = p
            } else {
                var p = TouchPath(
                    key: key,
                    deviceKind: frame.deviceKind,
                    startTime: t,
                    startX: touch.x,
                    startY: touch.y,
                    lastX: touch.x,
                    lastY: touch.y,
                    lastTime: t,
                    samples: [CGPoint(x: touch.x, y: touch.y)],
                    ignored: isInDeadZone(x: touch.x, y: touch.y)
                )
                if captureAllStrokes {
                    p.strokeCandidate = true
                    p.dwellEvaluated = true
                    p.ignored = false
                }
                paths[key] = p
            }
        }

        // Touches that vanished without an explicit "ended" state.
        let vanished = paths.values.filter { $0.key.deviceID == frame.deviceID && !seen.contains($0.key.touchID) }
        for p in vanished {
            paths.removeValue(forKey: p.key)
            endedPaths.append(p)
        }

        // Finalize only after every same-frame lift has been removed, so fingers
        // ending together are not mistaken for TipTap anchors of each other.
        for p in endedPaths {
            events += finalize(p, endTime: t)
        }

        if let g = pending, t >= g.deadline {
            pending = nil
            events += flushGroup(g)
        }
        return events
    }

    /// Flush a pending group whose deadline has passed with no further frames.
    func flush(at time: Double) -> [GestureEvent] {
        guard let g = pending, time >= g.deadline else { return [] }
        pending = nil
        return flushGroup(g)
    }

    // MARK: - Internals

    private func advance(_ p: inout TouchPath, to touch: TouchPoint, at t: Double) {
        let stepX = touch.x - p.lastX
        let stepY = touch.y - p.lastY
        p.pathLength += (stepX * stepX + stepY * stepY).squareRoot()
        let dispX = touch.x - p.startX
        let dispY = touch.y - p.startY
        p.maxDisplacement = max(p.maxDisplacement, (dispX * dispX + dispY * dispY).squareRoot())
        p.lastX = touch.x
        p.lastY = touch.y
        p.lastTime = t
        if p.samples.count < 4096 {
            p.samples.append(CGPoint(x: touch.x, y: touch.y))
        }
    }

    private func evaluateDwell(_ p: inout TouchPath, at t: Double) {
        guard strokeEnabled, !p.dwellEvaluated, !p.ignored, !captureAllStrokes else { return }
        guard t - p.startTime >= settings.strokeDwellTime else { return }
        p.dwellEvaluated = true
        let inTriggerZone = p.startY >= 1.0 - settings.strokeTriggerZoneFraction
        p.strokeCandidate = inTriggerZone && p.maxDisplacement <= settings.strokeDwellMaxTravel
    }

    private func isInDeadZone(x: Double, y: Double) -> Bool {
        x < settings.deadZoneEdgeX || x > 1.0 - settings.deadZoneEdgeX
            || y < settings.deadZoneBottom || y > 1.0 - settings.deadZoneTop
    }

    private func clickOccurred(between start: Double, and end: Double) -> Bool {
        clickTimes.contains { $0 >= start && $0 <= end }
    }

    private func scrolledTooMuch(between start: Double, and end: Double) -> Bool {
        let total = scrollEvents
            .filter { $0.time >= start && $0.time <= end }
            .reduce(0.0) { $0 + $1.amount }
        return total > settings.scrollContaminationThreshold
    }

    private func finalize(_ p: TouchPath, endTime: Double) -> [GestureEvent] {
        if p.ignored { return [] }

        if captureAllStrokes {
            if p.samples.count >= 4, p.pathLength >= 0.05 {
                onRawStroke?(p.samples, p.deviceKind)
            }
            return []
        }

        // Stroke: a deliberate draw that armed via the trigger zone.
        if p.strokeCandidate, p.pathLength >= settings.strokeMinLength {
            guard let matcher = strokeMatcher, let templateID = matcher(p.samples) else { return [] }
            return [makeEvent(kind: .stroke, fingers: 1, x: p.startX, y: p.startY,
                              deviceKind: p.deviceKind, timestamp: endTime,
                              strokeTemplateID: templateID)]
        }

        let duration = endTime - p.startTime
        if clickOccurred(between: p.startTime, and: endTime + settings.clickContaminationWindow) {
            return []
        }

        // Tap
        if duration <= settings.tapMaxDuration, p.maxDisplacement <= settings.tapMaxTravel {
            if scrolledTooMuch(between: p.startTime, and: endTime) { return [] }
            // TipTap: another stationary finger was already resting on the surface
            // before this tap began (simultaneous lifts are multi-finger taps).
            let anchor = paths.values.first {
                $0.key.deviceID == p.key.deviceID && !$0.ignored
                    && $0.startTime + settings.anchorMinAge <= p.startTime
                    && $0.maxDisplacement <= settings.anchorMaxTravel
            }
            if let anchor {
                let side: TipTapSide = p.startX < anchor.lastX ? .left : .right
                return [makeEvent(kind: .tipTap, fingers: 1, x: p.startX, y: p.startY,
                                  deviceKind: p.deviceKind, timestamp: endTime, tipTapSide: side)]
            }
            let member = PendingMember(startTime: p.startTime, endTime: endTime, x: p.startX, y: p.startY)
            return appendPending(kind: .tap, deviceKind: p.deviceKind, direction: nil, member: member)
        }

        // Swipe
        let netDX = p.lastX - p.startX
        let netDY = p.lastY - p.startY
        let net = (netDX * netDX + netDY * netDY).squareRoot()
        if duration <= settings.swipeMaxDuration, net >= settings.swipeMinTravel {
            if scrolledTooMuch(between: p.startTime, and: endTime) { return [] }
            let direction: SwipeDirection?
            if abs(netDX) >= abs(netDY) * settings.axisDominance {
                direction = netDX > 0 ? .right : .left
            } else if abs(netDY) >= abs(netDX) * settings.axisDominance {
                direction = netDY > 0 ? .up : .down
            } else {
                direction = nil // diagonal: ambiguous, drop
            }
            guard let direction else { return [] }
            let member = PendingMember(startTime: p.startTime, endTime: endTime, x: p.startX, y: p.startY)
            return appendPending(kind: .swipe, deviceKind: p.deviceKind, direction: direction, member: member)
        }

        return []
    }

    private func appendPending(kind: GestureKind, deviceKind: DeviceKind,
                               direction: SwipeDirection?, member: PendingMember) -> [GestureEvent] {
        var out: [GestureEvent] = []
        if var g = pending {
            // Fingers of one multi-finger gesture overlap in time; sequential taps must not merge.
            let overlaps = g.members.contains { member.startTime < $0.endTime && $0.startTime < member.endTime }
            if g.kind == kind, g.deviceKind == deviceKind, g.direction == direction, overlaps {
                g.members.append(member)
                g.deadline = member.endTime + settings.groupWindow
                pending = g
                return []
            }
            pending = nil
            out += flushGroup(g)
        }
        pending = PendingGroup(kind: kind, deviceKind: deviceKind, direction: direction,
                               members: [member], deadline: member.endTime + settings.groupWindow)
        return out
    }

    private func flushGroup(_ g: PendingGroup) -> [GestureEvent] {
        // Re-check clicks that may have landed after members were queued.
        if clickOccurred(between: g.earliestStart, and: g.deadline) { return [] }
        let cx = g.members.map(\.x).reduce(0, +) / Double(g.members.count)
        let cy = g.members.map(\.y).reduce(0, +) / Double(g.members.count)
        return [makeEvent(kind: g.kind, fingers: min(g.members.count, 5), x: cx, y: cy,
                          deviceKind: g.deviceKind, timestamp: g.deadline, direction: g.direction)]
    }

    private func makeEvent(kind: GestureKind, fingers: Int, x: Double, y: Double,
                           deviceKind: DeviceKind, timestamp: Double,
                           direction: SwipeDirection? = nil,
                           tipTapSide: TipTapSide? = nil,
                           strokeTemplateID: UUID? = nil) -> GestureEvent {
        GestureEvent(
            deviceKind: deviceKind,
            kind: kind,
            fingers: fingers,
            columnZone: .column(forX: x),
            verticalZone: .vertical(forY: y),
            direction: direction,
            tipTapSide: tipTapSide,
            strokeTemplateID: strokeTemplateID,
            timestamp: timestamp
        )
    }
}
