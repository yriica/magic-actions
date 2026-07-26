import Foundation

/// Device classification derived from the multitouch family ID.
enum DeviceKind: String, Codable, Sendable, CaseIterable {
    case magicMouse
    case magicTrackpad
    case builtInTrackpad
    case unknown

    /// Known family IDs (empirical, from open-source MultitouchSupport users):
    /// 110 = built-in trackpad (verified on this machine), 112/113 = Magic Mouse,
    /// 128-131 = external Magic Trackpads (129 verified on this machine).
    static func from(familyID: Int32, isBuiltIn: Bool) -> DeviceKind {
        if isBuiltIn { return .builtInTrackpad }
        switch familyID {
        case 112, 113: return .magicMouse
        case 128...131: return .magicTrackpad
        case 98...111: return .builtInTrackpad
        default: return .unknown
        }
    }

    var label: String {
        switch self {
        case .magicMouse: return "Magic Mouse"
        case .magicTrackpad: return "Magic Trackpad"
        case .builtInTrackpad: return "内蔵トラックパッド"
        case .unknown: return "不明なデバイス"
        }
    }

    /// Surface aspect ratio (width / height) used by the live canvas.
    /// Magic Mouse surface is tall (5152x9056), trackpads are wide.
    var surfaceAspect: Double {
        switch self {
        case .magicMouse: return 0.57
        case .magicTrackpad: return 15600.0 / 11040.0
        case .builtInTrackpad: return 12194.0 / 7408.0
        case .unknown: return 1.0
        }
    }
}

struct DeviceInfo: Identifiable, Hashable, Sendable {
    let id: UInt64
    let familyID: Int32
    let kind: DeviceKind
    let isBuiltIn: Bool
    let surfaceWidth: Int32
    let surfaceHeight: Int32

    var label: String { kind.label }
}

/// Lifecycle phase of a single touch, mapped from MTTouchState.
enum TouchPhase: Sendable {
    case began   // MakeTouch
    case moved   // Touching
    case ended   // BreakTouch and beyond
    case hover   // in-range but not touching (ignored by the engine)
}

struct TouchPoint: Sendable {
    let id: Int32
    let phase: TouchPhase
    /// Normalized position, 0..1, origin bottom-left.
    let x: Double
    let y: Double
    let velocityX: Double
    let velocityY: Double
    /// Total capacitance ("size" of the contact).
    let size: Double
    let pressure: Double
}

struct TouchFrame: Sendable {
    let deviceID: UInt64
    let deviceKind: DeviceKind
    let timestamp: Double
    let touches: [TouchPoint]
}
