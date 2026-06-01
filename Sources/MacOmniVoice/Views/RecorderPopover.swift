import SwiftUI

/// Compact recording UI shown in a popover anchored to the Record button.
struct RecorderPopover: View {
    @ObservedObject var recorder: AudioRecorderService
    let onFinish: (URL) -> Void
    let onCancel: () -> Void

    @State private var error: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Circle()
                    .fill(recorder.isRecording ? Color.red : Color.gray)
                    .frame(width: 12, height: 12)
                    .opacity(recorder.isRecording ? (0.4 + Double(recorder.level) * 0.6) : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: recorder.level)
                Text(recorder.isRecording ? "Recording…" : "Ready")
                    .font(.callout).bold()
                Spacer()
                Text(timeString(recorder.elapsed))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            // Level meter
            LevelMeter(level: recorder.level)
                .frame(height: 10)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Tip: 3–10 seconds of clear speech is ideal. Speak in the same language you want OmniVoice to clone.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if recorder.isRecording {
                    Button(role: .destructive) {
                        recorder.cancel()
                        onCancel()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                    Spacer()
                    Button {
                        if let url = recorder.stop() {
                            onFinish(url)
                        }
                    } label: {
                        Label("Use recording", systemImage: "checkmark.circle.fill")
                            .padding(.horizontal, 8)
                    }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                } else {
                    Spacer()
                    Button {
                        Task { await start() }
                    } label: {
                        Label("Start recording", systemImage: "mic.fill")
                            .padding(.horizontal, 12)
                    }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            if !recorder.isRecording {
                Task { await start() }
            }
        }
    }

    private func start() async {
        error = nil
        do {
            _ = try await recorder.start()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let total = Int(t)
        let ms = Int((t - floor(t)) * 10)
        return String(format: "%d:%02d.%d", total / 60, total % 60, ms)
    }
}

private struct LevelMeter: View {
    let level: Float
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(
                        colors: [.green, .green, .yellow, .red],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * CGFloat(min(1, max(0, level))))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
    }
}
