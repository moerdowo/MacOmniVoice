import AppKit
import AVFoundation
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var player = SimpleSoundPlayer.shared

    /// Called when the user picks an entry to load back into the main view.
    var onLoad: ((GenerationRecord) -> Void)? = nil

    @State private var search: String = ""
    @State private var selection: GenerationRecord.ID? = nil
    @State private var confirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 480)
        .onDisappear { player.stop() }
        .confirmationDialog("Clear all history?",
                            isPresented: $confirmingClear) {
            Button("Delete all", role: .destructive) {
                app.history.clear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the history index and deletes every cached output file.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Generation history").font(.title2).bold()
                Text("\(app.history.records.count) outputs cached on disk")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            TextField("Search…", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            Button(role: .destructive) {
                confirmingClear = true
            } label: { Label("Clear", systemImage: "trash") }
                .disabled(app.history.records.isEmpty)
        }
        .padding(20)
    }

    private var filtered: [GenerationRecord] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return app.history.records }
        return app.history.records.filter {
            $0.text.lowercased().contains(q)
            || ($0.refClipName ?? "").lowercased().contains(q)
            || ($0.language ?? "").lowercased().contains(q)
            || ($0.instruct ?? "").lowercased().contains(q)
        }
    }

    private var content: some View {
        Group {
            if app.history.records.isEmpty {
                emptyState
            } else {
                List(selection: $selection) {
                    ForEach(filtered) { rec in
                        HistoryRow(
                            record: rec,
                            isPlaying: player.isPlaying(rec.fileURL),
                            onTogglePlay: { player.toggle(url: rec.fileURL) }
                        )
                        .tag(rec.id)
                        .contextMenu {
                            Button("Load into main view") {
                                onLoad?(rec); dismiss()
                            }
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([rec.fileURL])
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                if player.isPlaying(rec.fileURL) { player.stop() }
                                app.history.delete(rec)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44)).foregroundStyle(.secondary)
            Text("No generations yet").font(.headline)
            Text("Successful Generate runs land here automatically with every parameter saved.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .frame(maxWidth: 360)
        }
        .padding(40)
    }

    private var footer: some View {
        HStack {
            if let id = selection,
               let rec = app.history.records.first(where: { $0.id == id }) {
                Button { player.toggle(url: rec.fileURL) } label: {
                    Label(player.isPlaying(rec.fileURL) ? "Stop" : "Play",
                          systemImage: player.isPlaying(rec.fileURL) ? "stop.circle" : "play.circle")
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([rec.fileURL])
                } label: { Label("Reveal", systemImage: "folder") }
                Button(role: .destructive) {
                    if player.isPlaying(rec.fileURL) { player.stop() }
                    app.history.delete(rec)
                } label: { Label("Delete", systemImage: "trash") }
            }
            Spacer()
            if onLoad != nil {
                Button("Cancel") { dismiss() }
                Button {
                    if let id = selection,
                       let rec = app.history.records.first(where: { $0.id == id }) {
                        onLoad?(rec); dismiss()
                    }
                } label: {
                    Text("Load into main view").padding(.horizontal, 8)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selection == nil)
            } else {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }
}

private struct HistoryRow: View {
    let record: GenerationRecord
    let isPlaying: Bool
    let onTogglePlay: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onTogglePlay) {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(isPlaying ? Color.red : Color.accentColor)
            }
            .buttonStyle(.borderless)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.text)
                    .font(.callout).bold()
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Label(timeLabel, systemImage: "clock")
                    if let cn = record.refClipName { Label(cn, systemImage: "waveform") }
                    if let lang = record.language, !lang.isEmpty { Label(lang, systemImage: "globe") }
                    if let inst = record.instruct, !inst.isEmpty { Label(inst, systemImage: "person.fill") }
                    Label("\(record.numStep) steps", systemImage: "gauge")
                    Label(String(format: "%.1f s", record.elapsed), systemImage: "hourglass")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var timeLabel: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: record.createdAt, relativeTo: Date())
    }
}
