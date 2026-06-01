import Foundation

@MainActor
final class GenerationHistory: ObservableObject {
    @Published private(set) var records: [GenerationRecord] = []

    static let outputsDir: URL = {
        let url = PythonRuntime.appSupportDir.appendingPathComponent("outputs", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var indexURL: URL {
        PythonRuntime.appSupportDir.appendingPathComponent("generation-history.json")
    }

    /// Hard cap to keep the index small + the audio directory bounded.
    private let maxRecords: Int = 200

    init() {
        load()
    }

    func load() {
        let url = Self.indexURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var loaded = try decoder.decode([GenerationRecord].self, from: data)
            // Prune orphans
            loaded = loaded.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
            records = loaded
        } catch {
            records = []
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(records) {
            try? data.write(to: Self.indexURL, options: .atomic)
        }
    }

    func add(_ record: GenerationRecord) {
        records.insert(record, at: 0)
        // Trim trailing entries beyond the cap, and delete their files
        // so the outputs directory doesn't bloat forever.
        while records.count > maxRecords {
            if let dropped = records.popLast() {
                try? FileManager.default.removeItem(at: dropped.fileURL)
            }
        }
        save()
    }

    func delete(_ record: GenerationRecord) {
        try? FileManager.default.removeItem(at: record.fileURL)
        records.removeAll { $0.id == record.id }
        save()
    }

    func clear() {
        for r in records {
            try? FileManager.default.removeItem(at: r.fileURL)
        }
        records.removeAll()
        save()
    }
}
