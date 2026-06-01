import Combine
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
    weak var diagnostics: DiagnosticsService?
    weak var history: GenerationHistory?
    /// Extra metadata the engine should stamp on the next history record
    /// — set by the MainView right before calling synthesize().
    var nextRecordMeta: NextRecordMeta? = nil
    /// External handler called for *every* event after engine-level
    /// handling so other services (transcription, history) can hook in.
    var eventTap: (([String: Any]) -> Void)? = nil

    struct NextRecordMeta {
        var refClipID: UUID?
        var refClipName: String?
        var refAudioOriginalPath: String?
        var refText: String?
    }
    private var pumpTask: Task<Void, Never>? = nil
    private var pendingSynthesisContinuation: CheckedContinuation<URL, Error>? = nil
    private var pendingLoadContinuation: CheckedContinuation<Void, Error>? = nil
    private var pendingDownloadContinuation: CheckedContinuation<Void, Error>? = nil
    private var lastRuntimeGeneration: Int = 0
    private var generationObserver: AnyCancellable? = nil

    init(runtime: PythonRuntime) {
        self.runtime = runtime
        // Re-bind the event pump and reset state whenever the runtime
        // process is (re)started — handles the auto-restart-on-crash path.
        self.generationObserver = runtime.$generation
            .receive(on: RunLoop.main)
            .sink { [weak self] g in
                guard let self else { return }
                guard g > self.lastRuntimeGeneration else { return }
                self.lastRuntimeGeneration = g
                if g > 1 {
                    self.handleRunnerRestart()
                }
                self.startPump()
            }
    }

    private func handleRunnerRestart() {
        appendLog("Runner restarted (generation #\(lastRuntimeGeneration)). Model needs to reload.")
        modelLoaded = false
        downloadProgress = nil
        synthesisElapsed = 0
        // Resume any pending continuations with a clear error so the
        // caller's Task doesn't hang forever after a crash.
        let err = NSError(domain: "OmniVoice", code: -4,
                          userInfo: [NSLocalizedDescriptionKey: "Python runner restarted mid-operation."])
        if let c = pendingSynthesisContinuation {
            c.resume(throwing: err); pendingSynthesisContinuation = nil
        }
        if let c = pendingLoadContinuation {
            c.resume(throwing: err); pendingLoadContinuation = nil
        }
        if let c = pendingDownloadContinuation {
            c.resume(throwing: err); pendingDownloadContinuation = nil
        }
        isBusy = false
        state = .ready
    }

    func attach(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    func attach(history: GenerationHistory) {
        self.history = history
    }

    /// Start the persistent Python subprocess and begin pumping events.
    /// The pump itself is wired by the generation observer in init().
    func startRunnerAndPump() throws {
        state = .startingRunner
        try runtime.startRunnerIfNeeded()
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

        // Pass to diagnostics / external tap first so they can observe
        // every event regardless of whether we have a switch case for it.
        diagnostics?.handle(event: event)
        eventTap?(event)

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
        if isBusy {
            throw NSError(domain: "OmniVoice", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Already generating — please wait."])
        }
        isBusy = true
        defer { isBusy = false }

        return try await _synthesizeOne(request, modelId: modelId, deviceOverride: deviceOverride,
                                        isLongForm: false)
    }

    /// Used by queue / long-form so they don't trip the isBusy guard
    /// every chunk. Caller is responsible for setting isBusy.
    func synthesizeChunk(_ request: SynthesisRequest,
                         modelId: String,
                         deviceOverride: String?) async throws -> URL {
        try await _synthesizeOne(request, modelId: modelId, deviceOverride: deviceOverride,
                                 isLongForm: true)
    }

    private func _synthesizeOne(_ request: SynthesisRequest,
                                modelId: String,
                                deviceOverride: String?,
                                isLongForm: Bool) async throws -> URL {
        try await ensureModelLoaded(modelId: modelId, deviceOverride: deviceOverride)

        let outDir = GenerationHistory.outputsDir
        let ts = ISO8601DateFormatter()
        ts.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        let stamp = ts.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let fileName = "omnivoice-\(stamp).wav"
        let outURL = outDir.appendingPathComponent(fileName)

        let payload: [String: Any] = [
            "action": "synthesize",
            "out_path": outURL.path,
            "params": request.toParams(),
        ]

        let url: URL = try await withCheckedThrowingContinuation { cont in
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

        // Record to history (only for whole-shot calls; long-form does
        // its own bookkeeping after concat).
        if !isLongForm, let history = history {
            let rec = makeRecord(request: request, file: url, elapsed: synthesisElapsed)
            history.add(rec)
            nextRecordMeta = nil
        }
        return url
    }

    private func makeRecord(request: SynthesisRequest, file: URL, elapsed: Double) -> GenerationRecord {
        let m = nextRecordMeta
        return GenerationRecord(
            text: request.text,
            fileName: file.lastPathComponent,
            elapsed: elapsed,
            sampleRate: runtime.samplingRate,
            refClipID: m?.refClipID,
            refClipName: m?.refClipName,
            refAudioOriginalPath: m?.refAudioOriginalPath ?? request.refAudioPath,
            refText: request.refText,
            language: request.language,
            instruct: request.instruct,
            speed: request.speed,
            duration: request.duration,
            numStep: request.numStep,
            guidanceScale: request.guidanceScale,
            denoise: request.denoise,
            postprocessOutput: request.postprocessOutput,
            preprocessPrompt: request.preprocessPrompt,
            tShift: request.tShift,
            layerPenaltyFactor: request.layerPenaltyFactor,
            positionTemperature: request.positionTemperature,
            classTemperature: request.classTemperature,
            device: runtime.detectedDevice
        )
    }

    /// Long-form: split text by sentence, synth each chunk, concatenate,
    /// record one history entry for the stitched result.
    func synthesizeLongForm(_ request: SynthesisRequest,
                            modelId: String,
                            deviceOverride: String?,
                            progress: ((Int, Int) -> Void)? = nil) async throws -> URL {
        if isBusy {
            throw NSError(domain: "OmniVoice", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Already generating — please wait."])
        }
        isBusy = true
        defer { isBusy = false }

        let chunks = TextSplitter.split(request.text)
        if chunks.isEmpty {
            throw NSError(domain: "OmniVoice", code: -5,
                          userInfo: [NSLocalizedDescriptionKey: "No text to synthesize."])
        }
        if chunks.count == 1 {
            return try await _synthesizeOne(request, modelId: modelId,
                                            deviceOverride: deviceOverride, isLongForm: false)
        }
        appendLog("Long-form: \(chunks.count) chunks")
        progress?(0, chunks.count)

        var pieces: [URL] = []
        for (idx, c) in chunks.enumerated() {
            var r = request
            r.text = c
            do {
                let part = try await synthesizeChunk(r, modelId: modelId, deviceOverride: deviceOverride)
                pieces.append(part)
                progress?(idx + 1, chunks.count)
            } catch {
                throw error
            }
        }

        let outDir = GenerationHistory.outputsDir
        let ts = ISO8601DateFormatter()
        ts.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        let stamp = ts.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let outURL = outDir.appendingPathComponent("omnivoice-longform-\(stamp).wav")
        try AudioConcat.concat(pieces, into: outURL, silenceSeconds: 0.25)

        // Clean up the per-chunk files — keep only the stitched output.
        for p in pieces { try? FileManager.default.removeItem(at: p) }

        if let history = history {
            history.add(makeRecord(request: request, file: outURL, elapsed: synthesisElapsed))
            nextRecordMeta = nil
        }
        return outURL
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
