import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case gestures
    case liveView
    case strokes
    case permissions
    case general

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gestures: return "ジェスチャ"
        case .liveView: return "ライブビュー"
        case .strokes: return "ストローク"
        case .permissions: return "権限"
        case .general: return "一般"
        }
    }

    var icon: String {
        switch self {
        case .gestures: return "hand.tap"
        case .liveView: return "dot.radiowaves.left.and.right"
        case .strokes: return "scribble.variable"
        case .permissions: return "lock.shield"
        case .general: return "gearshape"
        }
    }
}

struct SettingsRootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: SettingsSection = .gestures

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.label, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            switch selection {
            case .gestures:
                GestureListView()
            case .liveView:
                LiveCanvasView()
            case .strokes:
                StrokeTemplatesView()
            case .permissions:
                PermissionsView()
            case .general:
                GeneralSettingsView()
            }
        }
        .navigationTitle("MagicActions")
    }
}
