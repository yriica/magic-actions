import Foundation

/// Detects collisions between a configured gesture and macOS built-in
/// trackpad gestures (which fire simultaneously and cannot be blocked).
enum SystemGestureConflict {
    static func warning(for spec: GestureSpec) -> String? {
        guard spec.kind == .swipe, spec.fingers == 3, spec.device != .mouse,
              let direction = spec.direction else { return nil }
        let defaults = UserDefaults(suiteName: "com.apple.AppleMultitouchTrackpad")
        switch direction {
        case .up, .down:
            if defaults?.integer(forKey: "TrackpadThreeFingerVertSwipeGesture") != 0 {
                return "macOS の3本指上下スワイプ（Mission Control / アプリケーションExposé）と同時に発動します。システム設定 → トラックパッド → その他のジェスチャ側を無効にするか、別のジェスチャをご利用ください。"
            }
        case .left, .right:
            if defaults?.integer(forKey: "TrackpadThreeFingerHorizSwipeGesture") != 0 {
                return "macOS の3本指左右スワイプ（操作スペースの切替）と同時に発動します。システム設定 → トラックパッド → その他のジェスチャ側を無効にするか、別のジェスチャをご利用ください。"
            }
        }
        return nil
    }
}
