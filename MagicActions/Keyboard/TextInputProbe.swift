import AppKit
import ApplicationServices
import Carbon

/// Reads the selected keyboard input source via TIS.
enum InputSourceInspector {
    /// Only input *modes* can hold marked text; a plain layout (ABC) never does.
    /// The Japanese IM's alphanumeric sub-mode reports "com.apple.inputmethod.Roman"
    /// and types directly, so it does not compose either.
    static func isComposingMode(type: String, modeID: String?) -> Bool {
        type == (kTISTypeKeyboardInputMode as String) && modeID != "com.apple.inputmethod.Roman"
    }

    static func currentSourceComposes() -> Bool {
        guard
            let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
            let typePointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceType)
        else { return false }
        let type = Unmanaged<CFString>.fromOpaque(typePointer).takeUnretainedValue() as String
        let modeID = TISGetInputSourceProperty(source, kTISPropertyInputModeID).map {
            Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String
        }
        return isComposingMode(type: type, modeID: modeID)
    }
}

/// Accessibility queries made from inside the keyboard tap. Each call is a
/// synchronous IPC to the focused app while the key event is held, so every
/// element gets a short messaging timeout.
enum FocusProbe {
    enum MarkedText: Equatable {
        case marked
        case clear
        /// The element does not implement the attribute (Chromium/Electron,
        /// most custom text engines) or did not answer in time.
        case unsupported
    }

    private static let timeout: Float = 0.05
    private static let markedRangeAttribute = "AXTextInputMarkedRange"

    /// Bundle ID of the app that owns keyboard focus. Differs from the
    /// NSWorkspace frontmost app while a non-activating panel (launcher,
    /// Spotlight-like UI) has focus.
    static func focusedAppBundleID() -> String? {
        guard let app = copyElement(of: systemWide(), attribute: "AXFocusedApplication") else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(app, &pid) == .success, pid > 0 else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    static func markedText() -> MarkedText {
        guard let element = copyElement(of: systemWide(), attribute: "AXFocusedUIElement") else {
            return .unsupported
        }
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, markedRangeAttribute as CFString, &value) == .success,
           let value, CFGetTypeID(value) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(value as! AXValue, .cfRange, &range), range.length > 0 {
                return .marked
            }
        }
        // An empty answer only means "nothing marked" when the element actually
        // advertises the attribute; otherwise it is merely unimplemented.
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success,
              let list = names as? [String] else { return .unsupported }
        return list.contains(markedRangeAttribute) ? .clear : .unsupported
    }

    private static func systemWide() -> AXUIElement {
        let element = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }

    private static func copyElement(of parent: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }
}
