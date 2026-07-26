import AppKit
import ApplicationServices

/// Tracks the TCC grants this app needs and offers request/deep-link helpers.
/// - Accessibility: required to post synthesized events (CGEventPost fails silently without it).
/// - Input Monitoring: required for the scroll-suppression event tap; may also gate
///   multitouch frame delivery on recent macOS.
@MainActor
final class PermissionMonitor: ObservableObject {
    @Published private(set) var accessibility = false
    @Published private(set) var inputMonitoring = false
    @Published private(set) var postEvent = false

    private var timer: Timer?

    var allGranted: Bool { accessibility && inputMonitoring }

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func refresh() {
        accessibility = AXIsProcessTrusted()
        inputMonitoring = CGPreflightListenEventAccess()
        postEvent = CGPreflightPostEventAccess()
    }

    func requestAccessibility() {
        // Literal key avoids touching the non-Sendable global kAXTrustedCheckOptionPrompt.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
    }

    func openAccessibilityPane() {
        openPane("Privacy_Accessibility")
    }

    func openInputMonitoringPane() {
        openPane("Privacy_ListenEvent")
    }

    private func openPane(_ anchor: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        NSWorkspace.shared.open(url)
    }
}
