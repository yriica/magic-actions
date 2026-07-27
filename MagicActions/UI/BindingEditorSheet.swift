import SwiftUI

/// Create-or-edit sheet for a gesture binding. In newCapture mode it starts by
/// listening: the user performs the gesture on the device and the detected spec
/// is filled in automatically.
struct BindingEditorSheet: View {
    enum Mode: Identifiable {
        case newCapture(profileID: UUID)
        case newStroke(profileID: UUID)
        case edit(profileID: UUID, bindingID: UUID)

        var id: String {
            switch self {
            case .newCapture(let p): return "capture-\(p)"
            case .newStroke(let p): return "stroke-\(p)"
            case .edit(let p, let b): return "edit-\(p)-\(b)"
            }
        }
    }

    let mode: Mode

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var spec: GestureSpec?
    @State private var name = ""
    @State private var action: Action = .system(.missionControl)
    @State private var isEnabled = true

    private var isCapturing: Bool {
        if case .newCapture = mode { return spec == nil }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 480)
        .onAppear(perform: setup)
        .onDisappear {
            appState.gestureCapture = nil
            appState.setRecorderArmed(false)
        }
    }

    private var header: some View {
        HStack {
            Text(headerTitle).font(.headline)
            Spacer()
        }
        .padding(14)
    }

    private var headerTitle: String {
        switch mode {
        case .newCapture: return "ジェスチャを実演して追加"
        case .newStroke: return "ストロークジェスチャを追加"
        case .edit: return "ジェスチャを編集"
        }
    }

    @ViewBuilder
    private var content: some View {
        if isCapturing {
            captureView
        } else {
            formView
        }
    }

    private var captureView: some View {
        VStack(spacing: 14) {
            Image(systemName: "hand.draw")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse)
            Text("デバイスの上でジェスチャを実演してください")
                .font(.title3)
            Text("タップ・スワイプ・TipTap・ストローク（一拍静止してから描く）を認識します。物理クリックを伴う操作は登録できません。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let last = appState.gestureLog.first {
                Text(last)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var formView: some View {
        Form {
            Section("ジェスチャ") {
                HStack {
                    Text(spec?.displayName(templates: appState.config.allStrokeTemplates) ?? "-")
                        .fontWeight(.medium)
                    Spacer()
                    if case .newCapture = mode {
                        Button("再実演") { spec = nil }
                    }
                }

                if spec?.kind == .stroke {
                    Picker("ストローク", selection: strokeTemplateBinding) {
                        ForEach(appState.config.allStrokeTemplates) { template in
                            Text(template.name).tag(Optional(template.id))
                        }
                    }
                }

                if spec?.kind == .tap || spec?.kind == .swipe {
                    Picker("ゾーン限定", selection: zoneBinding) {
                        Text("なし（面全体）").tag(Optional<Zone>.none)
                        ForEach(Zone.allCases, id: \.self) { zone in
                            Text(zone.label).tag(Optional(zone))
                        }
                    }
                }

                Picker("デバイス", selection: deviceBinding) {
                    ForEach(DeviceClass.allCases, id: \.self) { device in
                        Text(device.label).tag(device)
                    }
                }
            }

            Section("アクション") {
                ActionPickerView(action: $action)
                Button("試す") { appState.testRun(action) }
            }

            Section("その他") {
                TextField("名前（省略可）", text: $name)
                if case .edit = mode {
                    Toggle("有効", isOn: $isEnabled)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 400)
    }

    private var footer: some View {
        HStack {
            Button("キャンセル") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("保存") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(spec == nil || !specComplete)
        }
        .padding(14)
    }

    private var specComplete: Bool {
        guard let spec else { return false }
        if spec.kind == .stroke { return spec.strokeTemplateID != nil }
        return true
    }

    // MARK: - Setup / save

    private func setup() {
        switch mode {
        case .newCapture:
            appState.setRecorderArmed(true)
            appState.gestureCapture = { event in
                guard spec == nil else { return }
                spec = GestureSpec(capturedFrom: event)
            }
        case .newStroke:
            spec = GestureSpec(
                kind: .stroke,
                fingers: 1,
                device: .any,
                strokeTemplateID: appState.config.allStrokeTemplates.first?.id
            )
        case .edit(let profileID, let bindingID):
            if let binding = appState.config.profiles
                .first(where: { $0.id == profileID })?
                .bindings.first(where: { $0.id == bindingID }) {
                spec = binding.spec
                name = binding.name
                action = binding.action
                isEnabled = binding.isEnabled
            }
        }
    }

    private func save() {
        guard let spec else { return }
        switch mode {
        case .newCapture(let profileID), .newStroke(let profileID):
            guard let pi = appState.config.profiles.firstIndex(where: { $0.id == profileID }) else { break }
            let binding = GestureBinding(name: name, spec: spec, action: action, isEnabled: true)
            appState.config.profiles[pi].bindings.append(binding)
        case .edit(let profileID, let bindingID):
            guard
                let pi = appState.config.profiles.firstIndex(where: { $0.id == profileID }),
                let bi = appState.config.profiles[pi].bindings.firstIndex(where: { $0.id == bindingID })
            else { break }
            appState.config.profiles[pi].bindings[bi].spec = spec
            appState.config.profiles[pi].bindings[bi].name = name
            appState.config.profiles[pi].bindings[bi].action = action
            appState.config.profiles[pi].bindings[bi].isEnabled = isEnabled
        }
        dismiss()
    }

    // MARK: - Bindings into optional spec

    private var zoneBinding: Binding<Zone?> {
        Binding(
            get: { spec?.zone },
            set: { spec?.zone = $0 }
        )
    }

    private var deviceBinding: Binding<DeviceClass> {
        Binding(
            get: { spec?.device ?? .any },
            set: { spec?.device = $0 }
        )
    }

    private var strokeTemplateBinding: Binding<UUID?> {
        Binding(
            get: { spec?.strokeTemplateID },
            set: { spec?.strokeTemplateID = $0 }
        )
    }
}

extension GestureSpec {
    /// Build an editable spec from a live captured event (zone unconstrained by default).
    init(capturedFrom event: GestureEvent) {
        self.init(
            kind: event.kind,
            fingers: event.fingers,
            device: event.deviceKind == .magicMouse ? .mouse : .trackpad,
            zone: nil,
            direction: event.direction,
            tipTapSide: event.tipTapSide,
            strokeTemplateID: event.strokeTemplateID
        )
    }
}
