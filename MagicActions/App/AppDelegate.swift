import AppKit

/// In Dock mode, clicking the Dock icon (reopen) should surface the settings
/// window instead of doing nothing.
final class AppDelegate: NSObject, NSApplicationDelegate {
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
