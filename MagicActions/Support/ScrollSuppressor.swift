import AppKit
import CoreGraphics
import os

/// Swallows scroll-wheel events while a stroke is being drawn so the page under
/// the cursor does not scroll. Uses an active CGEventTap, which requires the
/// Input Monitoring (and in practice Accessibility) permission.
final class ScrollSuppressor: @unchecked Sendable {
    private let active = OSAllocatedUnfairLock(initialState: false)
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var unavailable = false

    var isActive: Bool { active.withLock { $0 } }

    /// Main thread only (installs the tap into the main run loop on first use).
    func setActive(_ shouldSuppress: Bool) {
        active.withLock { $0 = shouldSuppress }
        if shouldSuppress, tap == nil, !unavailable {
            createTap()
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: shouldSuppress)
        }
    }

    private func createTap() {
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let suppressor = Unmanaged<ScrollSuppressor>.fromOpaque(refcon).takeUnretainedValue()
                return suppressor.isActive ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            unavailable = true
            NSLog("MagicActions: scroll suppression tap unavailable (missing Input Monitoring?)")
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }
}
