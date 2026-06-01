import AVFoundation
import Foundation

struct ReferenceClip: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    var description: String
    /// Transcript of the audio, optional. Pre-filling this lets users
    /// skip Whisper auto-transcription at synthesis time.
    var referenceText: String
    /// File name inside the clips directory (we copy uploads in).
    var fileName: String
    /// Duration in seconds, cached at import time.
    var durationSeconds: Double
    /// Byte size on disk.
    var byteSize: Int64
    /// When the user added this clip.
    var createdAt: Date
    /// Free-form tags. Stored lowercased and deduped.
    var tags: [String]
    /// User-marked favourite.
    var isFavourite: Bool

    init(id: UUID = UUID(),
         name: String,
         description: String = "",
         referenceText: String = "",
         fileName: String,
         durationSeconds: Double = 0,
         byteSize: Int64 = 0,
         createdAt: Date = Date(),
         tags: [String] = [],
         isFavourite: Bool = false) {
        self.id = id
        self.name = name
        self.description = description
        self.referenceText = referenceText
        self.fileName = fileName
        self.durationSeconds = durationSeconds
        self.byteSize = byteSize
        self.createdAt = createdAt
        self.tags = Self.normalize(tags)
        self.isFavourite = isFavourite
    }

    /// Allow loading older library JSONs without tags / isFavourite.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.description = try c.decode(String.self, forKey: .description)
        self.referenceText = try c.decode(String.self, forKey: .referenceText)
        self.fileName = try c.decode(String.self, forKey: .fileName)
        self.durationSeconds = try c.decode(Double.self, forKey: .durationSeconds)
        self.byteSize = try c.decode(Int64.self, forKey: .byteSize)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.tags = Self.normalize((try? c.decode([String].self, forKey: .tags)) ?? [])
        self.isFavourite = (try? c.decode(Bool.self, forKey: .isFavourite)) ?? false
    }

    static func normalize(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for t in tags {
            let v = t.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if v.isEmpty { continue }
            if seen.insert(v).inserted { out.append(v) }
        }
        return out
    }

    func fileURL(in clipsDir: URL) -> URL {
        clipsDir.appendingPathComponent(fileName)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, referenceText, fileName, durationSeconds,
             byteSize, createdAt, tags, isFavourite
    }
}
