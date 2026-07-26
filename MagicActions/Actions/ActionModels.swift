import Foundation

/// A captured keyboard shortcut: virtual key code + CGEventFlags bits.
/// `display` is rendered at capture time with the then-active keyboard layout.
struct KeyCombo: Codable, Hashable, Sendable {
    var keyCode: UInt16
    var modifiers: UInt64
    var display: String
}

enum SystemAction: String, Codable, Hashable, Sendable, CaseIterable {
    case missionControl
    case showDesktop
    case middleClick
    case playPause
    case nextTrack
    case previousTrack
    case volumeUp
    case volumeDown
    case mute

    var label: String {
        switch self {
        case .missionControl: return "Mission Control"
        case .showDesktop: return "デスクトップを表示"
        case .middleClick: return "ミドルクリック"
        case .playPause: return "再生 / 一時停止"
        case .nextTrack: return "次のトラック"
        case .previousTrack: return "前のトラック"
        case .volumeUp: return "音量を上げる"
        case .volumeDown: return "音量を下げる"
        case .mute: return "消音"
        }
    }
}

enum Action: Codable, Hashable, Sendable {
    case keyboardShortcut(KeyCombo)
    case launchApp(bundleID: String, name: String)
    case openURL(url: String)
    case runShell(command: String)
    case runAppleScript(source: String)
    case system(SystemAction)

    var displayName: String {
        switch self {
        case .keyboardShortcut(let combo):
            return "ショートカット \(combo.display)"
        case .launchApp(_, let name):
            return "アプリを開く: \(name)"
        case .openURL(let url):
            return "URLを開く: \(url)"
        case .runShell:
            return "シェルコマンド"
        case .runAppleScript:
            return "AppleScript"
        case .system(let sys):
            return sys.label
        }
    }
}
