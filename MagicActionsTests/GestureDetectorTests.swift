import XCTest
@testable import MagicActions

final class GestureDetectorTests: XCTestCase {
    private var detector: GestureDetector!

    override func setUp() {
        super.setUp()
        detector = GestureDetector(settings: .standard)
    }

    private func frame(
        _ t: Double,
        device: UInt64 = 1,
        kind: DeviceKind = .magicMouse,
        touches: [(id: Int32, phase: TouchPhase, x: Double, y: Double)]
    ) -> TouchFrame {
        TouchFrame(
            deviceID: device,
            deviceKind: kind,
            timestamp: t,
            touches: touches.map {
                TouchPoint(id: $0.id, phase: $0.phase, x: $0.x, y: $0.y,
                           velocityX: 0, velocityY: 0, size: 0.5, pressure: 0)
            }
        )
    }

    // MARK: - Taps

    func testSingleFingerTap() {
        var events: [GestureEvent] = []
        events += detector.process(frame(0.00, touches: [(1, .began, 0.5, 0.3)]))
        events += detector.process(frame(0.05, touches: [(1, .moved, 0.505, 0.3)]))
        events += detector.process(frame(0.10, touches: [(1, .ended, 0.505, 0.3)]))
        events += detector.flush(at: 0.5)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .tap)
        XCTAssertEqual(events.first?.fingers, 1)
        XCTAssertEqual(events.first?.columnZone, .middle)
        XCTAssertEqual(events.first?.verticalZone, .base)
    }

    func testTwoFingerTapGroupsIntoSingleEvent() {
        var events: [GestureEvent] = []
        events += detector.process(frame(0.00, touches: [(1, .began, 0.4, 0.5), (2, .began, 0.6, 0.5)]))
        events += detector.process(frame(0.06, touches: [(1, .moved, 0.4, 0.5), (2, .moved, 0.6, 0.5)]))
        events += detector.process(frame(0.12, touches: [(1, .ended, 0.4, 0.5), (2, .ended, 0.6, 0.5)]))
        events += detector.flush(at: 0.5)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .tap)
        XCTAssertEqual(events.first?.fingers, 2)
    }

    func testSequentialTapsDoNotMerge() {
        var events: [GestureEvent] = []
        events += detector.process(frame(0.00, touches: [(1, .began, 0.5, 0.5)]))
        events += detector.process(frame(0.08, touches: [(1, .ended, 0.5, 0.5)]))
        // Second tap arrives well after the first group's deadline.
        events += detector.process(frame(0.50, touches: [(2, .began, 0.5, 0.5)]))
        events += detector.process(frame(0.58, touches: [(2, .ended, 0.5, 0.5)]))
        events += detector.flush(at: 1.0)

        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.allSatisfy { $0.kind == .tap && $0.fingers == 1 })
    }

    func testTapZones() {
        var events: [GestureEvent] = []
        events += detector.process(frame(0.00, touches: [(1, .began, 0.1, 0.9)]))
        events += detector.process(frame(0.08, touches: [(1, .ended, 0.1, 0.9)]))
        events += detector.flush(at: 0.5)

        XCTAssertEqual(events.first?.columnZone, .left)
        XCTAssertEqual(events.first?.verticalZone, .tip)
    }

    func testTapRejectedWhenPhysicalClickOccurs() {
        var events: [GestureEvent] = []
        events += detector.process(frame(0.00, touches: [(1, .began, 0.5, 0.5)]))
        detector.noteButtonClick(at: 0.05)
        events += detector.process(frame(0.10, touches: [(1, .ended, 0.5, 0.5)]))
        events += detector.flush(at: 0.5)

        XCTAssertTrue(events.isEmpty)
    }

    func testTapRejectedWhenScrollingHeavily() {
        var events: [GestureEvent] = []
        events += detector.process(frame(0.00, touches: [(1, .began, 0.5, 0.5)]))
        detector.noteScroll(amount: 30, at: 0.05)
        events += detector.process(frame(0.10, touches: [(1, .ended, 0.5, 0.5)]))
        events += detector.flush(at: 0.5)

        XCTAssertTrue(events.isEmpty)
    }

    func testDeadZoneTouchIgnored() {
        var events: [GestureEvent] = []
        events += detector.process(frame(0.00, touches: [(1, .began, 0.01, 0.5)]))
        events += detector.process(frame(0.08, touches: [(1, .ended, 0.01, 0.5)]))
        events += detector.flush(at: 0.5)

        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - Swipes

    func testSwipeRight() {
        var events: [GestureEvent] = []
        events += detector.process(frame(0.00, touches: [(1, .began, 0.2, 0.5)]))
        events += detector.process(frame(0.10, touches: [(1, .moved, 0.32, 0.51)]))
        events += detector.process(frame(0.20, touches: [(1, .moved, 0.45, 0.52)]))
        events += detector.process(frame(0.25, touches: [(1, .ended, 0.45, 0.52)]))
        events += detector.flush(at: 0.6)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .swipe)
        XCTAssertEqual(events.first?.direction, .right)
    }

    func testSwipeUpTwoFingers() {
        var events: [GestureEvent] = []
        events += detector.process(frame(0.00, touches: [(1, .began, 0.4, 0.2), (2, .began, 0.6, 0.2)]))
        events += detector.process(frame(0.15, touches: [(1, .moved, 0.4, 0.45), (2, .moved, 0.6, 0.45)]))
        events += detector.process(frame(0.25, touches: [(1, .ended, 0.4, 0.5), (2, .ended, 0.6, 0.5)]))
        events += detector.flush(at: 0.6)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .swipe)
        XCTAssertEqual(events.first?.direction, .up)
        XCTAssertEqual(events.first?.fingers, 2)
    }

    // MARK: - TipTap

    func testTipTapRight() {
        var events: [GestureEvent] = []
        events += detector.process(frame(0.00, touches: [(1, .began, 0.3, 0.5)]))
        events += detector.process(frame(0.15, touches: [(1, .moved, 0.3, 0.5)]))
        events += detector.process(frame(0.30, touches: [(1, .moved, 0.3, 0.5), (2, .began, 0.6, 0.5)]))
        events += detector.process(frame(0.40, touches: [(1, .moved, 0.3, 0.5), (2, .ended, 0.6, 0.5)]))
        events += detector.flush(at: 0.8)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .tipTap)
        XCTAssertEqual(events.first?.tipTapSide, .right)
    }

    // MARK: - Strokes

    func testStrokeCircleRecognized() {
        detector.strokeEnabled = true
        let templates = BuiltinStroke.allCases.map(\.template)
        detector.strokeMatcher = { points in
            StrokeRecognizer.recognize(points, templates: templates, threshold: 0.7)?.id
        }

        var events: [GestureEvent] = []
        // Dwell near the tip (trigger zone y >= 0.7).
        events += detector.process(frame(0.00, touches: [(1, .began, 0.5, 0.80)]))
        events += detector.process(frame(0.08, touches: [(1, .moved, 0.5, 0.80)]))
        events += detector.process(frame(0.16, touches: [(1, .moved, 0.5, 0.80)]))
        // Draw a counter-clockwise circle starting at the top.
        let steps = 24
        for i in 1...steps {
            let angle = Double.pi / 2 + 2 * Double.pi * Double(i) / Double(steps)
            let x = 0.5 + 0.22 * cos(angle)
            let y = 0.58 + 0.22 * sin(angle)
            events += detector.process(frame(0.16 + 0.02 * Double(i), touches: [(1, .moved, x, y)]))
        }
        events += detector.process(frame(0.70, touches: [(1, .ended, 0.5, 0.80)]))
        events += detector.flush(at: 1.2)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .stroke)
        XCTAssertEqual(events.first?.strokeTemplateID, BuiltinStroke.circle.uuid)
    }

    func testShortTouchInTriggerZoneStillTapsWhenStrokesEnabled() {
        detector.strokeEnabled = true
        detector.strokeMatcher = { _ in nil }

        var events: [GestureEvent] = []
        events += detector.process(frame(0.00, touches: [(1, .began, 0.5, 0.9)]))
        events += detector.process(frame(0.08, touches: [(1, .ended, 0.5, 0.9)]))
        events += detector.flush(at: 0.5)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .tap)
    }
}
