import Foundation
import IOKit

/// Overrides the trackpad tracking speed (pointer acceleration) with finer
/// granularity than the System Settings slider.
///
/// Route: IOHIDSystem parameter connection (IOServiceOpen with
/// kIOHIDParamConnectType + IOConnectSetCFProperty). Verified working on
/// macOS 26.5, and verifiable by reading back the HIDParameters registry
/// property. The value is session-wide for all trackpads; -1 disables
/// acceleration ("linear" mode). Fixed-point encoding: value * 65536.
@MainActor
final class PointerSpeedManager {
    static let trackpadAccelerationKey = "HIDTrackpadAcceleration"
    private static let hidSystemPath = "IOService:/IOResources/IOHIDSystem"
    private static let paramConnectType: UInt32 = 1 // kIOHIDParamConnectType (IOHIDShared.h)

    /// The acceleration the HID system is currently applying (ground truth).
    func currentTrackpadAcceleration() -> Double? {
        guard let service = hidSystemService() else { return nil }
        defer { IOObjectRelease(service) }
        guard
            let params = IORegistryEntryCreateCFProperty(
                service, "HIDParameters" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any],
            let fixed = params[Self.trackpadAccelerationKey] as? Int
        else { return nil }
        return Double(fixed) / 65536.0
    }

    /// Applies acceleration live (pass -1 for linear mode). Returns success.
    @discardableResult
    func apply(acceleration: Double) -> Bool {
        guard let service = hidSystemService() else { return false }
        defer { IOObjectRelease(service) }

        var connect: io_connect_t = IO_OBJECT_NULL
        guard IOServiceOpen(service, mach_task_self_, Self.paramConnectType, &connect) == KERN_SUCCESS else {
            NSLog("MagicActions: IOHIDSystem param connect failed")
            return false
        }
        defer { IOServiceClose(connect) }

        let fixed = Int32((acceleration * 65536).rounded())
        let result = IOConnectSetCFProperty(
            connect, Self.trackpadAccelerationKey as CFString, fixed as CFNumber
        )
        if result != KERN_SUCCESS {
            NSLog("MagicActions: tracking override write failed: 0x%x", result)
        }
        return result == KERN_SUCCESS
    }

    /// Persists the value as the user preference the system re-derives
    /// acceleration from (survives relogin/reboot without the app running).
    func persistScalingPreference(_ value: Double) {
        CFPreferencesSetValue(
            "com.apple.trackpad.scaling" as CFString,
            value as CFNumber,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    private func hidSystemService() -> io_service_t? {
        let service = Self.hidSystemPath.withCString { cString in
            IORegistryEntryFromPath(kIOMainPortDefault, UnsafeMutablePointer(mutating: cString))
        }
        return service == IO_OBJECT_NULL ? nil : service
    }
}
