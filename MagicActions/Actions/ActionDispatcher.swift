import AppKit
import CoreGraphics

/// Executes bound actions. Event synthesis requires the Accessibility permission;
/// without it CGEvent posting fails silently.
@MainActor
final class ActionDispatcher {
    func perform(_ action: Action) {
        switch action {
        case .keyboardShortcut(let combo):
            postShortcut(combo)
        case .launchApp(let bundleID, _):
            launchApp(bundleID: bundleID)
        case .openURL(let urlString):
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        case .runShell(let command):
            runShell(command)
        case .runAppleScript(let source):
            runAppleScript(source)
        case .system(let systemAction):
            performSystem(systemAction)
        }
    }

    // MARK: - Keyboard synthesis

    private func postShortcut(_ combo: KeyCombo) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let flags = CGEventFlags(rawValue: combo.modifiers)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - Apps, URLs, scripts

    private func launchApp(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            NSLog("MagicActions: app not found for bundle id %@", bundleID)
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func runShell(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        do {
            try process.run()
        } catch {
            NSLog("MagicActions: shell launch failed: %@", error.localizedDescription)
        }
    }

    private func runAppleScript(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            NSLog("MagicActions: AppleScript error: %@", error)
        }
    }

    // MARK: - System actions

    private func performSystem(_ action: SystemAction) {
        switch action {
        case .missionControl:
            let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        case .showDesktop:
            // F11 drives the default "Show Desktop" shortcut.
            postShortcut(KeyCombo(keyCode: 103, modifiers: 0, display: "F11"))
        case .middleClick:
            postMiddleClick()
        case .playPause:
            postAuxKey(16) // NX_KEYTYPE_PLAY
        case .nextTrack:
            postAuxKey(19) // NX_KEYTYPE_FAST
        case .previousTrack:
            postAuxKey(20) // NX_KEYTYPE_REWIND
        case .volumeUp:
            postAuxKey(0) // NX_KEYTYPE_SOUND_UP
        case .volumeDown:
            postAuxKey(1) // NX_KEYTYPE_SOUND_DOWN
        case .mute:
            postAuxKey(7) // NX_KEYTYPE_MUTE
        }
    }

    private func postMiddleClick() {
        let location = CGEvent(source: nil)?.location ?? .zero
        guard
            let down = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown,
                               mouseCursorPosition: location, mouseButton: .center),
            let up = CGEvent(mouseEventSource: nil, mouseType: .otherMouseUp,
                             mouseCursorPosition: location, mouseButton: .center)
        else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Media/volume keys travel as NX_SYSDEFINED aux-key events.
    private func postAuxKey(_ key: Int32) {
        func post(down: Bool) {
            let data1 = Int((Int(key) << 16) | ((down ? 0x0A : 0x0B) << 8))
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        post(down: true)
        post(down: false)
    }
}
