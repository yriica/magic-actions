import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("動作") {
                Toggle("ジェスチャを有効にする", isOn: binding(\.enabled))
                Toggle("認識時に HUD を表示", isOn: binding(\.showHUD))
                Toggle("トラックパッドでも認識する", isOn: binding(\.watchTrackpad))
                Toggle("ストローク描画中はスクロールを抑制", isOn: binding(\.suppressScrollDuringStroke))
            }

            Section("起動") {
                LoginItemToggle(manager: appState.loginItem)
            }

            Section("認識チューニング") {
                slider("タップ許容移動量", value: engineBinding(\.tapMaxTravel), in: 0.01...0.15)
                slider("スワイプ最小距離", value: engineBinding(\.swipeMinTravel), in: 0.05...0.4)
                slider("縁のデッドゾーン（左右）", value: engineBinding(\.deadZoneEdgeX), in: 0...0.15)
                slider("縁のデッドゾーン（手前）", value: engineBinding(\.deadZoneBottom), in: 0...0.2)
                slider("ストローク開始ゾーン（先端側の割合）", value: engineBinding(\.strokeTriggerZoneFraction), in: 0.1...0.6)
            }

            Section("設定ファイル") {
                LabeledContent("保存先") {
                    Text(ConfigStore.configURL.path)
                        .font(.caption)
                        .textSelection(.enabled)
                }
                Button("Finder で表示") {
                    NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.configURL])
                }
            }

            Section("情報") {
                LabeledContent("バージョン") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("一般")
    }

    private func binding(_ keyPath: WritableKeyPath<AppSettingsModel, Bool>) -> Binding<Bool> {
        Binding(
            get: { appState.config.settings[keyPath: keyPath] },
            set: { appState.config.settings[keyPath: keyPath] = $0 }
        )
    }

    private func engineBinding(_ keyPath: WritableKeyPath<EngineSettings, Double>) -> Binding<Double> {
        Binding(
            get: { appState.config.settings.engine[keyPath: keyPath] },
            set: { appState.config.settings.engine[keyPath: keyPath] = $0 }
        )
    }

    private struct LoginItemToggle: View {
        @ObservedObject var manager: LoginItemManager

        var body: some View {
            Toggle("ログイン時に起動", isOn: $manager.isEnabled)
        }
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
        }
    }
}
