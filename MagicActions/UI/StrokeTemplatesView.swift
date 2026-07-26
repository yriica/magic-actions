import SwiftUI

/// Built-in and user-recorded stroke templates. New templates are recorded by
/// drawing directly on the device surface.
struct StrokeTemplatesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showRecorder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    showRecorder = true
                } label: {
                    Label("ストロークを記録…", systemImage: "plus.circle.fill")
                }
                Spacer()
                Text("ストロークは面の先端側で一拍置いてから描くと発動します")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            List {
                Section("組み込み") {
                    ForEach(BuiltinStroke.allCases, id: \.self) { builtin in
                        templateRow(builtin.template)
                    }
                }
                Section("カスタム") {
                    if appState.config.strokeTemplates.isEmpty {
                        Text("カスタムストロークはまだありません")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(appState.config.strokeTemplates) { template in
                        templateRow(template)
                            .contextMenu {
                                Button("削除", role: .destructive) {
                                    appState.config.strokeTemplates.removeAll { $0.id == template.id }
                                }
                            }
                    }
                }
            }
            .listStyle(.inset)
        }
        .navigationTitle("ストローク")
        .sheet(isPresented: $showRecorder) {
            StrokeRecorderSheet()
                .environmentObject(appState)
        }
    }

    private func templateRow(_ template: StrokeTemplate) -> some View {
        HStack(spacing: 12) {
            StrokePreview(points: template.points)
                .frame(width: 40, height: 40)
            Text(template.name)
            Spacer()
            if template.isBuiltin {
                Text("組み込み")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Draws a stroke path fitted into the view (touch coords are y-up; flip for screen).
struct StrokePreview: View {
    let points: [CGPoint]

    var body: some View {
        Canvas { context, size in
            guard points.count >= 2 else { return }
            var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
            var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
            for p in points {
                minX = min(minX, p.x); minY = min(minY, p.y)
                maxX = max(maxX, p.x); maxY = max(maxY, p.y)
            }
            let w = max(maxX - minX, 0.0001)
            let h = max(maxY - minY, 0.0001)
            let scale = min(size.width / w, size.height / h) * 0.8
            let offsetX = (size.width - w * scale) / 2
            let offsetY = (size.height - h * scale) / 2

            var path = Path()
            for (i, p) in points.enumerated() {
                let x = (p.x - minX) * scale + offsetX
                let y = (maxY - p.y) * scale + offsetY
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            // Start marker
            if let first = points.first {
                let x = (first.x - minX) * scale + offsetX
                let y = (maxY - first.y) * scale + offsetY
                context.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)), with: .color(.accentColor))
            }
        }
    }
}

/// Records a raw path drawn anywhere on any device surface.
struct StrokeRecorderSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var capturedPoints: [CGPoint] = []
    @State private var name = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("ストロークを記録").font(.headline)

            if capturedPoints.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "scribble.variable")
                        .font(.system(size: 40))
                        .foregroundStyle(.tint)
                        .symbolEffect(.pulse)
                    Text("デバイスの面に1本指で図形を描いてください")
                    Text("記録モード中はどの位置からでも描けます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 180)
            } else {
                VStack(spacing: 10) {
                    StrokePreview(points: capturedPoints)
                        .frame(width: 140, height: 140)
                        .background(.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    Button("描き直す") { capturedPoints = [] }
                }
            }

            TextField("ストローク名", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)

            HStack {
                Button("キャンセル") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    let template = StrokeTemplate(
                        name: name.isEmpty ? "ストローク \(appState.config.strokeTemplates.count + 1)" : name,
                        points: capturedPoints
                    )
                    appState.config.strokeTemplates.append(template)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(capturedPoints.count < 4)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            appState.strokeCapture = { points, _ in
                capturedPoints = points
            }
        }
        .onDisappear {
            appState.strokeCapture = nil
        }
    }
}
