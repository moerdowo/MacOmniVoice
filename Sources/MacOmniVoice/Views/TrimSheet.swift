import AVFoundation
import SwiftUI

/// Two-handle range slider for cropping a clip to its sweet-spot.
struct TrimSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var player = SimpleSoundPlayer.shared

    let clip: ReferenceClip

    @State private var start: Double = 0
    @State private var end: Double = 0
    @State private var duration: Double = 0
    @State private var errorMessage: String? = nil
    @State private var isSaving = false

    private var fileURL: URL { app.referenceLibrary.fileURL(for: clip) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Trim “\(clip.name)”").font(.title2).bold()

            VStack(alignment: .leading, spacing: 6) {
                Text("Range").font(.callout).bold()
                if duration > 0 {
                    RangeSlider(start: $start, end: $end, total: duration)
                        .frame(height: 30)
                    HStack {
                        Text(time(start)).monospacedDigit()
                        Spacer()
                        Text(String(format: "%.2f s selected", end - start))
                            .foregroundStyle(.tint)
                            .monospacedDigit()
                        Spacer()
                        Text(time(end)).monospacedDigit()
                    }
                    .font(.caption)
                } else {
                    Text("Loading…").font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack {
                Button {
                    player.toggle(url: fileURL)
                } label: {
                    Label(player.isPlaying(fileURL) ? "Stop" : "Preview whole clip",
                          systemImage: player.isPlaying(fileURL) ? "stop.circle" : "play.circle")
                }
                Spacer()
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.caption)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().controlSize(.small).padding(.horizontal, 14)
                    } else {
                        Text("Save trim").padding(.horizontal, 8)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || end - start < 0.2)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            let asset = AVURLAsset(url: fileURL)
            let s = CMTimeGetSeconds(asset.duration)
            duration = s.isFinite ? s : clip.durationSeconds
            start = 0
            end = duration
        }
        .onDisappear { player.stop() }
    }

    private func time(_ t: Double) -> String {
        let total = max(0, t)
        let s = Int(total)
        let ms = Int((total - floor(total)) * 100)
        return String(format: "%d:%02d.%02d", s / 60, s % 60, ms)
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("trim-\(UUID().uuidString).wav")
        do {
            try AudioTrim.trim(input: fileURL, to: tmp, startSec: start, endSec: end)
            try app.referenceLibrary.replaceFile(of: clip, with: tmp)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Two-handle range slider in [0…total]. Visual + drag handles are
/// drawn manually so we get the precision a single Slider can't.
private struct RangeSlider: View {
    @Binding var start: Double
    @Binding var end: Double
    let total: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let sx = total > 0 ? CGFloat(start / total) * w : 0
            let ex = total > 0 ? CGFloat(end / total) * w : 0
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: max(0, ex - sx), height: 6)
                    .offset(x: sx)
                handle(at: sx)
                    .gesture(DragGesture().onChanged { v in
                        let t = max(0, min(end, Double(v.location.x / w) * total))
                        start = t
                    })
                handle(at: ex)
                    .gesture(DragGesture().onChanged { v in
                        let t = max(start, min(total, Double(v.location.x / w) * total))
                        end = t
                    })
            }
            .frame(height: 30)
        }
    }

    private func handle(at x: CGFloat) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 18, height: 18)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .shadow(radius: 1)
            .offset(x: x - 9)
    }
}
