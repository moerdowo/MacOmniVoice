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

    init(id: UUID = UUID(),
         name: String,
         description: String = "",
         referenceText: String = "",
         fileName: String,
         durationSeconds: Double = 0,
         byteSize: Int64 = 0,
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.description = description
        self.referenceText = referenceText
        self.fileName = fileName
        self.durationSeconds = durationSeconds
        self.byteSize = byteSize
        self.createdAt = createdAt
    }

    func fileURL(in clipsDir: URL) -> URL {
        clipsDir.appendingPathComponent(fileName)
    }
}
