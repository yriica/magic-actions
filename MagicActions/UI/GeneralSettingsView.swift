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
                Text("初回起動時に自動でログイン項目へ登録済みです。ここでいつでも解除できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("表示") {
                Toggle("Dock とアプリスイッチャーに表示", isOn: showInDockBinding)
                Toggle("メニューバーにアイコンを表示", isOn: binding(\.showMenuBarIcon))
                    .disabled(!appState.config.settings.showInDock)
                Text("オフにするとメニューバー常駐のみ（既定）になります。メニューバーアイコンを消せるのは Dock 表示中だけです（設定画面へ戻る手段を残すため）。Dock アイコンのクリックでこの設定画面が開きます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("スクロール速度") {
                Toggle("スクロール速度を上書きする（倍率）", isOn: binding(\.scrollSpeedEnabled))
                if appState.config.settings.scrollSpeedEnabled {
                    slider("トラックパッド倍率", value: settingsDouble(\.trackpadScrollMultiplier), in: 0.5...6)
                    slider("Magic Mouse 倍率", value: settingsDouble(\.mouseScrollMultiplier), in: 0.5...6)
                    Text("1.00 が標準。2.00 なら一振りのスクロール量が2倍になり、慣性スクロールにも適用されます。タッチ式スクロール（トラックパッド・Magic Mouse）のみが対象で、ホイール式マウスには影響しません。入力監視の権限が必要です。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("トラックパッドのトラッキング速度") {
                Toggle("システム設定より細かく上書きする", isOn: trackingEnabledBinding)
                if appState.config.settings.trackpadTrackingEnabled {
                    slider(
                        "速度（加速度）",
                        value: settingsDouble(\.trackpadTrackingValue),
                        in: 0...5
                    )
                    .disabled(appState.config.settings.trackpadLinearMode)
                    Toggle("加速を無効化（リニアモード）", isOn: linearModeBinding)
                    LabeledContent("適用中の値") {
                        Text(appliedTrackingText)
                            .monospacedDigit()
                    }
                    Text("システム設定のスライダは10段階ですが、ここでは0.01刻み・最大5.0まで指定できます。システム設定側を操作すると上書きされるため、その場合は本アプリが起動時・スリープ復帰時に再適用します。オフに戻すと元の値へ復元します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("認識チューニング") {
                slider("タップ許容移動量", value: engineBinding(\.tapMaxTravel), in: 0.01...0.15)
                slider("スワイプ最小距離", value: engineBinding(\.swipeMinTravel), in: 0.05...0.4)
                slider("縁のデッドゾーン（左右）", value: engineBinding(\.deadZoneEdgeX), in: 0...0.15)
                slider("縁のデッドゾーン（手前）", value: engineBinding(\.deadZoneBottom), in: 0...0.2)
            }

            Section("ストローク認識") {
                Toggle("面のどこからでも開始できるようにする", isOn: engineBool(\.strokeTriggerAnywhere))
                slider("開始ゾーン（先端側の割合）", value: engineBinding(\.strokeTriggerZoneFraction), in: 0.1...0.8)
                    .disabled(appState.config.settings.engine.strokeTriggerAnywhere)
                slider("静止中の許容移動量", value: engineBinding(\.strokeDwellMaxTravel), in: 0.02...0.2)
                slider("一致しきい値（低いほど緩い）", value: engineBinding(\.strokeScoreThreshold), in: 0.5...0.95)
                Text("発動手順: 1本指で触れて一拍（0.15秒）静止 → そのまま描く → 指を離す。不成立の理由はライブビューの認識ログと HUD に表示されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private func settingsDouble(_ keyPath: WritableKeyPath<AppSettingsModel, Double>) -> Binding<Double> {
        Binding(
            get: { appState.config.settings[keyPath: keyPath] },
            set: { appState.config.settings[keyPath: keyPath] = $0 }
        )
    }

    private func engineBool(_ keyPath: WritableKeyPath<EngineSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { appState.config.settings.engine[keyPath: keyPath] },
            set: { appState.config.settings.engine[keyPath: keyPath] = $0 }
        )
    }

    private var trackingEnabledBinding: Binding<Bool> {
        Binding(
            get: { appState.config.settings.trackpadTrackingEnabled },
            set: { appState.setTrackingEnabled($0) }
        )
    }

    private var linearModeBinding: Binding<Bool> {
        binding(\.trackpadLinearMode)
    }

    private var showInDockBinding: Binding<Bool> {
        Binding(
            get: { appState.config.settings.showInDock },
            set: { appState.setShowInDock($0) }
        )
    }

    private var appliedTrackingText: String {
        guard let value = appState.pointerSpeed.currentTrackpadAcceleration() else { return "-" }
        return value < 0 ? "リニア（加速なし）" : String(format: "%.2f", value)
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

    /// Slider with a companion text field so exact values can be typed directly.
    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                TextField(
                    "",
                    value: clamped(value, to: range),
                    format: .number.precision(.fractionLength(0...2))
                )
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 64)
            }
            Slider(value: value, in: range)
        }
    }

    private func clamped(_ value: Binding<Double>, to range: ClosedRange<Double>) -> Binding<Double> {
        Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }
        )
    }
}
