import SwiftUI

@main
struct MagicActionsApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
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
}
