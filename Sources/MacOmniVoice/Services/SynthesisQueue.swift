import Foundation

@MainActor
final class SynthesisQueue: ObservableObject {

    struct Item: Identifiable, Equatable {
        let id: UUID
        var text: String
        var status: Status
        var outputURL: URL?
        var error: String?

        enum Status: String, Equatable {
            case pending, running, done, failed, cancelled
        }
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var currentIndex: Int? = nil
    @Published var lastError: String? = nil

    private var cancelRequested = false

    func setItems(_ texts: [String]) {
        items = texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { Item(id: UUID(), text: $0, status: .pending, outputURL: nil, error: nil) }
        cancelRequested = false
    }

    func cancel() {
        cancelRequested = true
        for idx in items.indices where items[idx].status == .pending {
            items[idx].status = .cancelled
        }
    }

    func clear() {
        guard !isRunning else { return }
        items.removeAll()
    }

    /// Run all pending items through the engine sequentially.
    func run(makeRequest: (String) -> SynthesisRequest,
             synthesize: (SynthesisRequest) async throws -> URL) async {
        guard !isRunning else { return }
        isRunning = true
        cancelRequested = false
        defer {
            isRunning = false
            currentIndex = nil
        }

        for idx in items.indices {
            if cancelRequested { break }
            guard items[idx].status == .pending else { continue }
            currentIndex = idx
            items[idx].status = .running
            do {
                let req = makeRequest(items[idx].text)
                let out = try await synthesize(req)
                items[idx].outputURL = out
                items[idx].status = .done
            } catch {
                items[idx].status = .failed
                items[idx].error = error.localizedDescription
                lastError = error.localizedDescription
            }
        }
    }
}
