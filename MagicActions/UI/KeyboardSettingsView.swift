import Carbon
import SwiftUI
import UniformTypeIdentifiers

struct KeyboardSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            KeyboardStatusSection(permissions: appState.permissions)

            Section {
                Toggle("Enter ガードを有効にする", isOn: enterGuardBinding)
                if appState.config.settings.enterGuardEnabled {
                    Toggle("変換中の Return は確定だけに使う（推奨）", isOn: binding(\.enterGuardIMEPassthrough))
                    Text("オン: 日本語入力の未確定文字列があるときの Return は、そのまま IME に渡して変換確定だけを行います。オフ: 変換中でも Shift+Return として渡します（送信は確実に防げますが、確定と同時に改行が1つ入る場合があります）。対象アプリで「変換確定の Return で送信されてしまう」ときはオフにしてください。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Enter ガード")
            } footer: {
                Text("対象アプリが前面のとき、Return を改行（Shift+Return）に、⌘Return を送信（Return）に置き換えます。Shift / Control / Option 付きの Return は変更しません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if appState.config.settings.enterGuardEnabled {
                Section("対象アプリ") {
                    if appState.config.settings.enterGuardApps.isEmpty {
                        Text("対象アプリがありません。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(appState.config.settings.enterGuardApps) { app in
                        appRow(app)
                    }
                    HStack {
                        Button("アプリを追加…", action: addApp)
                        if !missingDefaults.isEmpty {
                            Button("既定のアプリを戻す") {
                                appState.config.settings.enterGuardApps.append(contentsOf: missingDefaults)
                            }
                        }
                    }
                }
            }

            Section {
                Toggle("左⌘の単押しで英数、右⌘の単押しでかな", isOn: commandTapBinding)
            } header: {
                Text("⌘ 単押しで入力切替")
            } footer: {
                Text("⌘ を押して離すまでの間に他のキー・修飾キー・クリック・スクロールがなく、0.6 秒以内に離したときだけ切り替えます。⌘C などの組み合わせは通常どおり動作します。切り替えは JIS の「英数」「かな」キーを送出して行うため、入力ソースに ABC と日本語（ローマ字入力）が有効になっている必要があります。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("キーボード")
    }

    // MARK: - Target apps

    private var missingDefaults: [EnterGuardApp] {
        let current = Set(appState.config.settings.enterGuardApps.map(\.bundleID))
        return EnterGuardApp.defaults.filter { !current.contains($0.bundleID) }
    }

    private func appRow(_ app: EnterGuardApp) -> some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)
        return HStack(spacing: 10) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "questionmark.app.dashed")
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                Text(url == nil ? "\(app.bundleID)（未インストール）" : app.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Button(role: .destructive) {
                appState.config.settings.enterGuardApps.removeAll { $0.bundleID == app.bundleID }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("対象から外す")
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.message = "Enter ガードを適用するアプリを選択"
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier else { return }
        guard !appState.config.settings.enterGuardApps.contains(where: { $0.bundleID == bundleID }) else { return }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        appState.config.settings.enterGuardApps.append(EnterGuardApp(bundleID: bundleID, name: name))
    }

    // MARK: - Bindings

    private var enterGuardBinding: Binding<Bool> {
        Binding(
            get: { appState.config.settings.enterGuardEnabled },
            set: { appState.setEnterGuardEnabled($0) }
        )
    }

    private var commandTapBinding: Binding<Bool> {
        Binding(
            get: { appState.config.settings.commandTapInputSwitch },
            set: { appState.setCommandTapInputSwitch($0) }
        )
    }

    private func binding(_ keyPath: WritableKeyPath<AppSettingsModel, Bool>) -> Binding<Bool> {
        Binding(
            get: { appState.config.settings[keyPath: keyPath] },
            set: { appState.config.settings[keyPath: keyPath] = $0 }
        )
    }
}

/// Observes PermissionMonitor directly so the 2-second poll redraws the badges.
private struct KeyboardStatusSection: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var permissions: PermissionMonitor

    var body: some View {
        Section {
            statusRow(
                "アクセシビリティ（必須）",
                ok: permissions.accessibility,
                request: { permissions.requestAccessibility() },
                open: { permissions.openAccessibilityPane() }
            )
            statusRow(
                "入力監視（環境により必要）",
                ok: permissions.inputMonitoring,
                request: { permissions.requestInputMonitoring() },
                open: { permissions.openInputMonitoringPane() }
            )
            LabeledContent("キーボードフック") {
                HStack(spacing: 6) {
                    tapStatus
                    Button("再接続") { appState.reconnectKeyboardTap() }
                        .controlSize(.small)
                }
            }
            if IsSecureEventInputEnabled() {
                Label("セキュア入力が有効です（パスワード欄やターミナルの「セキュアキーボード入力」）。その間はキーボード機能が一時停止します。", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("権限と状態")
        } footer: {
            Text("下の機能をオンにすると、システムが「アクセシビリティ」の許可を求めます。システム設定で MagicActions をオンにしたら、数秒で「稼働中」になります。ならない場合は「再接続」、それでも駄目ならアプリを再起動してください。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var tapStatus: some View {
        if appState.keyboardTapActive {
            Label("稼働中", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if appState.keyboardFeaturesWanted {
            Label("停止中（権限を確認）", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else {
            Label("未使用（機能がオフ）", systemImage: "minus.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func statusRow(
        _ title: String,
        ok: Bool,
        request: @escaping () -> Void,
        open: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
            Text(title)
            Spacer()
            if !ok {
                Button("許可を求める", action: request)
            }
            Button("設定を開く", action: open)
        }
    }
}
