import Foundation
import CoreGraphics

/// Thread-safe wrapper that owns a GestureDetector on a serial queue,
/// schedules pending-group flushes, and reports scroll-suppression state.
final class GestureEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.hirano.magicactions.engine")
    private let detector: GestureDetector
    private var flushGeneration = 0
    private var suppressionActive = false

    /// Called on the engine queue.
    var onGesture: (@Sendable (GestureEvent) -> Void)?
    var onRawStroke: (@Sendable ([CGPoint], DeviceKind) -> Void)?
    var onStrokeRejected: (@Sendable (String) -> Void)?
    var onScrollSuppressionChange: (@Sendable (Bool) -> Void)?

    init(settings: EngineSettings = .standard) {
        detector = GestureDetector(settings: settings)
        detector.onRawStroke = { [weak self] points, kind in
            self?.onRawStroke?(points, kind)
        }
        detector.onStrokeRejected = { [weak self] reason in
            self?.onStrokeRejected?(reason)
        }
    }

    func ingest(_ frame: TouchFrame) {
        queue.async { [self] in
            emit(detector.process(frame))
            afterProcessing(now: frame.timestamp)
        }
    }

    func noteButton(at time: Double) {
        queue.async { [self] in detector.noteButtonClick(at: time) }
    }

    func noteScroll(amount: Double, at time: Double) {
        queue.async { [self] in detector.noteScroll(amount: amount, at: time) }
    }

    func updateSettings(_ settings: EngineSettings) {
        queue.async { [self] in detector.settings = settings }
    }

    func setStrokeMatcher(enabled: Bool, matcher: (@Sendable ([CGPoint]) -> UUID?)?) {
        queue.async { [self] in
            detector.strokeEnabled = enabled
            detector.strokeMatcher = matcher
        }
    }

    func setCaptureAllStrokes(_ capture: Bool) {
        queue.async { [self] in detector.captureAllStrokes = capture }
    }

    // MARK: - Internals (engine queue only)

    private func emit(_ events: [GestureEvent]) {
        for event in events { onGesture?(event) }
    }

    private func afterProcessing(now: Double) {
        scheduleFlushIfNeeded(now: now)
        updateSuppression()
    }

    private func scheduleFlushIfNeeded(now: Double) {
        flushGeneration += 1
        guard let deadline = detector.nextFlushDeadline else { return }
        let generation = flushGeneration
        let delay = max(deadline - now, 0) + 0.01
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.flushGeneration == generation else { return }
            self.emit(self.detector.flush(at: ProcessInfo.processInfo.systemUptime))
            self.updateSuppression()
        }
    }

    private func updateSuppression() {
        let wants = detector.wantsScrollSuppression
        if wants != suppressionActive {
            suppressionActive = wants
            onScrollSuppressionChange?(wants)
        }
    }
}
