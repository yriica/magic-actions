import SwiftUI

@main
struct MagicActionsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarIconBinding) {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: "computermouse.fill")
        }

        Window("MagicActions", id: "settings") {
            SettingsRootView()
                .environmentObject(appState)
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentMinSize)
    }

    private var menuBarIconBinding: Binding<Bool> {
        Binding(
            get: { appState.config.settings.showMenuBarIcon },
            set: { appState.config.settings.showMenuBarIcon = $0 }
        )
    }
}
