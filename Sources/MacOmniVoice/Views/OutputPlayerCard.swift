import SwiftUI
import AppKit

struct OutputPlayerCard: View {
    let url: URL
    @ObservedObject var player: AudioPlayerService
    @State private var showExport = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Output", systemImage: "speaker.wave.2.fill").font(.headline)
                    Spacer()
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                HStack(spacing: 12) {
                    Button {
                        player.isPlaying ? player.pause() : player.play()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .resizable().frame(width: 32, height: 32)
                    }
                    .buttonStyle(.borderless)

                    Slider(value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ), in: 0...max(0.01, player.duration))
                    .disabled(player.duration <= 0)

                    Text(timeLabel)
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(.secondary)

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("Reveal in Finder")

                    Button {
                        let panel = NSSavePanel()
                        panel.allowedContentTypes = [.wav]
                        panel.nameFieldStringValue = url.lastPathComponent
                        if panel.runModal() == .OK, let dst = panel.url {
                            try? FileManager.default.copyItem(at: url, to: dst)
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .help("Save a copy (WAV)")

                    Button {
                        showExport = true
                    } label: {
                        Image(systemName: "square.and.arrow.up.on.square")
                    }
                    .help("Export to another format (MP3 / AAC / FLAC / …)")
                }
            }
            .padding(8)
            .sheet(isPresented: $showExport) {
                ExportSheet(source: url)
            }
            .onAppear { player.load(url: url) }
            .onChange(of: url) { _, new in player.load(url: new) }
        }
    }

    private var timeLabel: String {
        func fmt(_ t: TimeInterval) -> String {
            let s = Int(t)
            return String(format: "%d:%02d", s / 60, s % 60)
        }
        return "\(fmt(player.currentTime)) / \(fmt(player.duration))"
    }
}
