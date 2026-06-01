import Foundation

@MainActor
final class TranscriptionService: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var lastError: String? = nil

    private var pending: [URL: CheckedContinuation<String, Error>] = [:]

    /// Engine event tap forwards "transcribe_done" events here.
    func handle(event: [String: Any]) {
        guard event["event"] as? String == "transcribe_done" else { return }
        let path = (event["audio_path"] as? String) ?? ""
        let url = URL(fileURLWithPath: path)
        guard let cont = pending[url] else { return }
        pending[url] = nil
        if let err = event["error"] as? String, !err.isEmpty {
            cont.resume(throwing: NSError(domain: "OmniVoice", code: -11,
                                          userInfo: [NSLocalizedDescriptionKey: err]))
        } else {
            let text = (event["text"] as? String) ?? ""
            cont.resume(returning: text)
        }
        if pending.isEmpty { isRunning = false }
    }

    func transcribe(audio url: URL,
                    language: String? = nil,
                    runtime: PythonRuntime) async throws -> String {
        try? runtime.startRunnerIfNeeded()
        isRunning = true
        return try await withCheckedThrowingContinuation { cont in
            pending[url] = cont
            var payload: [String: Any] = [
                "action": "transcribe",
                "audio_path": url.path,
            ]
            if let language { payload["language"] = language }
            do {
                try runtime.send(payload)
            } catch {
                pending[url] = nil
                cont.resume(throwing: error)
            }
        }
    }
}
