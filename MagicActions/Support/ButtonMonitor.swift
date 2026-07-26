import AppKit

/// Observes global mouse button and scroll activity via NSEvent global monitors
/// (mouse-category monitors need no TCC permission). Used to keep physical clicks
/// and real scrolling from being misread as gestures.
@MainActor
final class ButtonMonitor {
    var onButtonDown: ((Double) -> Void)?
    var onScroll: ((Double, Double) -> Void)? // (|delta|, uptime)

    private var monitors: [Any] = []

    func start() {
        guard monitors.isEmpty else { return }
        let buttonMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: buttonMask, handler: { [weak self] _ in
            self?.onButtonDown?(ProcessInfo.processInfo.systemUptime)
        }) {
            monitors.append(m)
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            let amount = abs(event.scrollingDeltaX) + abs(event.scrollingDeltaY)
            self?.onScroll?(amount, ProcessInfo.processInfo.systemUptime)
        }) {
            monitors.append(m)
        }
    }

    func stop() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
    }
}
