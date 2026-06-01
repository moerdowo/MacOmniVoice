import AVFoundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Full library browser. Used as a sheet so it doesn't disturb the
/// main synthesis surface.
struct ReferenceLibraryView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var soundPlayer = SimpleSoundPlayer.shared

    /// Optional pick handler — if set, a "Use" button appears that
    /// returns the selected clip's file URL and reference text.
    var onPick: ((ReferenceClip) -> Void)? = nil

    @State private var selection: ReferenceClip.ID? = nil
    @State private var editing: ReferenceClip? = nil
    @State private var showAddSheet = false
    @State private var importError: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 480)
        .onDisappear {
            // Stop any preview when the library closes.
            soundPlayer.stop()
        }
        .sheet(isPresented: $showAddSheet) {
            ReferenceClipEditor(mode: .add) { name, desc, refText, sourceURL in
                addClip(name: name, desc: desc, refText: refText, source: sourceURL)
            }
        }
        .sheet(item: $editing) { clip in
            ReferenceClipEditor(mode: .edit(clip)) { name, desc, refText, _ in
                var c = clip
                c.name = name
                c.description = desc
                c.referenceText = refText
                app.referenceLibrary.update(c)
            }
        }
        .alert("Import failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        ), actions: {
            Button("OK") { importError = nil }
        }, message: {
            Text(importError ?? "")
        })
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reference Audio Library")
                    .font(.title2).bold()
                Text("Manage saved voice samples — 3–10 s of clean speech works best.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Spacer()
            Button {
                showAddSheet = true
            } label: {
                Label("Add clip…", systemImage: "plus.circle.fill")
            }
            .keyboardShortcut("n", modifiers: [.command])
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
    }

    private var content: some View {
        Group {
            if app.referenceLibrary.clips.isEmpty {
                emptyState
            } else {
                clipList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.path.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No reference clips yet")
                .font(.headline)
            Text("Click **Add clip…** to import a WAV/MP3/FLAC sample and give it a name + description.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
        }
        .padding(40)
    }

    private var clipList: some View {
        List(selection: $selection) {
            ForEach(app.referenceLibrary.clips) { clip in
                ReferenceClipRow(
                    clip: clip,
                    isSelected: selection == clip.id,
                    isPlaying: soundPlayer.isPlaying(app.referenceLibrary.fileURL(for: clip))
                ) {
                    togglePlay(clip)
                }
                .tag(clip.id)
                .contextMenu {
                    if onPick != nil {
                        Button("Use this clip") { onPick?(clip); dismiss() }
                    }
                    Button("Edit…") { editing = clip }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([app.referenceLibrary.fileURL(for: clip)])
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        app.referenceLibrary.delete(clip)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack {
            if let id = selection,
               let clip = app.referenceLibrary.clip(withId: id) {
                let url = app.referenceLibrary.fileURL(for: clip)
                let isPlayingThis = soundPlayer.isPlaying(url)
                Button {
                    togglePlay(clip)
                } label: {
                    Label(isPlayingThis ? "Stop" : "Play",
                          systemImage: isPlayingThis ? "stop.circle" : "play.circle")
                }
                Button {
                    editing = clip
                } label: { Label("Edit", systemImage: "pencil") }
                Button(role: .destructive) {
                    if isPlayingThis { soundPlayer.stop() }
                    app.referenceLibrary.delete(clip)
                } label: { Label("Delete", systemImage: "trash") }
            }
            Spacer()
            if onPick != nil {
                Button("Cancel") { dismiss() }
                Button {
                    if let id = selection,
                       let clip = app.referenceLibrary.clip(withId: id) {
                        onPick?(clip)
                        dismiss()
                    }
                } label: {
                    Text("Use selected").padding(.horizontal, 8)
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

    // MARK: - Actions

    private func addClip(name: String, desc: String, refText: String, source: URL?) {
        guard let source else { return }
        do {
            _ = try app.referenceLibrary.importFile(
                from: source, name: name, description: desc, referenceText: refText)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func togglePlay(_ clip: ReferenceClip) {
        let url = app.referenceLibrary.fileURL(for: clip)
        soundPlayer.toggle(url: url)
    }
}

// MARK: - Row

private struct ReferenceClipRow: View {
    let clip: ReferenceClip
    let isSelected: Bool
    let isPlaying: Bool
    let onPlay: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onPlay) {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(isPlaying ? Color.red : Color.accentColor)
            }
            .buttonStyle(.borderless)
            .padding(.top, 2)
            .help(isPlaying ? "Stop" : "Play")

            VStack(alignment: .leading, spacing: 3) {
                Text(clip.name).font(.callout).bold()
                if !clip.description.isEmpty {
                    Text(clip.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 10) {
                    Label(durationLabel, systemImage: "clock")
                    Label(sizeLabel, systemImage: "internaldrive")
                    if !clip.referenceText.isEmpty {
                        Label("transcript", systemImage: "text.quote")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var durationLabel: String {
        let s = clip.durationSeconds
        if s <= 0 { return "—" }
        if s < 60 { return String(format: "%.1f s", s) }
        return String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }

    private var sizeLabel: String {
        let kb = Double(clip.byteSize) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }
}

// MARK: - Add / Edit sheet

private struct ReferenceClipEditor: View {
    enum Mode {
        case add
        case edit(ReferenceClip)
    }
    let mode: Mode
    let onSave: (_ name: String, _ desc: String, _ refText: String, _ sourceURL: URL?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var referenceText: String = ""
    @State private var sourceURL: URL? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEdit ? "Edit reference clip" : "Add reference clip")
                .font(.title2).bold()

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.callout).bold()
                TextField("e.g. Narrator male calm", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Description (optional)").font(.callout).bold()
                TextField("Anything that helps you find it later", text: $description, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Transcript (optional)").font(.callout).bold()
                TextField("Whisper auto-transcribes if blank", text: $referenceText, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
            }

            if !isEdit {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Audio file").font(.callout).bold()
                    HStack {
                        if let sourceURL {
                            VStack(alignment: .leading) {
                                Text(sourceURL.lastPathComponent).font(.callout)
                                Text(sourceURL.deletingLastPathComponent().path)
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Button(role: .destructive) { self.sourceURL = nil } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                        } else {
                            Text("WAV / MP3 / FLAC, 3–10 s recommended")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        Button {
                            pick()
                        } label: {
                            Label(sourceURL == nil ? "Choose…" : "Replace", systemImage: "folder")
                        }
                    }
                    .padding(8)
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button {
                    onSave(name, description, referenceText, sourceURL)
                    dismiss()
                } label: {
                    Text(isEdit ? "Save" : "Add to library").padding(.horizontal, 8)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 500)
        .onAppear {
            if case let .edit(c) = mode {
                name = c.name
                description = c.description
                referenceText = c.referenceText
            }
        }
    }

    private var isEdit: Bool {
        if case .edit = mode { return true }; return false
    }
    private var canSave: Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return false }
        if isEdit { return true }
        return sourceURL != nil
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio, .wav, .mp3]
        if panel.runModal() == .OK { sourceURL = panel.url }
    }
}

// MARK: - Observable single-clip preview player

@MainActor
final class SimpleSoundPlayer: NSObject, ObservableObject {
    static let shared = SimpleSoundPlayer()

    @Published private(set) var playingURL: URL? = nil
    private var player: AVAudioPlayer?

    func isPlaying(_ url: URL) -> Bool {
        playingURL?.standardizedFileURL == url.standardizedFileURL
    }

    /// Play `url`. If it's already the active clip, stop instead — so a
    /// single button can serve as Play/Stop.
    func toggle(url: URL) {
        if isPlaying(url) {
            stop()
        } else {
            play(url: url)
        }
    }

    func play(url: URL) {
        player?.stop()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            self.player = p
            self.playingURL = url
        } catch {
            self.player = nil
            self.playingURL = nil
            NSSound.beep()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingURL = nil
    }
}

extension SimpleSoundPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            self.playingURL = nil
        }
    }
}
