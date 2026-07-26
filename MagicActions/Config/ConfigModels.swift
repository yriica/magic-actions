import Foundation
import CoreGraphics

struct GestureBinding: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String = ""
    var spec: GestureSpec
    var action: Action
    var isEnabled = true

    func title(templates: [StrokeTemplate]) -> String {
        name.isEmpty ? spec.displayName(templates: templates) : name
    }
}

struct Profile: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    /// Empty = global profile (applies to every app).
    var appBundleIDs: [String] = []
    var bindings: [GestureBinding] = []

    var isGlobal: Bool { appBundleIDs.isEmpty }
}

struct StrokeTemplate: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var points: [CGPoint]
    var isBuiltin = false
}

struct AppSettingsModel: Codable, Hashable, Sendable {
    var enabled = true
    var showHUD = true
    var watchTrackpad = true
    var suppressScrollDuringStroke = true
    var engine = EngineSettings.standard

    /// Trackpad tracking-speed override (finer than the System Settings slider).
    var trackpadTrackingEnabled = false
    var trackpadTrackingValue = 3.0
    var trackpadLinearMode = false
    /// Acceleration captured before the first override, for restoration.
    var trackpadTrackingOriginal: Double?

    /// One-time flag: login item was auto-registered on first launch.
    var loginItemAutoConfigured = false

    private enum CodingKeys: String, CodingKey {
        case enabled, showHUD, watchTrackpad, suppressScrollDuringStroke, engine
        case trackpadTrackingEnabled, trackpadTrackingValue, trackpadLinearMode, trackpadTrackingOriginal
        case loginItemAutoConfigured
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        showHUD = try c.decodeIfPresent(Bool.self, forKey: .showHUD) ?? true
        watchTrackpad = try c.decodeIfPresent(Bool.self, forKey: .watchTrackpad) ?? true
        suppressScrollDuringStroke = try c.decodeIfPresent(Bool.self, forKey: .suppressScrollDuringStroke) ?? true
        engine = try c.decodeIfPresent(EngineSettings.self, forKey: .engine) ?? .standard
        trackpadTrackingEnabled = try c.decodeIfPresent(Bool.self, forKey: .trackpadTrackingEnabled) ?? false
        trackpadTrackingValue = try c.decodeIfPresent(Double.self, forKey: .trackpadTrackingValue) ?? 3.0
        trackpadLinearMode = try c.decodeIfPresent(Bool.self, forKey: .trackpadLinearMode) ?? false
        trackpadTrackingOriginal = try c.decodeIfPresent(Double.self, forKey: .trackpadTrackingOriginal)
        loginItemAutoConfigured = try c.decodeIfPresent(Bool.self, forKey: .loginItemAutoConfigured) ?? false
    }
}

struct AppConfig: Codable, Hashable, Sendable {
    var version = 1
    var settings = AppSettingsModel()
    var profiles: [Profile] = []
    var strokeTemplates: [StrokeTemplate] = []

    /// All templates available to the recognizer/UI: built-ins plus user templates.
    var allStrokeTemplates: [StrokeTemplate] {
        BuiltinStroke.allCases.map(\.template) + strokeTemplates
    }

    static func makeDefault() -> AppConfig {
        var config = AppConfig()
        let samples = [
            GestureBinding(
                name: "",
                spec: GestureSpec(kind: .tap, fingers: 2, device: .mouse),
                action: .system(.missionControl),
                isEnabled: true
            ),
            GestureBinding(
                name: "",
                spec: GestureSpec(kind: .tap, fingers: 3, device: .mouse),
                action: .system(.playPause),
                isEnabled: true
            ),
            GestureBinding(
                name: "",
                spec: GestureSpec(kind: .tap, fingers: 1, device: .mouse, zone: .tip),
                action: .system(.middleClick),
                isEnabled: false
            ),
        ]
        config.profiles = [Profile(name: "グローバル", appBundleIDs: [], bindings: samples)]
        return config
    }

    /// Resolve the binding for an event given the frontmost app.
    /// App-specific profiles win over the global profile; within a profile,
    /// more specific specs (zone/device constrained) win.
    func resolveBinding(for event: GestureEvent, frontmostBundleID: String?) -> GestureBinding? {
        let appProfiles = profiles.filter { p in
            guard let bundleID = frontmostBundleID else { return false }
            return p.appBundleIDs.contains(bundleID)
        }
        let globalProfiles = profiles.filter(\.isGlobal)
        for profileSet in [appProfiles, globalProfiles] {
            let matches = profileSet
                .flatMap(\.bindings)
                .filter { $0.isEnabled && $0.spec.matches(event) }
                .sorted { $0.spec.specificity > $1.spec.specificity }
            if let best = matches.first { return best }
        }
        return nil
    }
}
