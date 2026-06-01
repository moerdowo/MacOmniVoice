import Foundation
import Combine
import SwiftUI

/// Persisted user preferences for synthesis defaults. Uses Combine sinks
/// to mirror @Published properties into UserDefaults — works reliably
/// inside a non-view ObservableObject (unlike @AppStorage).
final class AppSettings: ObservableObject {
    @Published var modelId: String
    @Published var language: String
    @Published var instruct: String
    @Published var speed: Double
    @Published var duration: Double               // 0 = auto
    @Published var numStep: Int
    @Published var guidanceScale: Double
    @Published var denoise: Bool
    @Published var postprocessOutput: Bool
    @Published var preprocessPrompt: Bool
    @Published var tShift: Double
    @Published var layerPenaltyFactor: Double
    @Published var positionTemperature: Double
    @Published var classTemperature: Double
    @Published var deviceOverride: String          // "", "mps", "cpu"
    @Published var autoCheckUpdates: Bool

    private var bag: Set<AnyCancellable> = []

    init() {
        let d = UserDefaults.standard
        modelId            = d.string(forKey: "modelId") ?? "k2-fsa/OmniVoice"
        language           = d.string(forKey: "language") ?? ""
        instruct           = d.string(forKey: "instruct") ?? ""
        speed              = d.object(forKey: "speed") as? Double ?? 1.0
        duration           = d.object(forKey: "duration") as? Double ?? 0
        numStep            = d.object(forKey: "numStep") as? Int ?? 32
        guidanceScale      = d.object(forKey: "guidanceScale") as? Double ?? 2.0
        denoise            = d.object(forKey: "denoise") as? Bool ?? true
        postprocessOutput  = d.object(forKey: "postprocessOutput") as? Bool ?? true
        preprocessPrompt   = d.object(forKey: "preprocessPrompt") as? Bool ?? true
        tShift             = d.object(forKey: "tShift") as? Double ?? 0.1
        layerPenaltyFactor = d.object(forKey: "layerPenaltyFactor") as? Double ?? 5.0
        positionTemperature = d.object(forKey: "positionTemperature") as? Double ?? 5.0
        classTemperature   = d.object(forKey: "classTemperature") as? Double ?? 0.0
        deviceOverride     = d.string(forKey: "deviceOverride") ?? ""
        autoCheckUpdates   = d.object(forKey: "autoCheckUpdates") as? Bool ?? true

        wire($modelId, "modelId")
        wire($language, "language")
        wire($instruct, "instruct")
        wire($speed, "speed")
        wire($duration, "duration")
        wire($numStep, "numStep")
        wire($guidanceScale, "guidanceScale")
        wire($denoise, "denoise")
        wire($postprocessOutput, "postprocessOutput")
        wire($preprocessPrompt, "preprocessPrompt")
        wire($tShift, "tShift")
        wire($layerPenaltyFactor, "layerPenaltyFactor")
        wire($positionTemperature, "positionTemperature")
        wire($classTemperature, "classTemperature")
        wire($deviceOverride, "deviceOverride")
        wire($autoCheckUpdates, "autoCheckUpdates")
    }

    private func wire<P: Publisher>(_ publisher: P, _ key: String)
    where P.Failure == Never {
        publisher
            .dropFirst()
            .sink { v in UserDefaults.standard.set(v, forKey: key) }
            .store(in: &bag)
    }
}
