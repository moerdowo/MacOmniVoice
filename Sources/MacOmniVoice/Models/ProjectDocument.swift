import Foundation

/// On-disk representation of a saved synthesis project. Plain JSON.
struct ProjectDocument: Codable, Equatable {
    var schemaVersion: Int = 1
    var savedAt: Date = Date()
    var text: String
    var refClipID: UUID?
    var refClipName: String?
    var refAudioPath: String?
    var refText: String?

    // Settings snapshot
    var modelId: String
    var language: String
    var instruct: String
    var speed: Double
    var duration: Double
    var numStep: Int
    var guidanceScale: Double
    var denoise: Bool
    var postprocessOutput: Bool
    var preprocessPrompt: Bool
    var tShift: Double
    var layerPenaltyFactor: Double
    var positionTemperature: Double
    var classTemperature: Double
    var deviceOverride: String

    static let pathExtension = "omnivoice"
}
