import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("ジェスチャを有効にする", isOn: enabledBinding)

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
