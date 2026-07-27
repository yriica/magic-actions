import AppKit
import SwiftUI

/// Small transient overlay that names the recognized gesture (also useful for
/// self-diagnosing accidental triggers).
///
/// Implementation note: the panel has a fixed size and the hosting view has
/// sizingOptions = []. Letting NSHostingView drive the window's size
/// constraints from inside a borderless panel throws
/// NSInternalInconsistencyException during the constraint pass on macOS 26
/// (crash in updateWindowContentSizeExtremaIfNecessary), so all automatic
/// sizing is disabled and the content simply centers itself.
@MainActor
final class HUDController {
    private final class HUDModel: ObservableObject {
        @Published var text = ""
    }

    private static let panelSize = NSSize(width: 460, height: 80)

    private let model = HUDModel()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ text: String) {
        let panel = ensurePanel()
        model.text = text
        position(panel)
        hideTask?.cancel()
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideTask = Task { [weak panel] in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard !Task.isCancelled, let panel else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
            }
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]

        let hosting = NSHostingView(rootView: HUDLabel(model: model))
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: Self.panelSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let origin = NSPoint(
            x: frame.midX - Self.panelSize.width / 2,
            y: frame.minY + frame.height * 0.16
        )
        panel.setFrameOrigin(origin)
    }

    private struct HUDLabel: View {
        @ObservedObject fileprivate var model: HUDModel

        var body: some View {
            Text(model.text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.72), in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
