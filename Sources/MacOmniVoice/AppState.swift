import Combine
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    let pythonRuntime = PythonRuntime()
    let modelManager = ModelManager()
    let synthesisEngine: SynthesisEngine
    let settings = AppSettings()
    let referenceLibrary = ReferenceLibrary()
    let diagnostics = DiagnosticsService()
    let history = GenerationHistory()
    let transcription = TranscriptionService()

    @Published var currentStage: AppStage = .checking
    /// Set when the user picks Open Project; MainView watches this and
    /// applies the document, then clears it.
    @Published var pendingProjectDocument: ProjectDocument? = nil

    enum AppStage: Equatable {
        case checking
        case needsSetup
        case settingUp
        case ready
    }

    private var cancellables: Set<AnyCancellable> = []

    init() {
        self.synthesisEngine = SynthesisEngine(runtime: pythonRuntime)

        // Re-publish nested observable changes so any view that observes
        // AppState re-renders when ModelManager, SynthesisEngine, or
        // settings publish updates.
        let forward = { [weak self] in self?.objectWillChange.send() }
        modelManager.objectWillChange.sink { _ in forward() }.store(in: &cancellables)
        synthesisEngine.objectWillChange.sink { _ in forward() }.store(in: &cancellables)
        pythonRuntime.objectWillChange.sink { _ in forward() }.store(in: &cancellables)
        settings.objectWillChange.sink { _ in forward() }.store(in: &cancellables)
        referenceLibrary.objectWillChange.sink { _ in forward() }.store(in: &cancellables)
        diagnostics.objectWillChange.sink { _ in forward() }.store(in: &cancellables)
        history.objectWillChange.sink { _ in forward() }.store(in: &cancellables)
        transcription.objectWillChange.sink { _ in forward() }.store(in: &cancellables)

        // Route transcribe_done events from the runner stream into the
        // transcription service via the engine's event tap.
        synthesisEngine.eventTap = { [weak transcription] event in
            transcription?.handle(event: event)
        }

        Task { await bootstrap() }
    }

    func bootstrap() async {
        currentStage = .checking
        let status = await pythonRuntime.detectStatus()
        switch status {
        case .ready:
            currentStage = .ready
            await modelManager.refreshLocalStatus(runtime: pythonRuntime)
            if settings.autoCheckUpdates {
                await modelManager.checkForUpdate()
            }
        case .needsSetup:
            currentStage = .needsSetup
        }
    }

    func beginSetup(progress: @escaping (String) -> Void) async throws {
        currentStage = .settingUp
        try await pythonRuntime.performSetup(progress: progress)
        currentStage = .ready
        await modelManager.refreshLocalStatus(runtime: pythonRuntime)
    }

    enum GeneratePreflight: Equatable {
        case ready
        case blocked(reason: String, hint: String)
    }

    /// All-up gate for the Generate button. Returns either .ready or a
    /// human-readable reason the user can act on.
    func preflightForGenerate(text: String) -> GeneratePreflight {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .blocked(reason: "Enter some text to synthesize.",
                            hint: "Type a sentence in the text box above.")
        }
        if currentStage != .ready {
            return .blocked(reason: "Setup is not complete yet.",
                            hint: "Finish the initial OmniVoice install before generating.")
        }
        if !pythonRuntime.isRunnerLive {
            return .blocked(reason: "OmniVoice runner is not running.",
                            hint: "Try restarting the app — the Python subprocess died.")
        }
        if synthesisEngine.downloadProgress != nil {
            return .blocked(reason: "Model is downloading.",
                            hint: "Wait for the download to finish, then click Generate.")
        }
        if !modelManager.isFullyDownloaded {
            return .blocked(reason: "Model weights are not fully downloaded.",
                            hint: "Click the Download button above to fetch the ~3 GB model from HuggingFace.")
        }
        if synthesisEngine.isBusy {
            return .blocked(reason: "Already generating audio.",
                            hint: "One synthesis at a time — wait for the current run to finish.")
        }
        switch synthesisEngine.state {
        case .loadingModel:
            return .blocked(reason: "Loading model into memory.",
                            hint: "First-load takes ~30–60 s on Apple Silicon; please wait.")
        case .startingRunner:
            return .blocked(reason: "Starting Python runner.",
                            hint: "Almost ready…")
        default:
            break
        }
        return .ready
    }
}
