import Foundation

/// Loads and persists AppConfig as JSON under Application Support, with
/// debounced autosave on every change.
@MainActor
final class ConfigStore: ObservableObject {
    @Published var config: AppConfig {
        didSet { scheduleSave() }
    }

    static var configURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MagicActions/config.json")
    }

    private var saveTask: Task<Void, Never>?

    init() {
        config = Self.load()
    }

    private static func load() -> AppConfig {
        let url = configURL
        guard let data = try? Data(contentsOf: url) else {
            return .makeDefault()
        }
        do {
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            // Keep the unreadable file for inspection, then start fresh.
            let backup = url.deletingPathExtension().appendingPathExtension("broken.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: url, to: backup)
            NSLog("MagicActions: config decode failed (%@); using defaults", error.localizedDescription)
            return .makeDefault()
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    func persist() {
        let url = Self.configURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("MagicActions: config save failed: %@", error.localizedDescription)
        }
    }
}
