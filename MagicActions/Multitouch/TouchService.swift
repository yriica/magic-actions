import Foundation
import os.lock

/// Wraps the private MultitouchSupport framework: enumerates devices, starts and
/// stops contact-frame callbacks, and handles Bluetooth hot-plug via periodic rescans.
final class TouchService: @unchecked Sendable {
    /// Frame delivery, on an arbitrary background thread. Timestamps are rebased
    /// to ProcessInfo.systemUptime so they share a clock with NSEvent timestamps.
    var onFrame: (@Sendable (TouchFrame) -> Void)?
    /// Device set changes, on an arbitrary background thread.
    var onDevicesChanged: (@Sendable ([DeviceInfo]) -> Void)?

    private let queue = DispatchQueue(label: "com.hirano.magicactions.touch")
    private var running = false
    private var deviceList: NSArray?
    private var infos: [DeviceInfo] = []
    private var rescanTimer: DispatchSourceTimer?

    /// Pointer (bit pattern) → info lookup for the C callback (called on MT's own thread).
    private static let lookup = OSAllocatedUnfairLock<[UInt: DeviceInfo]>(initialState: [:])
    nonisolated(unsafe) static var current: TouchService?

    init() {
        TouchService.current = self
    }

    func start() {
        queue.async { self.startLocked() }
    }

    func stop() {
        queue.async { self.stopLocked() }
    }

    func rescan() {
        queue.async { self.rescanLocked() }
    }

    func currentDevices() -> [DeviceInfo] {
        queue.sync { infos }
    }

    // MARK: - Queue-confined internals

    private func startLocked() {
        guard !running else { return }
        let list = (MTDeviceCreateList()?.takeRetainedValue()) as NSArray?
        var newInfos: [DeviceInfo] = []
        var map: [UInt: DeviceInfo] = [:]

        if let list {
            for item in list {
                let ref = UnsafeMutableRawPointer(Unmanaged.passUnretained(item as AnyObject).toOpaque())
                let info = TouchService.readInfo(ref)
                newInfos.append(info)
                map[UInt(bitPattern: ref)] = info
                MTRegisterContactFrameCallback(ref, magicActionsFrameCallback)
                _ = MTDeviceStart(ref, 0)
            }
        }

        deviceList = list
        infos = newInfos
        let snapshot = map
        TouchService.lookup.withLock { $0 = snapshot }
        running = true
        scheduleRescanTimer()
        onDevicesChanged?(newInfos)
    }

    private func stopLocked() {
        guard running else { return }
        if let list = deviceList {
            for item in list {
                let ref = UnsafeMutableRawPointer(Unmanaged.passUnretained(item as AnyObject).toOpaque())
                MTUnregisterContactFrameCallback(ref, magicActionsFrameCallback)
                if MTDeviceIsRunning(ref) { _ = MTDeviceStop(ref) }
            }
        }
        deviceList = nil
        infos = []
        TouchService.lookup.withLock { $0 = [:] }
        rescanTimer?.cancel()
        rescanTimer = nil
        running = false
    }

    /// Re-enumerate; if the device set changed (Bluetooth connect/disconnect), restart.
    private func rescanLocked() {
        guard running else { return }
        guard let freshList = (MTDeviceCreateList()?.takeRetainedValue()) as NSArray? else { return }
        var freshIDs = Set<UInt64>()
        for item in freshList {
            let ref = UnsafeMutableRawPointer(Unmanaged.passUnretained(item as AnyObject).toOpaque())
            freshIDs.insert(TouchService.readInfo(ref).id)
        }
        let currentIDs = Set(infos.map(\.id))
        guard freshIDs != currentIDs else { return }
        stopLocked()
        startLocked()
    }

    private func scheduleRescanTimer() {
        rescanTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 4, repeating: 4)
        timer.setEventHandler { [weak self] in self?.rescanLocked() }
        timer.resume()
        rescanTimer = timer
    }

    private static func readInfo(_ ref: UnsafeMutableRawPointer) -> DeviceInfo {
        var familyID: Int32 = -1
        _ = MTDeviceGetFamilyID(ref, &familyID)
        var deviceID: UInt64 = 0
        _ = MTDeviceGetDeviceID(ref, &deviceID)
        var width: Int32 = 0
        var height: Int32 = 0
        _ = MTDeviceGetSensorSurfaceDimensions(ref, &width, &height)
        let isBuiltIn = MTDeviceIsBuiltIn(ref)
        return DeviceInfo(
            id: deviceID,
            familyID: familyID,
            kind: DeviceKind.from(familyID: familyID, isBuiltIn: isBuiltIn),
            isBuiltIn: isBuiltIn,
            surfaceWidth: width,
            surfaceHeight: height
        )
    }

    // Called from the C callback.
    static func deviceInfo(for ref: UnsafeMutableRawPointer) -> DeviceInfo? {
        let key = UInt(bitPattern: ref)
        return lookup.withLock { $0[key] }
    }
}

/// C callback registered with MTRegisterContactFrameCallback.
private func magicActionsFrameCallback(
    _ device: MTDeviceRef?,
    _ touches: UnsafeMutablePointer<MTTouch>?,
    _ numTouches: Int32,
    _ timestamp: Double,
    _ frame: Int32
) {
    guard let device, let service = TouchService.current else { return }
    guard let info = TouchService.deviceInfo(for: device) else { return }

    var points: [TouchPoint] = []
    if let touches, numTouches > 0 {
        points.reserveCapacity(Int(numTouches))
        for i in 0..<Int(numTouches) {
            let t = touches[i]
            let phase: TouchPhase
            switch t.state {
            case MTTouchState(MTTouchStateMakeTouch): phase = .began
            case MTTouchState(MTTouchStateTouching): phase = .moved
            case MTTouchState(MTTouchStateBreakTouch): phase = .ended
            default: phase = .hover
            }
            points.append(TouchPoint(
                id: t.identifier,
                phase: phase,
                x: Double(t.normalizedPosition.position.x),
                y: Double(t.normalizedPosition.position.y),
                velocityX: Double(t.normalizedPosition.velocity.x),
                velocityY: Double(t.normalizedPosition.velocity.y),
                size: Double(t.total),
                pressure: Double(t.pressure)
            ))
        }
    }

    let touchFrame = TouchFrame(
        deviceID: info.id,
        deviceKind: info.kind,
        timestamp: ProcessInfo.processInfo.systemUptime,
        touches: points
    )
    service.onFrame?(touchFrame)
}
