import AppKit
import Combine
import CoreGraphics
import SwiftUI
import os

/// Flags read from background threads (touch callback) without hopping to the main actor.
final class RuntimeFlags: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: State())

    private struct State {
        var watchTrackpad = true
        var liveViewActive = false
    }

    var watchTrackpad: Bool {
        get { lock.withLock { $0.watchTrackpad } }
        set { lock.withLock { $0.watchTrackpad = newValue } }
    }

    var liveViewActive: Bool {
        get { lock.withLock { $0.liveViewActive } }
        set { lock.withLock { $0.liveViewActive = newValue } }
    }
}

/// Central wiring: TouchService → GestureEngine → binding resolution → ActionDispatcher,
/// plus live view feed, recorder capture routing, and permission/profile plumbing.
@MainActor
final class AppState: ObservableObject {
    let configStore = ConfigStore()
    let permissions = PermissionMonitor()
    let frontmost = FrontmostAppMonitor()
    let loginItem = LoginItemManager()
    let dispatcher = ActionDispatcher()

    private let touch = TouchService()
    private let engine = GestureEngine()
    private let buttons = ButtonMonitor()
    private let suppressor = ScrollSuppressor()
    private let hud = HUDController()
    private let runtime = RuntimeFlags()

    @Published private(set) var devices: [DeviceInfo] = []
    @Published private(set) var liveFrames: [UInt64: TouchFrame] = [:]
    @Published private(set) var gestureLog: [String] = []

    /// Recorder sheet capture: while set, recognized gestures go here instead of dispatch.
    var gestureCapture: ((GestureEvent) -> Void)?
    /// Stroke-template recording: while set, every raw touch path is delivered here.
    var strokeCapture: (([CGPoint], DeviceKind) -> Void)? {
        didSet { engine.setCaptureAllStrokes(strokeCapture != nil) }
    }

    private var cancellables: Set<AnyCancellable> = []
    private var sleepObservers: [NSObjectProtocol] = []
    private var recorderArmed = false

    var config: AppConfig {
        get { configStore.config }
        set { configStore.config = newValue }
    }

    var magicMouseConnected: Bool {
        devices.contains { $0.kind == .magicMouse }
    }

    init() {
        wire()
        applyConfig(configStore.config)
        buttons.start()
        touch.start()
        observeSleepWake()
    }

    // MARK: - Wiring

    private func wire() {
        let engine = engine
        let runtime = runtime

        touch.onFrame = { [weak self] frame in
            // Background thread: filter and forward without touching the main actor.
            let deviceAllowed = frame.deviceKind == .magicMouse
                || (runtime.watchTrackpad && frame.deviceKind != .unknown)
            if deviceAllowed {
                engine.ingest(frame)
            }
            if runtime.liveViewActive {
                Task { @MainActor [weak self] in
                    self?.liveFrames[frame.deviceID] = frame
                }
            }
        }

        touch.onDevicesChanged = { [weak self] infos in
            Task { @MainActor [weak self] in
                self?.devices = infos
            }
        }

        engine.onGesture = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event)
            }
        }

        engine.onRawStroke = { [weak self] points, kind in
            Task { @MainActor [weak self] in
                self?.strokeCapture?(points, kind)
            }
        }

        engine.onScrollSuppressionChange = { [weak self] wants in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let allowed = self.config.settings.suppressScrollDuringStroke && self.permissions.inputMonitoring
                self.suppressor.setActive(wants && allowed)
            }
        }

        buttons.onButtonDown = { [engine] time in
            engine.noteButton(at: time)
        }
        buttons.onScroll = { [engine] amount, time in
            engine.noteScroll(amount: amount, at: time)
        }

        configStore.$config
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newConfig in
                self?.applyConfig(newConfig)
            }
            .store(in: &cancellables)
    }

    private func applyConfig(_ config: AppConfig) {
        runtime.watchTrackpad = config.settings.watchTrackpad
        engine.updateSettings(config.settings.engine)

        let hasStrokeBindings = config.profiles
            .flatMap(\.bindings)
            .contains { $0.isEnabled && $0.spec.kind == .stroke }
        let templates = config.allStrokeTemplates
        let threshold = config.settings.engine.strokeScoreThreshold
        engine.setStrokeMatcher(enabled: hasStrokeBindings || recorderArmed) { points in
            StrokeRecognizer.recognize(points, templates: templates, threshold: threshold)?.id
        }
    }

    /// While the recorder sheet is open, arm stroke recognition even before any
    /// stroke binding exists (otherwise the first stroke could never be captured).
    func setRecorderArmed(_ armed: Bool) {
        recorderArmed = armed
        applyConfig(configStore.config)
    }

    private func observeSleepWake() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [touch] _ in
            touch.stop()
        })
        sleepObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [touch] _ in
            touch.start()
        })
    }

    // MARK: - Gesture handling

    private func handle(_ event: GestureEvent) {
        log("認識: \(event.summary)（\(event.deviceKind.label)）")

        if let capture = gestureCapture {
            capture(event)
            return
        }
        guard config.settings.enabled else { return }
        guard let binding = config.resolveBinding(for: event, frontmostBundleID: frontmost.bundleID) else {
            return
        }
        if config.settings.showHUD {
            hud.show(binding.title(templates: config.allStrokeTemplates))
        }
        log("実行: \(binding.action.displayName)")
        dispatcher.perform(binding.action)
    }

    private func log(_ line: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        gestureLog.insert("\(formatter.string(from: Date())) \(line)", at: 0)
        if gestureLog.count > 30 {
            gestureLog.removeLast(gestureLog.count - 30)
        }
    }

    // MARK: - Live view control

    func setLiveViewActive(_ active: Bool) {
        runtime.liveViewActive = active
        if !active {
            liveFrames = [:]
        }
    }

    func rescanDevices() {
        touch.rescan()
    }

    /// Fire an action immediately (used by the "試す" button in the editor).
    func testRun(_ action: Action) {
        dispatcher.perform(action)
    }
}
