import Foundation

/// Owns the per-app Python virtual environment and the long-lived
/// `omnivoice_runner.py` subprocess used for inference.
@MainActor
final class PythonRuntime: ObservableObject {

    enum SetupStatus { case ready, needsSetup }
    enum RuntimeError: LocalizedError {
        case noPythonFound
        case pythonTooOld(String)
        case venvFailed(String)
        case pipFailed(String)
        case runnerCrashed(String)
        case timeout(String)
        case scriptMissing
        case notReady

        var errorDescription: String? {
            switch self {
            case .noPythonFound:
                return "No suitable Python 3.10+ interpreter was found. Install Python from python.org or via Homebrew (`brew install python@3.11`)."
            case .pythonTooOld(let v):
                return "Python \(v) is too old. OmniVoice requires Python 3.10 or newer."
            case .venvFailed(let msg):
                return "Failed to create Python virtual environment: \(msg)"
            case .pipFailed(let msg):
                return "Failed to install Python dependencies: \(msg)"
            case .runnerCrashed(let msg):
                return "OmniVoice runner crashed: \(msg)"
            case .timeout(let msg):
                return "OmniVoice runner timed out: \(msg)"
            case .scriptMissing:
                return "Internal error: omnivoice_runner.py is missing from the app bundle."
            case .notReady:
                return "OmniVoice runtime is not ready yet."
            }
        }
    }

    // MARK: - Locations

    static let appSupportDir: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MacOmniVoice", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    var venvDir: URL { Self.appSupportDir.appendingPathComponent("venv", isDirectory: true) }
    var venvPython: URL { venvDir.appendingPathComponent("bin/python3") }
    var venvPip: URL { venvDir.appendingPathComponent("bin/pip") }
    var runnerScript: URL { Self.appSupportDir.appendingPathComponent("omnivoice_runner.py") }
    var setupMarker: URL { Self.appSupportDir.appendingPathComponent(".setup_complete") }

    // MARK: - Public state

    @Published private(set) var isRunnerLive: Bool = false
    @Published private(set) var detectedDevice: String? = nil
    @Published private(set) var samplingRate: Int = 24_000

    // MARK: - Subprocess plumbing

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutBuffer = Data()
    private var eventContinuation: AsyncStream<[String: Any]>.Continuation?
    private var eventStream: AsyncStream<[String: Any]>?

    // MARK: - Setup detection

    func detectStatus() async -> SetupStatus {
        let fm = FileManager.default
        guard fm.fileExists(atPath: setupMarker.path),
              fm.fileExists(atPath: venvPython.path) else {
            return .needsSetup
        }
        // Refresh the bundled runner script every launch so updates ship cleanly.
        if let bundled = bundledRunnerURL() {
            try? fm.removeItem(at: runnerScript)
            try? fm.copyItem(at: bundled, to: runnerScript)
        }
        return .ready
    }

    /// Tries to find a host Python ≥ 3.10 that we can use to bootstrap a venv.
    func findHostPython() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/python3.12",
            "/opt/homebrew/bin/python3.11",
            "/opt/homebrew/bin/python3.10",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3.12",
            "/usr/local/bin/python3.11",
            "/usr/local/bin/python3.10",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        for path in candidates {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.isExecutableFile(atPath: url.path),
               let version = pythonVersion(at: url),
               version >= (3, 10) {
                return url
            }
        }
        // Also try `which python3` via /usr/bin/env
        if let pth = whichPython3(), let version = pythonVersion(at: pth), version >= (3, 10) {
            return pth
        }
        return nil
    }

    private func whichPython3() -> URL? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["which", "python3"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !s.isEmpty {
                return URL(fileURLWithPath: s)
            }
        } catch {
            return nil
        }
        return nil
    }

    private func pythonVersion(at url: URL) -> (Int, Int)? {
        let p = Process()
        p.executableURL = url
        p.arguments = ["-c", "import sys; print(f'{sys.version_info[0]}.{sys.version_info[1]}')"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let s = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               let dot = s.firstIndex(of: "."),
               let maj = Int(s[..<dot]),
               let min = Int(s[s.index(after: dot)...]) {
                return (maj, min)
            }
        } catch {}
        return nil
    }

    // MARK: - Setup

    /// Creates the venv and pip-installs OmniVoice + PyTorch. Progress lines
    /// are reported via `progress` so the UI can render a console-style log.
    func performSetup(progress: @escaping (String) -> Void) async throws {
        guard let host = findHostPython() else {
            throw RuntimeError.noPythonFound
        }
        guard let version = pythonVersion(at: host), version >= (3, 10) else {
            throw RuntimeError.pythonTooOld("unknown")
        }
        progress("Using host Python: \(host.path) (\(version.0).\(version.1))")

        // Step 1: create venv
        if !FileManager.default.fileExists(atPath: venvPython.path) {
            progress("Creating virtual environment at \(venvDir.path)…")
            try await runShell(host.path, ["-m", "venv", venvDir.path],
                               progress: progress, label: "venv")
        } else {
            progress("Virtual environment already exists at \(venvDir.path)")
        }

        // Step 2: upgrade pip
        progress("Upgrading pip…")
        try await runShell(venvPython.path,
                           ["-m", "pip", "install", "--upgrade", "pip", "wheel", "setuptools"],
                           progress: progress, label: "pip-upgrade")

        // Step 3: install PyTorch (Apple Silicon uses default wheels)
        progress("Installing PyTorch (this can take several minutes)…")
        try await runShell(venvPython.path,
                           ["-m", "pip", "install", "torch==2.8.0", "torchaudio==2.8.0"],
                           progress: progress, label: "torch")

        // Step 4: install OmniVoice itself
        progress("Installing OmniVoice…")
        try await runShell(venvPython.path,
                           ["-m", "pip", "install", "omnivoice"],
                           progress: progress, label: "omnivoice")

        // Step 5: copy runner script into appsupport
        try copyRunnerScript()
        progress("Installed runner script: \(runnerScript.path)")

        // Mark setup complete
        try Data("ok".utf8).write(to: setupMarker, options: .atomic)
        progress("Setup complete.")
    }

    private func bundledRunnerURL() -> URL? {
        Bundle.module.url(forResource: "omnivoice_runner", withExtension: "py")
    }

    private func copyRunnerScript() throws {
        guard let src = bundledRunnerURL() else { throw RuntimeError.scriptMissing }
        let dst = runnerScript
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) {
            try fm.removeItem(at: dst)
        }
        try fm.copyItem(at: src, to: dst)
    }

    private func runShell(_ launchPath: String,
                          _ arguments: [String],
                          progress: @escaping (String) -> Void,
                          label: String) async throws {
        progress("[\(label)] \(launchPath) \(arguments.joined(separator: " "))")
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: launchPath)
            p.arguments = arguments
            let out = Pipe()
            let err = Pipe()
            p.standardOutput = out
            p.standardError = err

            out.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let s = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async { progress(s.trimmingCharacters(in: .newlines)) }
                }
            }
            err.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let s = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async { progress("[stderr] " + s.trimmingCharacters(in: .newlines)) }
                }
            }

            p.terminationHandler = { proc in
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                if proc.terminationStatus == 0 {
                    cont.resume(returning: ())
                } else {
                    cont.resume(throwing: RuntimeError.pipFailed("\(label) exited with \(proc.terminationStatus)"))
                }
            }

            do {
                try p.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    // MARK: - Long-lived runner

    /// Starts the persistent `omnivoice_runner.py` subprocess.
    func startRunnerIfNeeded() throws {
        if isRunnerLive, let proc = process, proc.isRunning { return }
        guard FileManager.default.fileExists(atPath: venvPython.path) else {
            throw RuntimeError.notReady
        }
        if !FileManager.default.fileExists(atPath: runnerScript.path) {
            try copyRunnerScript()
        }

        let p = Process()
        p.executableURL = venvPython
        p.arguments = [runnerScript.path]
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        // Allow the user to choose the mainland mirror via env if HF is blocked.
        if env["HF_ENDPOINT"] == nil, ProcessInfo.processInfo.environment["MACOMNIVOICE_HF_MIRROR"] == "1" {
            env["HF_ENDPOINT"] = "https://hf-mirror.com"
        }
        p.environment = env

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = stderr

        self.process = p
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.stderrPipe = stderr
        self.stdoutBuffer.removeAll()

        let stream = AsyncStream<[String: Any]> { cont in
            self.eventContinuation = cont
        }
        self.eventStream = stream

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.ingestStdout(data) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let s = String(data: data, encoding: .utf8) else { return }
            FileHandle.standardError.write(Data(("[runner-stderr] " + s).utf8))
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRunnerLive = false
                self?.eventContinuation?.finish()
            }
        }

        try p.run()
        self.isRunnerLive = true
    }

    private func ingestStdout(_ data: Data) {
        stdoutBuffer.append(data)
        while let nl = stdoutBuffer.firstIndex(of: 0x0a) {
            let line = stdoutBuffer.subdata(in: 0..<nl)
            stdoutBuffer.removeSubrange(0...nl)
            guard !line.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                continue
            }
            // Cache device & sampling rate from load_done events.
            if let ev = obj["event"] as? String, ev == "load_done" {
                if let dev = obj["device"] as? String { detectedDevice = dev }
                if let sr = obj["sampling_rate"] as? Int { samplingRate = sr }
            }
            eventContinuation?.yield(obj)
        }
    }

    /// Public stream of decoded JSON events from the runner.
    func events() -> AsyncStream<[String: Any]> {
        if let s = eventStream { return s }
        return AsyncStream { _ in }
    }

    /// Send a JSON request to the runner.
    func send(_ payload: [String: Any]) throws {
        guard isRunnerLive, let stdin = stdinPipe else {
            throw RuntimeError.notReady
        }
        var data = try JSONSerialization.data(withJSONObject: payload, options: [])
        data.append(0x0a)
        try stdin.fileHandleForWriting.write(contentsOf: data)
    }

    func stopRunner() {
        if isRunnerLive {
            try? send(["action": "quit"])
        }
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        isRunnerLive = false
    }
}
