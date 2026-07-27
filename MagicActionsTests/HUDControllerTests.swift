import XCTest
@testable import MagicActions

/// Regression test for the v0.5.0 launch crash: showing the HUD panel threw
/// NSInternalInconsistencyException during the AppKit constraint pass
/// (NSHostingView driving window size extrema inside a borderless panel).
@MainActor
final class HUDControllerTests: XCTestCase {
    func testShowSurvivesDisplayCycle() async throws {
        let hud = HUDController()
        hud.show("回帰テスト: 不一致「丸」0.62 / 0.70")
        // Let the display/constraint cycle run; the old implementation crashed here.
        try await Task.sleep(nanoseconds: 700_000_000)
        hud.show("2回目の表示（ビュー使い回し経路）")
        try await Task.sleep(nanoseconds: 400_000_000)
    }
}
