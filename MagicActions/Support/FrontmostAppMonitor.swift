import AppKit

/// Tracks the frontmost application for per-app profile switching.
@MainActor
final class FrontmostAppMonitor: ObservableObject {
    @Published private(set) var bundleID: String?
    @Published private(set) var appName: String?

    private var observer: NSObjectProtocol?

    init() {
        update(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor [weak self] in self?.update(app) }
        }
    }

    private func update(_ app: NSRunningApplication?) {
        bundleID = app?.bundleIdentifier
        appName = app?.localizedName
    }
}
