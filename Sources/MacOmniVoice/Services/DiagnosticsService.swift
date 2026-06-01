import AppKit
import Foundation

/// Operations that don't fit into PythonRuntime / SynthesisEngine but
/// still talk to them: model integrity check, post-install self-test,
/// and a one-click debug-bundle exporter.
@MainActor
final class DiagnosticsService: ObservableObject {

    struct VerificationResult: Equatable {
        struct File: Equatable {
            var path: String
            var status: String     // ok / missing / size_mismatch / hash_mismatch / io_error
            var size: Int64
            var expected: String?
            var got: String?
        }
        var ok: Bool
        var error: String?
        var files: [File]
    }

    struct SelfTestResult: Equatable {
        var ok: Bool
        var elapsed: Double
        var outputURL: URL?
        var message: String
    }

    @Published var isVerifying: Bool = false
    @Published var verifyProgress: String? = nil
    @Published var lastVerification: VerificationResult? = nil

    @Published var isRunningSelfTest: Bool = false
    @Published var lastSelfTest: SelfTestResult? = nil

    @Published var isExportingBundle: Bool = false

    // Track per-action continuations the runner promises to resolve.
    private var verifyContinuation: CheckedContinuation<VerificationResult, Error>? = nil

    func handle(event: [String: Any]) {
        guard let kind = event["event"] as? String else { return }
        switch kind {
        case "verify_start":
            verifyProgress = "Checking manifest…"
        case "verify_progress":
            if let path = event["path"] as? String {
                verifyProgress = "Hashing \(path)"
            }
        case "verify_done":
            let ok = (event["ok"] as? Bool) ?? false
            let err = event["error"] as? String
            let results = (event["results"] as? [[String: Any]]) ?? []
            let files: [VerificationResult.File] = results.map { d in
                .init(
                    path: (d["path"] as? String) ?? "?",
                    status: (d["status"] as? String) ?? "?",
                    size: Int64((d["size"] as? Int) ?? 0),
                    expected: d["expected"] as? String,
                    got: d["got"] as? String
                )
            }
            let result = VerificationResult(ok: ok, error: err, files: files)
            lastVerification = result
            verifyProgress = nil
            isVerifying = false
            verifyContinuation?.resume(returning: result)
            verifyContinuation = nil
        default:
            break
        }
    }

    /// Ask the runner to SHA256-check every cached blob against the HF manifest.
    func verifyModel(runtime: PythonRuntime, modelId: String) async throws -> VerificationResult {
        guard runtime.isRunnerLive || ((try? runtime.startRunnerIfNeeded()) != nil) else {
            throw NSError(domain: "OmniVoice", code: -10,
                          userInfo: [NSLocalizedDescriptionKey: "Runner not available."])
        }
        isVerifying = true
        verifyProgress = "Starting…"
        return try await withCheckedThrowingContinuation { cont in
            self.verifyContinuation = cont
            do {
                try runtime.send(["action": "verify", "model_id": modelId])
            } catch {
                self.verifyContinuation = nil
                self.isVerifying = false
                self.verifyProgress = nil
                cont.resume(throwing: error)
            }
        }
    }

    /// Synthesize a short canned sentence to prove the whole stack works.
    func runSelfTest(engine: SynthesisEngine, settings: AppSettings) async -> SelfTestResult {
        isRunningSelfTest = true
        defer { isRunningSelfTest = false }

        let sentence = "OmniVoice is now installed and working on this Mac."
        let req = SynthesisRequest(
            text: sentence,
            refAudioPath: nil,
            refText: nil,
            language: "en",
            instruct: nil,
            speed: 1.0,
            duration: nil,
            numStep: max(8, min(16, settings.numStep)),
            guidanceScale: settings.guidanceScale,
            denoise: settings.denoise,
            postprocessOutput: settings.postprocessOutput,
            preprocessPrompt: settings.preprocessPrompt,
            tShift: settings.tShift,
            layerPenaltyFactor: settings.layerPenaltyFactor,
            positionTemperature: settings.positionTemperature,
            classTemperature: settings.classTemperature
        )
        let start = Date()
        do {
            let url = try await engine.synthesize(
                req,
                modelId: settings.modelId,
                deviceOverride: settings.deviceOverride.isEmpty ? nil : settings.deviceOverride
            )
            let r = SelfTestResult(
                ok: true,
                elapsed: Date().timeIntervalSince(start),
                outputURL: url,
                message: "Synthesis succeeded — model + Python venv are healthy."
            )
            lastSelfTest = r
            return r
        } catch {
            let r = SelfTestResult(
                ok: false,
                elapsed: Date().timeIntervalSince(start),
                outputURL: nil,
                message: error.localizedDescription
            )
            lastSelfTest = r
            return r
        }
    }

    /// Collect logs + system info into a ZIP under ~/Downloads/, then
    /// reveal in Finder.
    @discardableResult
    func exportDebugBundle(app: AppState) -> URL? {
        isExportingBundle = true
        defer { isExportingBundle = false }

        let fm = FileManager.default
        let dateStr: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            return f.string(from: Date())
        }()
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("MacOmniVoiceDebug-\(dateStr)", isDirectory: true)
        try? fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        // 1. System info
        let sysInfo = """
        MacOmniVoice debug bundle
        Generated: \(Date())
        macOS:     \(ProcessInfo.processInfo.operatingSystemVersionString)
        Hostname:  \(ProcessInfo.processInfo.hostName)
        Locale:    \(Locale.current.identifier)
        App version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?"))
        Runner alive: \(app.pythonRuntime.isRunnerLive)
        Runner generation: \(app.pythonRuntime.generation)
        Restart count: \(app.pythonRuntime.restartCount)
        Last crash msg: \(app.pythonRuntime.lastCrashMessage ?? "-")
        Detected device: \(app.pythonRuntime.detectedDevice ?? "-")
        Model loaded: \(app.synthesisEngine.modelLoaded)
        Engine state: \(app.synthesisEngine.state.humanLabel)
        Model id: \(app.modelManager.modelId)
        Local snapshot: \(app.modelManager.local?.snapshotPath ?? "-")
        Local size: \(app.modelManager.local?.sizeOnDisk ?? 0)
        Remote total: \(app.modelManager.remote?.totalBytes ?? 0)
        Reference clips: \(app.referenceLibrary.clips.count)
        """
        try? sysInfo.write(to: tmpDir.appendingPathComponent("system-info.txt"),
                           atomically: true, encoding: .utf8)

        // 2. Console log of the engine
        let logTxt = app.synthesisEngine.consoleLog.joined(separator: "\n")
        try? logTxt.write(to: tmpDir.appendingPathComponent("engine-console.log"),
                          atomically: true, encoding: .utf8)

        // 3. Copy small support files (ref-library.json, settings)
        let appSupport = PythonRuntime.appSupportDir
        for fileName in ["ref-library.json", ".setup_complete", "omnivoice_runner.py"] {
            let src = appSupport.appendingPathComponent(fileName)
            if fm.fileExists(atPath: src.path) {
                try? fm.copyItem(at: src, to: tmpDir.appendingPathComponent(fileName))
            }
        }

        // 4. List of venv packages (best-effort)
        let pipFreeze = tmpDir.appendingPathComponent("pip-freeze.txt")
        if fm.isExecutableFile(atPath: app.pythonRuntime.venvPython.path) {
            let p = Process()
            p.executableURL = app.pythonRuntime.venvPython
            p.arguments = ["-m", "pip", "freeze"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = Pipe()
            do {
                try p.run()
                p.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                try? data.write(to: pipFreeze)
            } catch {
                try? "pip freeze failed: \(error)".write(to: pipFreeze,
                                                         atomically: true, encoding: .utf8)
            }
        }

        // 5. Zip it
        let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser
        let zipURL = downloads.appendingPathComponent("MacOmniVoiceDebug-\(dateStr).zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-r", zipURL.path, tmpDir.lastPathComponent]
        zip.currentDirectoryURL = tmpDir.deletingLastPathComponent()
        let zipPipe = Pipe()
        zip.standardOutput = zipPipe
        zip.standardError = zipPipe
        do {
            try zip.run()
            zip.waitUntilExit()
        } catch {
            return nil
        }
        // Clean up the staging dir
        try? fm.removeItem(at: tmpDir)

        NSWorkspace.shared.activateFileViewerSelecting([zipURL])
        return zipURL
    }
}
