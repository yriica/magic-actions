import XCTest
@testable import MagicActions

final class StrokeRecognizerTests: XCTestCase {
    private let templates = BuiltinStroke.allCases.map(\.template)

    private func circlePoints(noise: Double = 0.0) -> [CGPoint] {
        (0...40).map { i in
            let angle = Double.pi / 2 + 2 * Double.pi * Double(i) / 40
            let wobble = noise * sin(Double(i) * 1.7)
            return CGPoint(
                x: 0.5 + (0.3 + wobble) * cos(angle),
                y: 0.5 + (0.3 + wobble) * sin(angle)
            )
        }
    }

    private func zigzagPoints() -> [CGPoint] {
        var pts: [CGPoint] = []
        let corners = [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0)]
        for i in 1..<corners.count {
            for s in 0..<12 {
                let t = CGFloat(s) / 12
                let a = corners[i - 1], b = corners[i]
                pts.append(CGPoint(x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y)))
            }
        }
        return pts
    }

    func testCircleRecognized() {
        let result = StrokeRecognizer.recognize(circlePoints(noise: 0.02), templates: templates, threshold: 0.7)
        XCTAssertEqual(result?.id, BuiltinStroke.circle.uuid)
    }

    func testZigzagRecognized() {
        let result = StrokeRecognizer.recognize(zigzagPoints(), templates: templates, threshold: 0.7)
        XCTAssertEqual(result?.id, BuiltinStroke.zigzag.uuid)
    }

    func testVeeRecognized() {
        var pts: [CGPoint] = []
        for s in 0...15 {
            let t = CGFloat(s) / 15
            pts.append(CGPoint(x: t * 0.5, y: 1 - t))
        }
        for s in 1...15 {
            let t = CGFloat(s) / 15
            pts.append(CGPoint(x: 0.5 + t * 0.5, y: t))
        }
        let result = StrokeRecognizer.recognize(pts, templates: templates, threshold: 0.7)
        XCTAssertEqual(result?.id, BuiltinStroke.vee.uuid)
    }

    func testLineUpDetectedAsLine() {
        let pts = (0...20).map { CGPoint(x: 0.5 + 0.01 * sin(Double($0)), y: Double($0) / 20) }
        XCTAssertEqual(StrokeRecognizer.lineDirection(pts), .lineUp)
        let result = StrokeRecognizer.recognize(pts, templates: templates, threshold: 0.7)
        XCTAssertEqual(result?.id, BuiltinStroke.lineUp.uuid)
    }

    func testLineLeftDetected() {
        let pts = (0...20).map { CGPoint(x: 1 - Double($0) / 20, y: 0.5) }
        XCTAssertEqual(StrokeRecognizer.lineDirection(pts), .lineLeft)
    }

    func testCircleIsNotALine() {
        XCTAssertNil(StrokeRecognizer.lineDirection(circlePoints()))
    }

    func testGarbageBelowThresholdRejected() {
        // A tight scribble blob should not confidently match anything.
        let pts = (0...30).map { i in
            CGPoint(x: 0.5 + 0.02 * sin(Double(i) * 3.1), y: 0.5 + 0.02 * cos(Double(i) * 2.3))
        }
        let result = StrokeRecognizer.recognize(pts, templates: templates, threshold: 0.9)
        XCTAssertNil(result)
    }
}
