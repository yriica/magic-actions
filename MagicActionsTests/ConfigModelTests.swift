import XCTest
@testable import MagicActions

final class ConfigModelTests: XCTestCase {
    func testActionCodableRoundTrip() throws {
        let actions: [Action] = [
            .keyboardShortcut(KeyCombo(keyCode: 8, modifiers: 1 << 20, display: "⌘C")),
            .launchApp(bundleID: "com.apple.Safari", name: "Safari"),
            .openURL(url: "https://note.com"),
            .runShell(command: "echo hello"),
            .runAppleScript(source: "display notification \"hi\""),
            .system(.missionControl),
        ]
        let data = try JSONEncoder().encode(actions)
        let decoded = try JSONDecoder().decode([Action].self, from: data)
        XCTAssertEqual(actions, decoded)
    }

    func testAppConfigRoundTrip() throws {
        let config = AppConfig.makeDefault()
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(config, decoded)
    }

    func testEngineSettingsToleratesMissingKeys() throws {
        let decoded = try JSONDecoder().decode(EngineSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, EngineSettings.standard)
    }

    func testAppSettingsToleratesMissingKeys() throws {
        let decoded = try JSONDecoder().decode(AppSettingsModel.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, AppSettingsModel())
        XCTAssertFalse(decoded.trackpadTrackingEnabled)
        XCTAssertFalse(decoded.loginItemAutoConfigured)
    }

    private func event(kind: GestureKind, fingers: Int, column: Zone = .middle, vertical: Zone = .base,
                       device: DeviceKind = .magicMouse) -> GestureEvent {
        GestureEvent(deviceKind: device, kind: kind, fingers: fingers,
                     columnZone: column, verticalZone: vertical,
                     direction: nil, tipTapSide: nil, strokeTemplateID: nil, timestamp: 0)
    }

    func testZoneSpecificBindingWinsOverGeneric() {
        var config = AppConfig()
        let generic = GestureBinding(
            spec: GestureSpec(kind: .tap, fingers: 1),
            action: .system(.missionControl)
        )
        let zoned = GestureBinding(
            spec: GestureSpec(kind: .tap, fingers: 1, zone: .tip),
            action: .system(.playPause)
        )
        config.profiles = [Profile(name: "グローバル", appBundleIDs: [], bindings: [generic, zoned])]

        let resolved = config.resolveBinding(
            for: event(kind: .tap, fingers: 1, vertical: .tip),
            frontmostBundleID: nil
        )
        XCTAssertEqual(resolved?.id, zoned.id)

        let baseResolved = config.resolveBinding(
            for: event(kind: .tap, fingers: 1, vertical: .base),
            frontmostBundleID: nil
        )
        XCTAssertEqual(baseResolved?.id, generic.id)
    }

    func testAppProfileWinsOverGlobal() {
        var config = AppConfig()
        let globalBinding = GestureBinding(
            spec: GestureSpec(kind: .tap, fingers: 2),
            action: .system(.missionControl)
        )
        let safariBinding = GestureBinding(
            spec: GestureSpec(kind: .tap, fingers: 2),
            action: .system(.playPause)
        )
        config.profiles = [
            Profile(name: "グローバル", appBundleIDs: [], bindings: [globalBinding]),
            Profile(name: "Safari", appBundleIDs: ["com.apple.Safari"], bindings: [safariBinding]),
        ]

        let inSafari = config.resolveBinding(for: event(kind: .tap, fingers: 2), frontmostBundleID: "com.apple.Safari")
        XCTAssertEqual(inSafari?.id, safariBinding.id)

        let elsewhere = config.resolveBinding(for: event(kind: .tap, fingers: 2), frontmostBundleID: "com.apple.finder")
        XCTAssertEqual(elsewhere?.id, globalBinding.id)
    }

    func testDisabledBindingNotResolved() {
        var config = AppConfig()
        var binding = GestureBinding(
            spec: GestureSpec(kind: .tap, fingers: 3),
            action: .system(.mute)
        )
        binding.isEnabled = false
        config.profiles = [Profile(name: "グローバル", appBundleIDs: [], bindings: [binding])]

        XCTAssertNil(config.resolveBinding(for: event(kind: .tap, fingers: 3), frontmostBundleID: nil))
    }
}
