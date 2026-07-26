import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService.
@MainActor
final class LoginItemManager: ObservableObject {
    @Published var isEnabled: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            guard oldValue != isEnabled else { return }
            apply()
        }
    }

    private func apply() {
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("MagicActions: login item change failed: %@", error.localizedDescription)
            isEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}
