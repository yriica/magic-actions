import SwiftUI
import UniformTypeIdentifiers

struct GestureListView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedProfileID: UUID?
    @State private var sheetMode: BindingEditorSheet.Mode?

    private var profiles: [Profile] { appState.config.profiles }

    private var selectedProfile: Profile? {
        profiles.first { $0.id == selectedProfileID } ?? profiles.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            profileBar
            Divider()
            bindingList
        }
        .navigationTitle("ジェスチャ")
        .onAppear {
            if selectedProfileID == nil {
                selectedProfileID = profiles.first?.id
            }
        }
        .sheet(item: $sheetMode) { mode in
            BindingEditorSheet(mode: mode)
                .environmentObject(appState)
        }
    }

    private var profileBar: some View {
        HStack {
            Picker("プロファイル", selection: Binding(
                get: { selectedProfile?.id ?? UUID() },
                set: { selectedProfileID = $0 }
            )) {
                ForEach(profiles) { profile in
                    Text(profile.isGlobal ? "グローバル" : profile.name).tag(profile.id)
                }
            }
            .frame(maxWidth: 320)

            Button {
                addAppProfile()
            } label: {
                Label("アプリ別プロファイル", systemImage: "plus")
            }
            .help("特定のアプリが前面のときだけ有効になるプロファイルを追加します")

            if let profile = selectedProfile, !profile.isGlobal {
                Button(role: .destructive) {
                    removeProfile(profile.id)
                } label: {
                    Image(systemName: "trash")
                }
                .help("このプロファイルを削除")
            }

            Spacer()

            Menu {
                Button("ジェスチャを実演して追加…") {
                    if let id = selectedProfile?.id {
                        sheetMode = .newCapture(profileID: id)
                    }
                }
                Button("ストロークを選んで追加…") {
                    if let id = selectedProfile?.id {
                        sheetMode = .newStroke(profileID: id)
                    }
                }
            } label: {
                Label("追加", systemImage: "plus.circle.fill")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(12)
    }

    @ViewBuilder
    private var bindingList: some View {
        if let profile = selectedProfile {
            if profile.bindings.isEmpty {
                ContentUnavailableView(
                    "ジェスチャがありません",
                    systemImage: "hand.tap",
                    description: Text("「追加」からジェスチャを実演して登録してください。")
                )
            } else {
                List {
                    ForEach(profile.bindings) { binding in
                        bindingRow(profileID: profile.id, binding: binding)
                    }
                }
                .listStyle(.inset)
            }
        } else {
            ContentUnavailableView("プロファイルがありません", systemImage: "questionmark")
        }
    }

    private func bindingRow(profileID: UUID, binding: GestureBinding) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { currentBinding(profileID, binding.id)?.isEnabled ?? false },
                set: { newValue in mutateBinding(profileID, binding.id) { $0.isEnabled = newValue } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)

            VStack(alignment: .leading, spacing: 2) {
                Text(binding.title(templates: appState.config.allStrokeTemplates))
                    .fontWeight(.medium)
                Text(binding.action.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                sheetMode = .edit(profileID: profileID, bindingID: binding.id)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("削除", role: .destructive) {
                removeBinding(profileID, binding.id)
            }
        }
    }

    // MARK: - Mutations

    private func currentBinding(_ profileID: UUID, _ bindingID: UUID) -> GestureBinding? {
        appState.config.profiles
            .first { $0.id == profileID }?
            .bindings.first { $0.id == bindingID }
    }

    private func mutateBinding(_ profileID: UUID, _ bindingID: UUID, _ mutate: (inout GestureBinding) -> Void) {
        guard
            let pi = appState.config.profiles.firstIndex(where: { $0.id == profileID }),
            let bi = appState.config.profiles[pi].bindings.firstIndex(where: { $0.id == bindingID })
        else { return }
        mutate(&appState.config.profiles[pi].bindings[bi])
    }

    private func removeBinding(_ profileID: UUID, _ bindingID: UUID) {
        guard let pi = appState.config.profiles.firstIndex(where: { $0.id == profileID }) else { return }
        appState.config.profiles[pi].bindings.removeAll { $0.id == bindingID }
    }

    private func addAppProfile() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.message = "プロファイルを適用するアプリを選択"
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        let profile = Profile(name: name, appBundleIDs: [bundleID], bindings: [])
        appState.config.profiles.append(profile)
        selectedProfileID = profile.id
    }

    private func removeProfile(_ id: UUID) {
        appState.config.profiles.removeAll { $0.id == id }
        selectedProfileID = appState.config.profiles.first?.id
    }
}
