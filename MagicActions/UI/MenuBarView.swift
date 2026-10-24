import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("ジェスチャを有効にする", isOn: enabledBinding)
        Toggle("Enter ガード", isOn: Binding(
            get: { appState.config.settings.enterGuardEnabled },
            set: { appState.setEnterGuardEnabled($0) }
        ))
        Toggle("⌘ 単押しで英数／かな", isOn: Binding(
            get: { appState.config.settings.commandTapInputSwitch },
            set: { appState.setCommandTapInputSwitch($0) }
        ))
        if appState.keyboardFeaturesWanted && !appState.keyboardTapActive {
            Text("キーボード機能: 権限が必要です（設定 → キーボード）")
        }

        Divider()

        if appState.devices.isEmpty {
            Text("マルチタッチデバイスなし")
        } else {
            ForEach(appState.devices) { device in
                Text("接続中: \(device.label)")
            }
        }
        if !appState.magicMouseConnected {
            Text("Magic Mouse 未接続（電源を確認）")
        }

        Divider()

        Button("設定を開く…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")

        Divider()

        Button("MagicActions を終了") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { appState.config.settings.enabled },
            set: { appState.config.settings.enabled = $0 }
        )
    }
}
