import Foundation

enum GestureKind: String, Codable, Sendable, CaseIterable {
    case tap
    case swipe
    case tipTap
    case stroke

    var label: String {
        switch self {
        case .tap: return "タップ"
        case .swipe: return "スワイプ"
        case .tipTap: return "TipTap"
        case .stroke: return "ストローク"
        }
    }
}

enum Zone: String, Codable, Sendable, CaseIterable {
    case left, middle, right // column zones (x axis)
    case tip, base           // vertical zones (y axis; tip = far edge)

    var label: String {
        switch self {
        case .left: return "左"
        case .middle: return "中央"
        case .right: return "右"
        case .tip: return "先端"
        case .base: return "手前"
        }
    }

    static func column(forX x: Double) -> Zone {
        if x < 1.0 / 3.0 { return .left }
        if x < 2.0 / 3.0 { return .middle }
        return .right
    }

    static func vertical(forY y: Double) -> Zone {
        y >= 0.5 ? .tip : .base
    }
}

enum SwipeDirection: String, Codable, Sendable, CaseIterable {
    case up, down, left, right

    var label: String {
        switch self {
        case .up: return "上"
        case .down: return "下"
        case .left: return "左"
        case .right: return "右"
        }
    }
}

enum TipTapSide: String, Codable, Sendable, CaseIterable {
    case left, right

    var label: String { self == .left ? "左" : "右" }
}

/// Which device class a binding applies to.
enum DeviceClass: String, Codable, Sendable, CaseIterable {
    case any
    case mouse
    case trackpad

    func matches(_ kind: DeviceKind) -> Bool {
        switch self {
        case .any: return true
        case .mouse: return kind == .magicMouse
        case .trackpad: return kind == .magicTrackpad || kind == .builtInTrackpad
        }
    }

    var label: String {
        switch self {
        case .any: return "すべてのデバイス"
        case .mouse: return "Magic Mouse"
        case .trackpad: return "トラックパッド"
        }
    }
}

/// A recognized gesture occurrence (engine output).
struct GestureEvent: Sendable {
    let deviceKind: DeviceKind
    let kind: GestureKind
    let fingers: Int
    let columnZone: Zone
    let verticalZone: Zone
    let direction: SwipeDirection?
    let tipTapSide: TipTapSide?
    let strokeTemplateID: UUID?
    let timestamp: Double

    var summary: String {
        switch kind {
        case .tap:
            return "\(fingers)本指タップ（\(columnZone.label)・\(verticalZone.label)）"
        case .swipe:
            return "\(fingers)本指スワイプ \(direction?.label ?? "?")"
        case .tipTap:
            return "TipTap \(tipTapSide?.label ?? "?")"
        case .stroke:
            return "ストローク"
        }
    }
}

/// A configurable gesture pattern (what the user binds an action to).
struct GestureSpec: Codable, Hashable, Sendable {
    var kind: GestureKind
    var fingers: Int = 1
    var device: DeviceClass = .any
    var zone: Zone?
    var direction: SwipeDirection?
    var tipTapSide: TipTapSide?
    var strokeTemplateID: UUID?

    func matches(_ e: GestureEvent) -> Bool {
        guard kind == e.kind, device.matches(e.deviceKind) else { return false }
        switch kind {
        case .tap:
            return fingers == e.fingers && zoneMatches(e)
        case .swipe:
            return fingers == e.fingers && direction == e.direction && zoneMatches(e)
        case .tipTap:
            return tipTapSide == e.tipTapSide
        case .stroke:
            return strokeTemplateID == e.strokeTemplateID
        }
    }

    private func zoneMatches(_ e: GestureEvent) -> Bool {
        guard let zone else { return true }
        return zone == e.columnZone || zone == e.verticalZone
    }

    /// Higher wins when several specs match the same event.
    var specificity: Int {
        (zone != nil ? 2 : 0) + (device != .any ? 1 : 0)
    }

    func displayName(templates: [StrokeTemplate] = []) -> String {
        let deviceSuffix = device == .any ? "" : "・\(device.label)"
        switch kind {
        case .tap:
            let zonePart = zone.map { "（\($0.label)）" } ?? ""
            return "\(fingers)本指タップ\(zonePart)\(deviceSuffix)"
        case .swipe:
            return "\(fingers)本指スワイプ \(direction?.label ?? "?")\(deviceSuffix)"
        case .tipTap:
            return "TipTap \(tipTapSide?.label ?? "?")\(deviceSuffix)"
        case .stroke:
            let name = templates.first { $0.id == strokeTemplateID }?.name ?? "?"
            return "ストローク「\(name)」\(deviceSuffix)"
        }
    }
}
