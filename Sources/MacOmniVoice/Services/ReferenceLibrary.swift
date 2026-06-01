import AVFoundation
import Combine
import Foundation

/// Persisted library of named reference audio clips.
/// Files live under ~/Library/Application Support/MacOmniVoice/refs/,
/// metadata is a single JSON file alongside.
@MainActor
final class ReferenceLibrary: ObservableObject {
    @Published private(set) var clips: [ReferenceClip] = []
    @Published var lastError: String? = nil

    static let clipsDir: URL = {
        let dir = PythonRuntime.appSupportDir
            .appendingPathComponent("refs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var indexURL: URL {
        PythonRuntime.appSupportDir.appendingPathComponent("ref-library.json")
    }

    init() {
        load()
    }

    func fileURL(for clip: ReferenceClip) -> URL {
        clip.fileURL(in: Self.clipsDir)
    }

    // MARK: - Persistence

    func load() {
        let url = Self.indexURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            clips = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            clips = try decoder.decode([ReferenceClip].self, from: data)
            // Drop entries whose files no longer exist.
            clips = clips.filter { FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
        } catch {
            lastError = "Failed to load reference library: \(error.localizedDescription)"
            clips = []
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(clips)
            try data.write(to: Self.indexURL, options: .atomic)
        } catch {
            lastError = "Failed to save reference library: \(error.localizedDescription)"
        }
    }

    // MARK: - Mutations

    /// Copies the source audio into the library's clips directory and adds
    /// a metadata entry. Returns the created clip.
    @discardableResult
    func importFile(from source: URL,
                    name: String,
                    description: String = "",
                    referenceText: String = "",
                    tags: [String] = []) throws -> ReferenceClip {
        let fm = FileManager.default
        let ext = source.pathExtension.isEmpty ? "wav" : source.pathExtension.lowercased()
        let id = UUID()
        let fileName = "\(id.uuidString).\(ext)"
        let dst = Self.clipsDir.appendingPathComponent(fileName)

        // If the source is in the recorder's directory (or anywhere
        // already inside our app support tree), copy — don't move.
        try fm.copyItem(at: source, to: dst)

        let durationSeconds: Double = {
            let asset = AVURLAsset(url: dst)
            return CMTimeGetSeconds(asset.duration)
        }()
        let byteSize: Int64 = {
            (try? fm.attributesOfItem(atPath: dst.path)[.size] as? Int64) ?? 0
        }()

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let clip = ReferenceClip(
            id: id,
            name: trimmedName.isEmpty ? source.deletingPathExtension().lastPathComponent : trimmedName,
            description: description,
            referenceText: referenceText,
            fileName: fileName,
            durationSeconds: durationSeconds.isFinite ? durationSeconds : 0,
            byteSize: byteSize,
            tags: tags
        )
        clips.insert(clip, at: 0)
        save()
        return clip
    }

    func update(_ updated: ReferenceClip) {
        guard let idx = clips.firstIndex(where: { $0.id == updated.id }) else { return }
        var u = updated
        u.tags = ReferenceClip.normalize(u.tags)
        clips[idx] = u
        save()
    }

    func toggleFavourite(_ clip: ReferenceClip) {
        var c = clip
        c.isFavourite.toggle()
        update(c)
    }

    /// All tags currently in the library, sorted by frequency desc.
    var allTags: [(String, Int)] {
        var counts: [String: Int] = [:]
        for c in clips { for t in c.tags { counts[t, default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
    }

    /// Replace the file behind a clip (used after trim). Keeps the same
    /// id so history references stay valid.
    func replaceFile(of clip: ReferenceClip, with newFile: URL) throws {
        let dst = fileURL(for: clip)
        if FileManager.default.fileExists(atPath: dst.path) {
            try FileManager.default.removeItem(at: dst)
        }
        try FileManager.default.moveItem(at: newFile, to: dst)
        // Recompute duration + size
        let dur: Double = {
            let asset = AVURLAsset(url: dst)
            let s = CMTimeGetSeconds(asset.duration)
            return s.isFinite ? s : clip.durationSeconds
        }()
        let size: Int64 = (try? FileManager.default.attributesOfItem(atPath: dst.path)[.size] as? Int64) ?? clip.byteSize
        var c = clip
        c.durationSeconds = dur
        c.byteSize = size
        update(c)
    }

    func delete(_ clip: ReferenceClip) {
        let url = fileURL(for: clip)
        try? FileManager.default.removeItem(at: url)
        clips.removeAll { $0.id == clip.id }
        save()
    }

    func clip(withId id: UUID) -> ReferenceClip? {
        clips.first { $0.id == id }
    }
}
