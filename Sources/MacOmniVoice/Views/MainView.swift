import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct MainView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var player = AudioPlayerService()

    @State private var text: String = "Hello, this is a test of zero-shot voice cloning."
    @State private var refText: String = ""
    @State private var refAudioURL: URL? = nil
    @State private var refClipName: String = ""        // empty unless from the library
    @State private var showAdvanced: Bool = false
    @State private var showConsole: Bool = false
    @State private var showRecorder: Bool = false
    @State private var showLibrary: Bool = false
    @State private var showSaveToLibrary: Bool = false
    @State private var showDiagnostics: Bool = false
    @State private var showHistory: Bool = false
    @State private var showQueue: Bool = false
    @State private var longForm: Bool = false
    @State private var longFormProgress: (done: Int, total: Int)? = nil
    @State private var showSymbolPicker: Bool = false
    @State private var showVoiceDesign: Bool = false
    @State private var detectedLanguage: (code: String, name: String)? = nil
    @State private var errorMessage: String? = nil
    @StateObject private var recorder = AudioRecorderService()

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    titleRow
                    modelStatusCard
                    textInputCard
                    if showVoiceDesign {
                        VoiceDesignPanel()
                    }
                    referenceAudioCard
                    if showAdvanced {
                        AdvancedSettingsView()
                    }
                    generateRow
                    if let url = player.currentURL ?? app.synthesisEngine.lastOutput {
                        OutputPlayerCard(url: url, player: player)
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .padding(.top, 4)
                    }
                }
                .padding(28)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity)

            if showConsole {
                Divider()
                ConsolePanel()
                    .frame(width: 320)
                    .transition(.move(edge: .trailing))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    showVoiceDesign.toggle()
                } label: {
                    Label(showVoiceDesign ? "Hide Voice Design" : "Voice Design",
                          systemImage: "person.crop.circle.badge.questionmark")
                }
                Button {
                    showAdvanced.toggle()
                } label: {
                    Label(showAdvanced ? "Hide Advanced" : "Advanced",
                          systemImage: "slider.horizontal.3")
                }
                Button {
                    showLibrary = true
                } label: {
                    Label("Library", systemImage: "books.vertical.fill")
                }
                .help("Reference audio library")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await app.modelManager.checkForUpdate(force: true) }
                } label: {
                    Label("Check for Update", systemImage: "arrow.triangle.2.circlepath")
                }
                Button {
                    showHistory = true
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                Button {
                    showQueue = true
                } label: {
                    Label("Queue", systemImage: "list.number")
                }
                Button {
                    showDiagnostics = true
                } label: {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
                Button {
                    withAnimation { showConsole.toggle() }
                } label: {
                    Label(showConsole ? "Hide Console" : "Console",
                          systemImage: "terminal")
                }
            }
        }
        .environmentObject(player)
        .sheet(isPresented: $showLibrary) {
            ReferenceLibraryView(onPick: { clip in
                refAudioURL = app.referenceLibrary.fileURL(for: clip)
                refClipName = clip.name
                if !clip.referenceText.isEmpty {
                    refText = clip.referenceText
                }
            })
            .environmentObject(app)
        }
        .sheet(isPresented: $showSaveToLibrary) {
            SaveToLibrarySheet(
                source: refAudioURL,
                initialRefText: refText,
                onSaved: { clip in
                    // After saving, switch the current ref to the library copy
                    refAudioURL = app.referenceLibrary.fileURL(for: clip)
                    refClipName = clip.name
                }
            )
            .environmentObject(app)
        }
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsView().environmentObject(app)
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(onLoad: { rec in
                loadFromHistory(rec)
            })
            .environmentObject(app)
        }
        .sheet(isPresented: $showQueue) {
            QueueView(requestBuilder: { _ in currentRequest() })
                .environmentObject(app)
        }
        .onChange(of: app.pendingProjectDocument) { _, doc in
            if let doc { applyProjectDocument(doc); app.pendingProjectDocument = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveProject)) { _ in
            saveProject()
        }
        .onAppear {
            app.synthesisEngine.attach(modelManager: app.modelManager)
            app.synthesisEngine.attach(history: app.history)
            app.synthesisEngine.diagnostics = app.diagnostics
            do {
                try app.synthesisEngine.startRunnerAndPump()
            } catch {
                errorMessage = error.localizedDescription
            }
            Task {
                await app.modelManager.refreshLocalStatus(runtime: app.pythonRuntime)
                if app.settings.autoCheckUpdates {
                    await app.modelManager.checkForUpdate()
                }
            }
        }
    }

    // MARK: - Subviews

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("OmniVoice")
                    .font(.largeTitle).bold()
                Text("Zero-shot voice cloning across 600+ languages")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Spacer()
            EngineStateBadge(state: app.synthesisEngine.state)
        }
    }

    private var modelStatusCard: some View {
        ModelStatusBar()
    }

    private var textInputCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Text to synthesize", systemImage: "text.alignleft").font(.headline)
                    Spacer()
                    Button {
                        showSymbolPicker = true
                    } label: {
                        Label("Symbol", systemImage: "speaker.wave.2.bubble")
                    }
                    .controlSize(.small)
                    .help("Insert non-verbal symbols like [laughter] or [sigh]")
                    .popover(isPresented: $showSymbolPicker, arrowEdge: .top) {
                        SymbolPickerPopover(text: $text)
                    }
                }
                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))

                if let det = detectedLanguage,
                   det.code != app.settings.language,
                   !text.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "globe").foregroundStyle(.tint)
                        Text("Detected \(det.name) (\(det.code)).")
                            .font(.caption)
                        Button("Use \(det.code)") {
                            app.settings.language = det.code
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        Button("Dismiss") {
                            detectedLanguage = nil
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderless)
                    }
                    .padding(8)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }

                HStack {
                    Text("\(text.count) chars")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                    Spacer()
                    Button("Paste example") {
                        text = "Hello, this is a test of zero-shot voice cloning."
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .padding(8)
            .onChange(of: text) { _, newValue in
                detectedLanguage = LanguageDetector.detect(newValue)
            }
        }
    }

    private var referenceAudioCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Reference audio (voice to clone)", systemImage: "waveform")
                        .font(.headline)
                    Spacer()
                    if !app.referenceLibrary.clips.isEmpty {
                        Text("\(app.referenceLibrary.clips.count) in library")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    if let refAudioURL {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(refClipName.isEmpty ? refAudioURL.lastPathComponent : refClipName)
                                .font(.callout).bold()
                                .lineLimit(1).truncationMode(.middle)
                            Text(refAudioURL.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if isFromLibrary {
                            Label("from library", systemImage: "books.vertical")
                                .font(.caption2)
                                .foregroundStyle(.tint)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.tint.opacity(0.12), in: Capsule())
                        } else {
                            Button {
                                showSaveToLibrary = true
                            } label: {
                                Label("Save to library", systemImage: "tray.and.arrow.down")
                            }
                            .controlSize(.small)
                            .help("Add this clip to the reference library")
                        }
                        Button(role: .destructive) {
                            self.refAudioURL = nil
                            self.refClipName = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").imageScale(.large)
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Text("Drop or pick a 3–10 s WAV/MP3/FLAC clip — or open the library")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    Button {
                        showLibrary = true
                    } label: {
                        Label("Library", systemImage: "books.vertical.fill")
                    }
                    .help("Open the reference audio library")
                    Button {
                        showRecorder = true
                    } label: {
                        Label(recorder.isRecording ? "Recording…" : "Record", systemImage: "mic.fill")
                            .foregroundStyle(recorder.isRecording ? Color.red : Color.primary)
                    }
                    .popover(isPresented: $showRecorder, arrowEdge: .top) {
                        RecorderPopover(
                            recorder: recorder,
                            onFinish: { url in
                                refAudioURL = url
                                refClipName = ""
                                showRecorder = false
                            },
                            onCancel: { showRecorder = false }
                        )
                    }
                    Button {
                        pickReferenceAudio()
                    } label: {
                        Label(refAudioURL == nil ? "Choose…" : "Replace", systemImage: "folder")
                    }
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Reference text (optional)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextField("Whisper auto-transcribes if left blank", text: $refText, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(8)
            .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                guard let item = providers.first else { return false }
                _ = item.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async { self.refAudioURL = url }
                    }
                }
                return true
            }
        }
    }

    private var generateRow: some View {
        let preflight = app.preflightForGenerate(text: text)
        let suggestLongForm = text.count > 400
        return VStack(alignment: .trailing, spacing: 6) {
            HStack {
                if case let .blocked(reason, hint) = preflight {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(reason).font(.callout).bold()
                            Text(hint).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Toggle(isOn: $longForm) {
                    Label("Long form", systemImage: "text.justify")
                        .foregroundStyle(suggestLongForm ? Color.orange : Color.primary)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Split long text by sentence, synth each chunk, stitch them into one WAV.")

                Button {
                    Task { await reroll() }
                } label: { Label("Re-roll", systemImage: "dice") }
                .controlSize(.large)
                .disabled(preflight != .ready)
                .help("Same text + ref, new class-temperature so you get a different take.")

                Button {
                    Task { await generate() }
                } label: {
                    HStack(spacing: 8) {
                        if app.synthesisEngine.state == .synthesizing ||
                            app.synthesisEngine.state == .loadingModel ||
                            app.synthesisEngine.state == .downloadingModel {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(generateButtonLabel)
                            .bold()
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 6)
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(preflight != .ready)
            }
            if let lp = longFormProgress, lp.total > 0 {
                ProgressView(value: Double(lp.done), total: Double(lp.total))
                    .progressViewStyle(.linear)
                Text("Long-form chunk \(lp.done) / \(lp.total)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var isWorking: Bool {
        switch app.synthesisEngine.state {
        case .synthesizing, .loadingModel, .downloadingModel, .startingRunner:
            return true
        default:
            return false
        }
    }

    private var generateButtonLabel: String {
        switch app.synthesisEngine.state {
        case .loadingModel: return "Loading model…"
        case .downloadingModel: return "Downloading model…"
        case .synthesizing:
            let s = app.synthesisEngine.synthesisElapsed
            return s > 0 ? String(format: "Generating… %.1fs", s) : "Generating…"
        default: return "Generate"
        }
    }

    private func pickReferenceAudio() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio, .wav, .mp3]
        if panel.runModal() == .OK {
            refAudioURL = panel.url
            refClipName = ""
        }
    }

    private var isFromLibrary: Bool {
        guard let url = refAudioURL else { return false }
        return url.path.hasPrefix(ReferenceLibrary.clipsDir.path)
    }

    private func currentRequest() -> SynthesisRequest {
        let s = app.settings
        return SynthesisRequest(
            text: text,
            refAudioPath: refAudioURL?.path,
            refText: refText.isEmpty ? nil : refText,
            language: s.language.isEmpty ? nil : s.language,
            instruct: s.instruct.isEmpty ? nil : s.instruct,
            speed: s.speed,
            duration: s.duration > 0 ? s.duration : nil,
            numStep: s.numStep,
            guidanceScale: s.guidanceScale,
            denoise: s.denoise,
            postprocessOutput: s.postprocessOutput,
            preprocessPrompt: s.preprocessPrompt,
            tShift: s.tShift,
            layerPenaltyFactor: s.layerPenaltyFactor,
            positionTemperature: s.positionTemperature,
            classTemperature: s.classTemperature
        )
    }

    private func stampRecordMeta() {
        var clipID: UUID? = nil
        if isFromLibrary, let url = refAudioURL {
            clipID = app.referenceLibrary.clips.first(where: {
                app.referenceLibrary.fileURL(for: $0).standardizedFileURL == url.standardizedFileURL
            })?.id
        }
        app.synthesisEngine.nextRecordMeta = .init(
            refClipID: clipID,
            refClipName: refClipName.isEmpty ? nil : refClipName,
            refAudioOriginalPath: refAudioURL?.path,
            refText: refText.isEmpty ? nil : refText
        )
    }

    private func generate() async {
        errorMessage = nil
        let req = currentRequest()
        stampRecordMeta()
        let s = app.settings
        let device = s.deviceOverride.isEmpty ? nil : s.deviceOverride
        do {
            let out: URL
            if longForm {
                longFormProgress = (0, 0)
                out = try await app.synthesisEngine.synthesizeLongForm(
                    req, modelId: s.modelId, deviceOverride: device,
                    progress: { done, total in
                        longFormProgress = (done, total)
                    }
                )
                longFormProgress = nil
            } else {
                out = try await app.synthesisEngine.synthesize(
                    req, modelId: s.modelId, deviceOverride: device
                )
            }
            player.load(url: out)
            player.play()
        } catch {
            longFormProgress = nil
            errorMessage = error.localizedDescription
        }
    }

    private func reroll() async {
        errorMessage = nil
        // Bump class_temperature a notch so the output varies even with
        // the same text + reference. Stays inside the same Generate call
        // so it's all-or-nothing under the isBusy guard.
        var req = currentRequest()
        let bump = Double.random(in: 0.4...1.5)
        req.classTemperature = max(0, req.classTemperature) + bump
        stampRecordMeta()
        do {
            let out = try await app.synthesisEngine.synthesize(
                req,
                modelId: app.settings.modelId,
                deviceOverride: app.settings.deviceOverride.isEmpty ? nil : app.settings.deviceOverride
            )
            player.load(url: out)
            player.play()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyProjectDocument(_ doc: ProjectDocument) {
        text = doc.text
        refText = doc.refText ?? ""
        if let id = doc.refClipID,
           let clip = app.referenceLibrary.clip(withId: id) {
            refAudioURL = app.referenceLibrary.fileURL(for: clip)
            refClipName = clip.name
        } else if let path = doc.refAudioPath,
                  FileManager.default.fileExists(atPath: path) {
            refAudioURL = URL(fileURLWithPath: path)
            refClipName = doc.refClipName ?? ""
        }
        let s = app.settings
        s.modelId = doc.modelId
        s.language = doc.language
        s.instruct = doc.instruct
        s.speed = doc.speed
        s.duration = doc.duration
        s.numStep = doc.numStep
        s.guidanceScale = doc.guidanceScale
        s.denoise = doc.denoise
        s.postprocessOutput = doc.postprocessOutput
        s.preprocessPrompt = doc.preprocessPrompt
        s.tShift = doc.tShift
        s.layerPenaltyFactor = doc.layerPenaltyFactor
        s.positionTemperature = doc.positionTemperature
        s.classTemperature = doc.classTemperature
        s.deviceOverride = doc.deviceOverride
    }

    private func saveProject() {
        var clipID: UUID? = nil
        if isFromLibrary, let url = refAudioURL {
            clipID = app.referenceLibrary.clips.first(where: {
                app.referenceLibrary.fileURL(for: $0).standardizedFileURL == url.standardizedFileURL
            })?.id
        }
        let doc = ProjectStore.capture(
            text: text,
            refClipID: clipID,
            refClipName: refClipName.isEmpty ? nil : refClipName,
            refAudioPath: refAudioURL?.path,
            refText: refText.isEmpty ? nil : refText,
            settings: app.settings
        )
        let suggested = refClipName.isEmpty
            ? String(text.prefix(40)).trimmingCharacters(in: .whitespacesAndNewlines)
            : refClipName
        ProjectStore.saveWithPanel(doc, defaultName: suggested.isEmpty ? "Untitled" : suggested)
    }

    private func loadFromHistory(_ rec: GenerationRecord) {
        text = rec.text
        refText = rec.refText ?? ""
        // Restore the ref clip if it's still in the library
        if let id = rec.refClipID,
           let clip = app.referenceLibrary.clip(withId: id) {
            refAudioURL = app.referenceLibrary.fileURL(for: clip)
            refClipName = clip.name
        } else if let path = rec.refAudioOriginalPath,
                  FileManager.default.fileExists(atPath: path) {
            refAudioURL = URL(fileURLWithPath: path)
            refClipName = ""
        } else {
            refAudioURL = nil
            refClipName = ""
        }
        let s = app.settings
        s.language = rec.language ?? ""
        s.instruct = rec.instruct ?? ""
        s.speed = rec.speed
        s.duration = rec.duration ?? 0
        s.numStep = rec.numStep
        s.guidanceScale = rec.guidanceScale
        s.denoise = rec.denoise
        s.postprocessOutput = rec.postprocessOutput
        s.preprocessPrompt = rec.preprocessPrompt
        s.tShift = rec.tShift
        s.layerPenaltyFactor = rec.layerPenaltyFactor
        s.positionTemperature = rec.positionTemperature
        s.classTemperature = rec.classTemperature
        // And play the existing file so the user hears it instantly
        player.load(url: rec.fileURL)
        player.play()
    }
}

struct EngineStateBadge: View {
    let state: SynthesisEngine.EngineState

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(state.humanLabel).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.background.secondary, in: Capsule())
    }

    private var color: Color {
        switch state {
        case .ready: return .green
        case .idle: return .gray
        case .error: return .red
        case .synthesizing, .loadingModel, .downloadingModel, .startingRunner: return .orange
        }
    }
}
