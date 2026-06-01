import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    let pythonRuntime = PythonRuntime()
    let modelManager = ModelManager()
    let synthesisEngine: SynthesisEngine
    let settings = AppSettings()

    @Published var currentStage: AppStage = .checking

    enum AppStage: Equatable {
        case checking
        case needsSetup
        case settingUp
        case ready
    }

    init() {
        self.synthesisEngine = SynthesisEngine(runtime: pythonRuntime)
        Task { await bootstrap() }
    }

    func bootstrap() async {
        currentStage = .checking
        let status = await pythonRuntime.detectStatus()
        switch status {
        case .ready:
            currentStage = .ready
            await modelManager.refreshLocalStatus(runtime: pythonRuntime)
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
}
