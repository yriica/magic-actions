import SwiftUI

struct PermissionsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section {
                permissionRow(
                    title: "アクセシビリティ",
                    detail: "ショートカット送出などの操作の実行に必須です。Enter ガードと ⌘ 単押しでの入力切替（キーボードのイベントタップ）にも必須です。",
                    granted: appState.permissions.accessibility,
                    request: { appState.permissions.requestAccessibility() },
                    open: { appState.permissions.openAccessibilityPane() }
                )
                permissionRow(
                    title: "入力監視",
                    detail: "ストローク中のスクロール抑制に使用します。タッチデータの受信や、キーボード機能のキー監視にも必要な場合があります。",
                    granted: appState.permissions.inputMonitoring,
                    request: { appState.permissions.requestInputMonitoring() },
                    open: { appState.permissions.openInputMonitoringPane() }
                )
            } header: {
                Text("必要な権限")
            } footer: {
                Text("許可を変更した後に反映されない場合は、アプリを再起動してください。リストに表示されない場合は、ターミナルで tccutil reset Accessibility / tccutil reset ListenEvent を実行してから再度許可を求めると復旧できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("状態") {
                LabeledContent("イベント送出（PostEvent）") {
                    statusBadge(appState.permissions.postEvent)
                }
                LabeledContent("ライブビューでタッチが見えるか") {
                    Text("タッチデータ受信の実地確認は「ライブビュー」タブで行えます")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("権限")
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        detail: String,
        granted: Bool,
        request: @escaping () -> Void,
        open: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                statusBadge(granted)
                Text(title).font(.headline)
                Spacer()
                if !granted {
                    Button("許可を求める", action: request)
                }
                Button("設定を開く", action: open)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(_ granted: Bool) -> some View {
        Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(granted ? .green : .red)
    }
}
