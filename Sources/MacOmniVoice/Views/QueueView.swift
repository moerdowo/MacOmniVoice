import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Batch-synthesize many lines of text. Lines are pasted, one per line,
/// or imported from a .txt file. Each line uses the current reference
/// audio + advanced parameters from the main view.
struct QueueView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var queue = SynthesisQueue()
    @ObservedObject private var player = SimpleSoundPlayer.shared

    /// Caller-provided builder so the queue uses MainView's current
    /// reference, language, instruct, and advanced params.
    let requestBuilder: (_ text: String) -> SynthesisRequest

    @State private var rawInput: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if queue.items.isEmpty {
                inputForm
            } else {
                runList
            }
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 480)
        .onDisappear {
            player.stop()
            queue.cancel()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Batch queue").font(.title2).bold()
                Text("One line of text per item. Re-uses your current reference audio + advanced settings.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var inputForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Paste one line per item").font(.callout).bold()
                Spacer()
                Button {
                    pickFile()
                } label: { Label("Import .txt…", systemImage: "doc.text") }
            }
            TextEditor(text: $rawInput)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.background.secondary)
                .frame(minHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
            Text("\(lineCount) non-empty line\(lineCount == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(20)
    }

    private var lineCount: Int {
        rawInput.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    private var runList: some View {
        List {
            ForEach(queue.items) { item in
                QueueRow(
                    item: item,
                    isPlaying: item.outputURL.map(player.isPlaying) ?? false,
                    onPlay: {
                        if let url = item.outputURL { player.toggle(url: url) }
                    },
                    onReveal: {
                        if let url = item.outputURL {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                )
            }
        }
        .listStyle(.inset)
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            if queue.items.isEmpty {
                Text("\(lineCount) items ready to queue")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Close") { dismiss() }
                Button {
                    queue.setItems(rawInput.components(separatedBy: .newlines))
                    Task { await runQueue() }
                } label: {
                    Text("Start queue").padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(lineCount == 0)
            } else {
                Text(progressLabel).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if queue.isRunning {
                    Button("Stop after current") { queue.cancel() }
                } else {
                    Button("Reset") { queue.clear() }
                }
                Button("Close") { dismiss() }
            }
        }
        .padding(16)
    }

    private var progressLabel: String {
        let done = queue.items.filter { $0.status == .done }.count
        let total = queue.items.count
        return queue.isRunning
            ? "Running… \(done) / \(total) done"
            : "\(done) / \(total) done"
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url,
           let s = try? String(contentsOf: url, encoding: .utf8) {
            rawInput = s
        }
    }

    private func runQueue() async {
        await queue.run(
            makeRequest: { text in
                var req = requestBuilder(text)
                req.text = text
                return req
            },
            synthesize: { req in
                try await app.synthesisEngine.synthesizeChunk(
                    req,
                    modelId: app.settings.modelId,
                    deviceOverride: app.settings.deviceOverride.isEmpty ? nil : app.settings.deviceOverride
                )
            }
        )
    }
}

private struct QueueRow: View {
    let item: SynthesisQueue.Item
    let isPlaying: Bool
    let onPlay: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text).font(.callout).lineLimit(2)
                if let err = item.error {
                    Text(err).font(.caption).foregroundStyle(.red).lineLimit(1)
                }
            }
            Spacer()
            if item.status == .done, item.outputURL != nil {
                Button(action: onPlay) {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .imageScale(.large)
                        .foregroundStyle(isPlaying ? Color.red : Color.accentColor)
                }
                .buttonStyle(.borderless)
                Button(action: onReveal) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .pending:   Image(systemName: "circle").foregroundStyle(.secondary)
        case .running:   ProgressView().controlSize(.small)
        case .done:      Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .cancelled: Image(systemName: "xmark.circle").foregroundStyle(.gray)
        }
    }
}
