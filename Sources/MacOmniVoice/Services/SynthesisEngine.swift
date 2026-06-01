import Foundation

/// High-level orchestrator that talks to the Python runner for model load
/// and synthesis. It also routes other events to the right manager.
@MainActor
final class SynthesisEngine: ObservableObject {

    enum EngineState: Equatable {
        case idle
        case startingRunner
        case loadingModel
        case ready
        case downloadingModel
        case synthesizing
        case error(String)

        var humanLabel: String {
            switch self {
            case .idle: return "Idle"
            case .startingRunner: return "Starting Python runner…"
            case .loadingModel: return "Loading OmniVoice model…"
            case .ready: return "Ready"
            case .downloadingModel: return "Downloading model from HuggingFace…"
            case .synthesizing: return "Synthesizing…"
            case .error(let s): return "Error: \(s)"
            }
        }
    }

    @Published var state: EngineState = .idle
    @Published var modelLoaded: Bool = false
    @Published var lastOutput: URL? = nil
    @Published var lastError: String? = nil
    @Published var consoleLog: [String] = []
    /// Live elapsed seconds while a synth is in progress (from runner heartbeat).
    @Published var synthesisElapsed: Double = 0
    /// True from the moment Generate is clicked until the synth resolves or fails.
    /// Used to suppress reentrant clicks that would otherwise overwrite the
    /// pending-continuation and leak the first Task.
    @Published var isBusy: Bool = false

    /// Aggregate download progress shown in the UI. nil = no active download.
    @Published var downloadProgress: DownloadProgress? = nil

    struct DownloadProgress: Equatable {
        var label: String
        var n: Int64
        var total: Int64
        var fraction: Double {
            guard total > 0 else { return 0 }
            return min(1, max(0, Double(n) / Double(total)))
        }
        var humanLabel: String {
            if total == 0 { return label }
            let mb = Double(total) / (1024 * 1024)
            let done = Double(n) / (1024 * 1024)
            return "\(label) · \(String(format: "%.1f / %.1f MB", done, mb))"
        }
    }

    private let runtime: PythonRuntime
    weak var modelManager: ModelManager?
    private var pumpTask: Task<Void, Never>? = nil
    private var pendingSynthesisContinuation: CheckedContinuation<URL, Error>? = nil
    private var pendingLoadContinuation: CheckedContinuation<Void, Error>? = nil
    private var pendingDownloadContinuation: CheckedContinuation<Void, Error>? = nil

    init(runtime: PythonRuntime) {
        self.runtime = runtime
    }

    func attach(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    /// Start the persistent Python subprocess and begin pumping events.
    func startRunnerAndPump() throws {
        state = .startingRunner
        try runtime.startRunnerIfNeeded()
        startPump()
        state = .ready
    }

    private func startPump() {
        pumpTask?.cancel()
        pumpTask = Task { [weak self] in
            guard let self else { return }
            for await event in runtime.events() {
                await self.handle(event: event)
            }
        }
    }

    private func appendLog(_ s: String) {
        consoleLog.append(s)
        if consoleLog.count > 500 {
            consoleLog.removeFirst(consoleLog.count - 500)
        }
    }

    private func handle(event: [String: Any]) async {
        let kind = event["event"] as? String ?? "?"
        switch kind {
        case "log":
            let lvl = (event["level"] as? String) ?? "info"
            let msg = (event["msg"] as? String) ?? ""
            appendLog("[\(lvl)] \(msg)")

        case "load_start":
            state = .loadingModel
            appendLog("Loading model on \((event["device"] as? String) ?? "?")…")
        case "load_done":
            modelLoaded = true
            state = .ready
            appendLog("Model loaded (sample rate \(event["sampling_rate"] ?? "?"), device \(event["device"] ?? "?")).")
            pendingLoadContinuation?.resume()
            pendingLoadContinuation = nil

        case "synthesize_start":
            state = .synthesizing
            synthesisElapsed = 0
            let step = (event["num_step"] as? Int) ?? 0
            let dev = (event["device"] as? String) ?? "?"
            appendLog("Synthesizing on \(dev) (num_step=\(step))…")
        case "synthesize_progress":
            if let e = event["elapsed"] as? Double {
                synthesisElapsed = e
            }
        case "synthesize_done":
            state = .ready
            let path = (event["out_path"] as? String) ?? ""
            let elapsed = (event["elapsed"] as? Double) ?? 0
            synthesisElapsed = 0
            appendLog("Done in \(String(format: "%.2f", elapsed))s → \(path)")
            let url = URL(fileURLWithPath: path)
            self.lastOutput = url
            pendingSynthesisContinuation?.resume(returning: url)
            pendingSynthesisContinuation = nil

        case "download_start":
            state = .downloadingModel
            modelManager?.isDownloading = true
            downloadProgress = DownloadProgress(label: "Starting download…", n: 0, total: 0)
            appendLog("Downloading \(event["model_id"] ?? "")…")
        case "download_progress":
            let n = (event["n"] as? Int).map(Int64.init) ?? 0
            var total = (event["total"] as? Int).map(Int64.init) ?? 0
            let desc = (event["desc"] as? String) ?? "Downloading"
            // The runner has no idea what the repo total is; fill it
            // in from the cached HF tree response on the Swift side.
            if total == 0, let knownTotal = modelManager?.remote?.totalBytes, knownTotal > 0 {
                total = knownTotal
            }
            downloadProgress = DownloadProgress(label: desc, n: n, total: total)
            // Mirror the live bytes into the model manager so the status
            // headline ("Partial download · 41%") moves too.
            if let mm = modelManager {
                let existing = mm.local
                mm.local = .init(
                    revision: existing?.revision ?? "",
                    snapshotPath: existing?.snapshotPath ?? "",
                    sizeOnDisk: n
                )
            }
        case "download_done":
            state = .ready
            downloadProgress = nil
            appendLog("Download complete → \((event["snapshot_path"] as? String) ?? "?")")
            modelManager?.downloadFinished()
            pendingDownloadContinuation?.resume()
            pendingDownloadContinuation = nil
            // After download, refresh local info.
            try? runtime.send(["action": "model_info", "model_id": modelManager?.modelId ?? "k2-fsa/OmniVoice"])

        case "model_info":
            modelManager?.ingest(modelInfo: event)

        case "error":
            let msg = (event["msg"] as? String) ?? "unknown"
            self.lastError = msg
            appendLog("ERROR: \(msg)")
            state = .error(msg)
            pendingSynthesisContinuation?.resume(throwing: NSError(domain: "OmniVoice", code: -1, userInfo: [NSLocalizedDescriptionKey: msg]))
            pendingSynthesisContinuation = nil
            pendingLoadContinuation?.resume(throwing: NSError(domain: "OmniVoice", code: -1, userInfo: [NSLocalizedDescriptionKey: msg]))
            pendingLoadContinuation = nil
            pendingDownloadContinuation?.resume(throwing: NSError(domain: "OmniVoice", code: -1, userInfo: [NSLocalizedDescriptionKey: msg]))
            pendingDownloadContinuation = nil

        case "bye":
            appendLog("Runner exiting.")
        default:
            break
        }
    }

    /// Ensure model is loaded; loads on first call.
    func ensureModelLoaded(modelId: String, deviceOverride: String? = nil) async throws {
        if modelLoaded { return }
        try? runtime.startRunnerIfNeeded()
        if pumpTask == nil { startPump() }
        var payload: [String: Any] = [
            "action": "load",
            "model_id": modelId,
        ]
        if let dev = deviceOverride, !dev.isEmpty {
            payload["device"] = dev
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            if let stale = self.pendingLoadContinuation {
                stale.resume(throwing: NSError(
                    domain: "OmniVoice", code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "Superseded by a newer load request."]))
            }
            self.pendingLoadContinuation = cont
            do {
                try runtime.send(payload)
            } catch {
                self.pendingLoadContinuation = nil
                cont.resume(throwing: error)
            }
        }
    }

    func synthesize(_ request: SynthesisRequest,
                    modelId: String,
                    deviceOverride: String?) async throws -> URL {
        // Reject re-entrant calls. Prevents the click-twice bug where a
        // second click overwrites pendingSynthesisContinuation and the
        // first awaiting Task hangs forever.
        if isBusy {
            throw NSError(domain: "OmniVoice", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Already generating — please wait."])
        }
        isBusy = true
        defer { isBusy = false }

        try await ensureModelLoaded(modelId: modelId, deviceOverride: deviceOverride)

        // Write output to a temp file under appsupport/outputs.
        let outDir = PythonRuntime.appSupportDir.appendingPathComponent("outputs", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let ts = ISO8601DateFormatter()
        ts.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        let stamp = ts.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let outURL = outDir.appendingPathComponent("omnivoice-\(stamp).wav")

        let payload: [String: Any] = [
            "action": "synthesize",
            "out_path": outURL.path,
            "params": request.toParams(),
        ]

        return try await withCheckedThrowingContinuation { cont in
            // Defensive: if a continuation is somehow still pending (e.g.
            // a previous synth was abandoned), resume it with an error
            // before overwriting so it doesn't leak.
            if let stale = self.pendingSynthesisContinuation {
                stale.resume(throwing: NSError(
                    domain: "OmniVoice", code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "Superseded by a newer request."]))
            }
            self.pendingSynthesisContinuation = cont
            do {
                try runtime.send(payload)
            } catch {
                self.pendingSynthesisContinuation = nil
                cont.resume(throwing: error)
            }
        }
    }

    func downloadOrUpdateModel(modelId: String) async throws {
        try? runtime.startRunnerIfNeeded()
        if pumpTask == nil { startPump() }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.pendingDownloadContinuation = cont
            do {
                try runtime.send(["action": "download", "model_id": modelId])
            } catch {
                self.pendingDownloadContinuation = nil
                cont.resume(throwing: error)
            }
        }
    }
}
