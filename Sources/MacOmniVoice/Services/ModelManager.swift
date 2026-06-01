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

    /// Hit the HuggingFace API to get the latest commit SHA for the model repo.
    func checkForUpdate(force: Bool = false) async {
        isChecking = true
        defer { isChecking = false }

        let url = URL(string: "https://huggingface.co/api/models/\(modelId)")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("MacOmniVoice/0.1 (+https://github.com/k2-fsa/OmniVoice)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                updateState = .error("HF API HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
                return
            }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                updateState = .error("Invalid HF JSON")
                return
            }
            let sha = (obj["sha"] as? String) ?? ""
            let modified = obj["lastModified"] as? String
            self.remote = RemoteHead(sha: sha, lastModified: modified)

            if let local = local {
                if local.revision == sha {
                    updateState = .upToDate(local: sha)
                } else {
                    updateState = .behind(local: local.revision, remote: sha)
                }
            } else {
                updateState = .notInstalled
            }
        } catch {
            updateState = .error(error.localizedDescription)
        }
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
