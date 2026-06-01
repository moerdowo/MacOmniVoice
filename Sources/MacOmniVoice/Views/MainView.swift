import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct MainView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var player = AudioPlayerService()

    @State private var text: String = "Hello, this is a test of zero-shot voice cloning."
    @State private var refText: String = ""
    @State private var refAudioURL: URL? = nil
    @State private var showAdvanced: Bool = false
    @State private var showConsole: Bool = false
    @State private var showRecorder: Bool = false
    @State private var errorMessage: String? = nil
    @StateObject private var recorder = AudioRecorderService()

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    titleRow
                    modelStatusCard
                    textInputCard
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
                    showAdvanced.toggle()
                } label: {
                    Label(showAdvanced ? "Hide Advanced" : "Advanced",
                          systemImage: "slider.horizontal.3")
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await app.modelManager.checkForUpdate(force: true) }
                } label: {
                    Label("Check for Update", systemImage: "arrow.triangle.2.circlepath")
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
        .onAppear {
            app.synthesisEngine.attach(modelManager: app.modelManager)
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
                Label("Text to synthesize", systemImage: "text.alignleft").font(.headline)
                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
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
        }
    }

    private var referenceAudioCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Reference audio (voice to clone)", systemImage: "waveform")
                    .font(.headline)

                HStack(spacing: 10) {
                    if let refAudioURL {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(refAudioURL.lastPathComponent)
                                .font(.callout).bold()
                                .lineLimit(1).truncationMode(.middle)
                            Text(refAudioURL.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            self.refAudioURL = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill").imageScale(.large)
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Text("Drop or pick a 3–10 s WAV/MP3/FLAC clip")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
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
        HStack {
            Spacer()
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
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                      isWorking)
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
        case .synthesizing: return "Generating…"
        default: return "Generate"
        }
    }

    private func pickReferenceAudio() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio, .wav, .mp3]
        if panel.runModal() == .OK { refAudioURL = panel.url }
    }

    private func generate() async {
        errorMessage = nil
        let s = app.settings
        let req = SynthesisRequest(
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
        do {
            let out = try await app.synthesisEngine.synthesize(
                req,
                modelId: s.modelId,
                deviceOverride: s.deviceOverride.isEmpty ? nil : s.deviceOverride
            )
            player.load(url: out)
            player.play()
        } catch {
            errorMessage = error.localizedDescription
        }
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
