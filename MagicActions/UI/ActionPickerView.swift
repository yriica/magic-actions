import SwiftUI
import UniformTypeIdentifiers

/// Editor for an Action value: type picker + type-specific fields.
struct ActionPickerView: View {
    @Binding var action: Action

    private enum ActionType: String, CaseIterable, Identifiable {
        case shortcut, system, app, url, shell, appleScript

        var id: String { rawValue }

        var label: String {
            switch self {
            case .shortcut: return "キーボードショートカット"
            case .system: return "システム操作"
            case .app: return "アプリを開く"
            case .url: return "URLを開く"
            case .shell: return "シェルコマンド"
            case .appleScript: return "AppleScript"
            }
        }
    }

    private var currentType: ActionType {
        switch action {
        case .keyboardShortcut: return .shortcut
        case .system: return .system
        case .launchApp: return .app
        case .openURL: return .url
        case .runShell: return .shell
        case .runAppleScript: return .appleScript
        }
    }

    var body: some View {
        Picker("種類", selection: typeBinding) {
            ForEach(ActionType.allCases) { type in
                Text(type.label).tag(type)
            }
        }

        switch currentType {
        case .shortcut:
            LabeledContent("ショートカット") {
                ShortcutRecorderField(combo: shortcutBinding)
            }
        case .system:
            Picker("操作", selection: systemBinding) {
                ForEach(SystemAction.allCases, id: \.self) { sys in
                    Text(sys.label).tag(sys)
                }
            }
        case .app:
            LabeledContent("アプリ") {
                HStack {
                    Text(appName.isEmpty ? "未選択" : appName)
                        .foregroundStyle(appName.isEmpty ? .secondary : .primary)
                    Button("選択…", action: chooseApp)
                }
            }
        case .url:
            TextField("URL", text: urlBinding, prompt: Text("https://example.com または raycast:// など"))
        case .shell:
            VStack(alignment: .leading, spacing: 4) {
                Text("シェルコマンド（/bin/zsh -c で実行）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: shellBinding)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 64)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
            }
        case .appleScript:
            VStack(alignment: .leading, spacing: 4) {
                Text("AppleScript ソース")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: scriptBinding)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 64)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
            }
        }
    }

    // MARK: - Case bindings

    private var typeBinding: Binding<ActionType> {
        Binding(
            get: { currentType },
            set: { newType in
                guard newType != currentType else { return }
                switch newType {
                case .shortcut: action = .keyboardShortcut(KeyCombo(keyCode: 0, modifiers: 0, display: ""))
                case .system: action = .system(.missionControl)
                case .app: action = .launchApp(bundleID: "", name: "")
                case .url: action = .openURL(url: "")
                case .shell: action = .runShell(command: "")
                case .appleScript: action = .runAppleScript(source: "")
                }
            }
        )
    }

    private var shortcutBinding: Binding<KeyCombo?> {
        Binding(
            get: {
                if case .keyboardShortcut(let combo) = action, !combo.display.isEmpty { return combo }
                return nil
            },
            set: { newValue in
                if let newValue { action = .keyboardShortcut(newValue) }
            }
        )
    }

    private var systemBinding: Binding<SystemAction> {
        Binding(
            get: {
                if case .system(let sys) = action { return sys }
                return .missionControl
            },
            set: { action = .system($0) }
        )
    }

    private var appName: String {
        if case .launchApp(_, let name) = action { return name }
        return ""
    }

    private var urlBinding: Binding<String> {
        Binding(
            get: {
                if case .openURL(let url) = action { return url }
                return ""
            },
            set: { action = .openURL(url: $0) }
        )
    }

    private var shellBinding: Binding<String> {
        Binding(
            get: {
                if case .runShell(let cmd) = action { return cmd }
                return ""
            },
            set: { action = .runShell(command: $0) }
        )
    }

    private var scriptBinding: Binding<String> {
        Binding(
            get: {
                if case .runAppleScript(let src) = action { return src }
                return ""
            },
            set: { action = .runAppleScript(source: $0) }
        )
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        action = .launchApp(bundleID: bundleID, name: name)
    }
}

/// Click-to-record keyboard shortcut field (captures the next keyDown; Esc cancels).
struct ShortcutRecorderField: View {
    @Binding var combo: KeyCombo?
    @State private var capturing = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            capturing ? stopCapture() : startCapture()
        } label: {
            Text(capturing ? "キーを入力…" : (combo?.display ?? "クリックして記録"))
                .frame(minWidth: 130)
        }
        .onDisappear(perform: stopCapture)
    }

    private func startCapture() {
        capturing = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isPlainEscape = event.keyCode == 53 && event.modifierFlags
                .intersection([.command, .option, .control, .shift]).isEmpty
            if !isPlainEscape {
                combo = KeyCombo(capturing: event)
            }
            stopCapture()
            return nil
        }
    }

    private func stopCapture() {
        capturing = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}

extension KeyCombo {
    init(capturing event: NSEvent) {
        var flags: CGEventFlags = []
        var symbols = ""
        let m = event.modifierFlags
        if m.contains(.control) { flags.insert(.maskControl); symbols += "⌃" }
        if m.contains(.option) { flags.insert(.maskAlternate); symbols += "⌥" }
        if m.contains(.shift) { flags.insert(.maskShift); symbols += "⇧" }
        if m.contains(.command) { flags.insert(.maskCommand); symbols += "⌘" }
        if m.contains(.function), KeyCombo.functionKeyRelevant(event.keyCode) {
            flags.insert(.maskSecondaryFn)
        }
        self.init(
            keyCode: event.keyCode,
            modifiers: flags.rawValue,
            display: symbols + KeyCombo.keyName(for: event)
        )
    }

    private static func functionKeyRelevant(_ keyCode: UInt16) -> Bool {
        // Arrow/function keys carry .function implicitly; only keep fn for other keys.
        !(123...126).contains(keyCode) && !specialNames.keys.contains(keyCode)
    }

    private static let specialNames: [UInt16: String] = [
        36: "Return", 48: "Tab", 49: "Space", 51: "⌫", 53: "Esc", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Home", 119: "End", 116: "PgUp", 121: "PgDn",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    static func keyName(for event: NSEvent) -> String {
        if let special = specialNames[event.keyCode] {
            return special
        }
        return event.charactersIgnoringModifiers?.uppercased() ?? "key\(event.keyCode)"
    }
}
