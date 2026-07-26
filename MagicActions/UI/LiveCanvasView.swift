import SwiftUI

/// Real-time visualization of touches on the selected device, shaped to the
/// device's actual sensor aspect ratio. Doubles as the reception health check.
struct LiveCanvasView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedDeviceID: UInt64?

    private var selectedDevice: DeviceInfo? {
        if let id = selectedDeviceID, let device = appState.devices.first(where: { $0.id == id }) {
            return device
        }
        return appState.devices.first { $0.kind == .magicMouse } ?? appState.devices.first
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("デバイス", selection: Binding(
                    get: { selectedDevice?.id ?? 0 },
                    set: { selectedDeviceID = $0 }
                )) {
                    ForEach(appState.devices) { device in
                        Text("\(device.label)（fam \(device.familyID)）").tag(device.id)
                    }
                }
                .frame(maxWidth: 340)

                Button("再スキャン") { appState.rescanDevices() }
                Spacer()
            }

            if let device = selectedDevice {
                canvas(for: device)
                    .frame(maxHeight: 340)
                touchReadout(for: device)
            } else {
                ContentUnavailableView(
                    "デバイスが見つかりません",
                    systemImage: "computermouse",
                    description: Text("Magic Mouse の電源を入れると自動で検出されます。")
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("認識ログ").font(.headline)
                if appState.gestureLog.isEmpty {
                    Text("まだ認識イベントはありません。面をタップしてみてください。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(appState.gestureLog.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: 160)
        }
        .padding(16)
        .navigationTitle("ライブビュー")
        .onAppear { appState.setLiveViewActive(true) }
        .onDisappear { appState.setLiveViewActive(false) }
    }

    private func canvas(for device: DeviceInfo) -> some View {
        Canvas { context, size in
            let surface = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.width * 0.18)
            context.fill(surface, with: .color(.gray.opacity(0.15)))
            context.stroke(surface, with: .color(.gray.opacity(0.4)), lineWidth: 1)

            guard let frame = appState.liveFrames[device.id] else { return }
            for touch in frame.touches {
                let cx = touch.x * size.width
                let cy = (1 - touch.y) * size.height
                let radius = 10 + min(touch.size, 3) * 8
                let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
                let opacity = touch.phase == .hover ? 0.2 : 0.75
                context.fill(Path(ellipseIn: rect), with: .color(.blue.opacity(opacity)))
                context.stroke(Path(ellipseIn: rect), with: .color(.blue), lineWidth: 1)
            }
        }
        .aspectRatio(device.kind.surfaceAspect, contentMode: .fit)
    }

    private func touchReadout(for device: DeviceInfo) -> some View {
        let touches = appState.liveFrames[device.id]?.touches ?? []
        return Group {
            if touches.isEmpty {
                Text("タッチなし — 面に触れると即座に表示されます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(touches, id: \.id) { touch in
                        Text(String(
                            format: "id %d  (%.3f, %.3f)  size %.2f  pressure %.2f",
                            touch.id, touch.x, touch.y, touch.size, touch.pressure
                        ))
                        .font(.system(.caption2, design: .monospaced))
                    }
                }
            }
        }
    }
}
