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

    /// Scroll-speed override (delta multiplication for touch-based scrolling).
    var scrollSpeedEnabled = false
    /// Adaptive: amplify only fast swipes; slow scrolling stays native (no jank).
    var scrollAdaptive = true
    var trackpadScrollMultiplier = 2.0
    var mouseScrollMultiplier = 1.0

    /// One-time flag: login item was auto-registered on first launch.
    var loginItemAutoConfigured = false

    /// Presentation: show in Dock / app switcher (regular app) vs menu-bar-only.
    var showInDock = false
    /// Menu bar icon can only be hidden while the Dock icon is shown.
    var showMenuBarIcon = true

    private enum CodingKeys: String, CodingKey {
        case enabled, showHUD, watchTrackpad, suppressScrollDuringStroke, engine
        case trackpadTrackingEnabled, trackpadTrackingValue, trackpadLinearMode, trackpadTrackingOriginal
        case scrollSpeedEnabled, scrollAdaptive, trackpadScrollMultiplier, mouseScrollMultiplier
        case loginItemAutoConfigured
        case showInDock, showMenuBarIcon
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
        scrollSpeedEnabled = try c.decodeIfPresent(Bool.self, forKey: .scrollSpeedEnabled) ?? false
        scrollAdaptive = try c.decodeIfPresent(Bool.self, forKey: .scrollAdaptive) ?? true
        trackpadScrollMultiplier = try c.decodeIfPresent(Double.self, forKey: .trackpadScrollMultiplier) ?? 2.0
        mouseScrollMultiplier = try c.decodeIfPresent(Double.self, forKey: .mouseScrollMultiplier) ?? 1.0
        loginItemAutoConfigured = try c.decodeIfPresent(Bool.self, forKey: .loginItemAutoConfigured) ?? false
        showInDock = try c.decodeIfPresent(Bool.self, forKey: .showInDock) ?? false
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
    }
}

struct AppConfig: Codable, Hashable, Sendable {
    var version = 2
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
