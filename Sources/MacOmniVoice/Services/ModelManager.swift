import Foundation

/// Tracks the locally cached OmniVoice model snapshot and checks for
/// updates against the HuggingFace API.
@MainActor
final class ModelManager: ObservableObject {

    struct LocalSnapshot: Equatable {
        var revision: String         // commit hash (may be a short prefix from refs)
        var snapshotPath: String
        var sizeOnDisk: Int64
    }

    struct RemoteHead: Equatable {
        var sha: String
        var lastModified: String?
        /// Sum of all file sizes in the repo tree (bytes).
        var totalBytes: Int64
        /// Largest single file in the repo (typically the main weights).
        var mainFileBytes: Int64
        var mainFileName: String
    }

    enum UpdateState: Equatable {
        case unknown
        case notInstalled
        case upToDate(local: String)
        case behind(local: String, remote: String)
        case error(String)
    }

    @Published var local: LocalSnapshot? = nil
    @Published var remote: RemoteHead? = nil
    @Published var updateState: UpdateState = .unknown
    @Published var isChecking: Bool = false
    @Published var isDownloading: Bool = false
    @Published var downloadLog: [String] = []

    let modelId = "k2-fsa/OmniVoice"

    func refreshLocalStatus(runtime: PythonRuntime) async {
        guard runtime.isRunnerLive || ((try? runtime.startRunnerIfNeeded()) != nil) else {
            updateState = .notInstalled
            return
        }
        try? runtime.send(["action": "model_info", "model_id": modelId])
        // The event loop in SynthesisEngine forwards relevant events into us.
    }

    func ingest(modelInfo: [String: Any]) {
        if let revisions = modelInfo["revisions"] as? [[String: Any]],
           let first = revisions.first,
           let hash = first["commit_hash"] as? String,
           let path = first["snapshot_path"] as? String,
           let size = first["size_on_disk"] as? Int {
            self.local = LocalSnapshot(revision: hash,
                                       snapshotPath: path,
                                       sizeOnDisk: Int64(size))
            // Recompute update state if we already have a remote head.
            if let remote = remote {
                updateState = (remote.sha == hash)
                    ? .upToDate(local: hash)
                    : .behind(local: hash, remote: remote.sha)
            } else {
                updateState = .upToDate(local: hash)
            }
        } else {
            self.local = nil
            self.updateState = .notInstalled
        }
    }

    /// Hit the HuggingFace API to get the latest commit SHA + total size.
    func checkForUpdate(force: Bool = false) async {
        isChecking = true
        defer { isChecking = false }

        async let head: RemoteHead? = fetchHead()
        async let tree: (total: Int64, mainSize: Int64, mainName: String)? = fetchTreeTotals()

        let h = await head
        let t = await tree

        guard let h = h else {
            updateState = .error("Could not reach HuggingFace API")
            return
        }
        var merged = h
        if let t = t {
            merged.totalBytes = t.total
            merged.mainFileBytes = t.mainSize
            merged.mainFileName = t.mainName
        }
        self.remote = merged

        if let local = local {
            updateState = (local.revision == merged.sha)
                ? .upToDate(local: merged.sha)
                : .behind(local: local.revision, remote: merged.sha)
        } else {
            updateState = .notInstalled
        }
    }

    private func fetchHead() async -> RemoteHead? {
        let url = URL(string: "https://huggingface.co/api/models/\(modelId)")!
        var req = URLRequest(url: url)
        req.setValue("MacOmniVoice/0.1 (+https://github.com/k2-fsa/OmniVoice)",
                     forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sha = obj["sha"] as? String else { return nil }
            return RemoteHead(
                sha: sha,
                lastModified: obj["lastModified"] as? String,
                totalBytes: 0,
                mainFileBytes: 0,
                mainFileName: ""
            )
        } catch {
            return nil
        }
    }

    private func fetchTreeTotals() async -> (total: Int64, mainSize: Int64, mainName: String)? {
        let url = URL(string: "https://huggingface.co/api/models/\(modelId)/tree/main?recursive=true")!
        var req = URLRequest(url: url)
        req.setValue("MacOmniVoice/0.1 (+https://github.com/k2-fsa/OmniVoice)",
                     forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let files = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { return nil }
            var total: Int64 = 0
            var mainSize: Int64 = 0
            var mainName = ""
            for f in files {
                let sz = (f["size"] as? Int64) ?? Int64((f["size"] as? Int) ?? 0)
                total += sz
                if sz > mainSize {
                    mainSize = sz
                    mainName = (f["path"] as? String) ?? ""
                }
            }
            return (total, mainSize, mainName)
        } catch {
            return nil
        }
    }

    /// Returns the directory containing the locally cached model snapshot
    /// (if any), otherwise the HF Hub cache root that we can still reveal.
    func revealableLocation() -> URL? {
        if let local = local {
            return URL(fileURLWithPath: local.snapshotPath)
        }
        let cache = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".cache/huggingface/hub")
        if FileManager.default.fileExists(atPath: cache) {
            return URL(fileURLWithPath: cache)
        }
        return PythonRuntime.appSupportDir
    }

    /// Trigger a download via the Python runner (huggingface_hub snapshot_download).
    func downloadOrUpdate(runtime: PythonRuntime) async {
        guard runtime.isRunnerLive || ((try? runtime.startRunnerIfNeeded()) != nil) else {
            return
        }
        isDownloading = true
        downloadLog.removeAll()
        try? runtime.send(["action": "download", "model_id": modelId])
        // SynthesisEngine will pipe download_done back to us.
    }

    func ingest(downloadLog line: String) {
        downloadLog.append(line)
    }

    func downloadFinished() {
        isDownloading = false
    }
}
