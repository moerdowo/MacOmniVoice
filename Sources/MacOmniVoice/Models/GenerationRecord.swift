import Foundation

struct GenerationRecord: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var createdAt: Date
    var text: String
    var fileName: String          // inside the outputs dir
    var elapsed: Double
    var sampleRate: Int

    // Reproduce-ability — every knob that mattered.
    var refClipID: UUID?          // when sourced from the library
    var refClipName: String?
    var refAudioOriginalPath: String?
    var refText: String?
    var language: String?
    var instruct: String?
    var speed: Double
    var duration: Double?
    var numStep: Int
    var guidanceScale: Double
    var denoise: Bool
    var postprocessOutput: Bool
    var preprocessPrompt: Bool
    var tShift: Double
    var layerPenaltyFactor: Double
    var positionTemperature: Double
    var classTemperature: Double
    var device: String?

    init(id: UUID = UUID(),
         createdAt: Date = Date(),
         text: String,
         fileName: String,
         elapsed: Double,
         sampleRate: Int = 24_000,
         refClipID: UUID? = nil,
         refClipName: String? = nil,
         refAudioOriginalPath: String? = nil,
         refText: String? = nil,
         language: String? = nil,
         instruct: String? = nil,
         speed: Double = 1.0,
         duration: Double? = nil,
         numStep: Int = 16,
         guidanceScale: Double = 2.0,
         denoise: Bool = true,
         postprocessOutput: Bool = true,
         preprocessPrompt: Bool = true,
         tShift: Double = 0.1,
         layerPenaltyFactor: Double = 5.0,
         positionTemperature: Double = 5.0,
         classTemperature: Double = 0.0,
         device: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.fileName = fileName
        self.elapsed = elapsed
        self.sampleRate = sampleRate
        self.refClipID = refClipID
        self.refClipName = refClipName
        self.refAudioOriginalPath = refAudioOriginalPath
        self.refText = refText
        self.language = language
        self.instruct = instruct
        self.speed = speed
        self.duration = duration
        self.numStep = numStep
        self.guidanceScale = guidanceScale
        self.denoise = denoise
        self.postprocessOutput = postprocessOutput
        self.preprocessPrompt = preprocessPrompt
        self.tShift = tShift
        self.layerPenaltyFactor = layerPenaltyFactor
        self.positionTemperature = positionTemperature
        self.classTemperature = classTemperature
        self.device = device
    }

    var fileURL: URL {
        GenerationHistory.outputsDir.appendingPathComponent(fileName)
    }
}
