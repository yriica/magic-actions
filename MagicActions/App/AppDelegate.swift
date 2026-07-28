import AppKit

/// In Dock mode, clicking the Dock icon (reopen) should surface the settings
/// window instead of doing nothing.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The agent must never die just because its settings window was closed
    /// (e.g. by a gesture-dispatched Cmd+W landing on ourselves).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        if let settings = sender.windows.first(where: { $0.identifier?.rawValue.hasPrefix("settings") ?? false }) {
            settings.makeKeyAndOrderFront(nil)
            sender.activate(ignoringOtherApps: true)
            return false
        }
        return true
    }
}
