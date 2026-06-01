import Foundation

struct SynthesisRequest {
    var text: String
    var refAudioPath: String?
    var refText: String?
    var language: String?
    var instruct: String?
    var speed: Double
    var duration: Double?        // nil = auto
    var numStep: Int
    var guidanceScale: Double
    var denoise: Bool
    var postprocessOutput: Bool
    var preprocessPrompt: Bool
    var tShift: Double
    var layerPenaltyFactor: Double
    var positionTemperature: Double
    var classTemperature: Double

    /// Build the kwargs dictionary that the Python bridge forwards to
    /// `model.generate(**kwargs)`. Any keys not accepted by the installed
    /// version of the runtime are filtered out on the Python side.
    func toParams() -> [String: Any] {
        var params: [String: Any] = [
            "text": text,
            "speed": speed,
            "num_step": numStep,
            "guidance_scale": guidanceScale,
            "denoise": denoise,
            "postprocess_output": postprocessOutput,
            "preprocess_prompt": preprocessPrompt,
            "t_shift": tShift,
            "layer_penalty_factor": layerPenaltyFactor,
            "position_temperature": positionTemperature,
            "class_temperature": classTemperature,
        ]
        if let refAudioPath, !refAudioPath.isEmpty {
            params["ref_audio"] = refAudioPath
        }
        if let refText, !refText.isEmpty {
            params["ref_text"] = refText
        }
        if let language, !language.isEmpty {
            params["language"] = language
        }
        if let instruct, !instruct.isEmpty {
            params["instruct"] = instruct
        }
        if let duration, duration > 0 {
            params["duration"] = duration
        }
        return params
    }
}
