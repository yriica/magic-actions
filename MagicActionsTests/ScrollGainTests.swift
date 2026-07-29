import XCTest
@testable import MagicActions

final class ScrollGainTests: XCTestCase {
    func testSlowScrollStaysNative() {
        XCTAssertEqual(ScrollTap.gain(velocity: 0, maxMultiplier: 3.0), 1.0)
        XCTAssertEqual(ScrollTap.gain(velocity: 400, maxMultiplier: 3.0), 1.0)
    }

    func testFastScrollReachesMaxMultiplier() {
        XCTAssertEqual(ScrollTap.gain(velocity: 5000, maxMultiplier: 3.0), 3.0, accuracy: 0.001)
    }

    func testGainIsMonotonicInBetween() {
        let low = ScrollTap.gain(velocity: 1000, maxMultiplier: 3.0)
        let mid = ScrollTap.gain(velocity: 1600, maxMultiplier: 3.0)
        let high = ScrollTap.gain(velocity: 2200, maxMultiplier: 3.0)
        XCTAssertGreaterThan(low, 1.0)
        XCTAssertGreaterThan(mid, low)
        XCTAssertGreaterThan(high, mid)
        XCTAssertLessThan(high, 3.0)
    }

    func testReducingMultiplierBypassesAdaptiveCurve() {
        // Slow-down multipliers (< 1) are applied as-is regardless of velocity.
        XCTAssertEqual(ScrollTap.gain(velocity: 5000, maxMultiplier: 0.7), 0.7)
        XCTAssertEqual(ScrollTap.gain(velocity: 0, maxMultiplier: 0.7), 0.7)
    }
}
