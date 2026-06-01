import AVFoundation
import Foundation

/// Sample-accurate concatenation of multiple PCM WAVs into a single
/// output WAV, with an optional silence gap between chunks. All inputs
/// must share the same format (which they will when they all come from
/// the OmniVoice runner at 24 kHz mono).
enum AudioConcat {

    enum ConcatError: LocalizedError {
        case noInputs
        case openFailed(URL, String)
        case writeFailed(String)
        case formatMismatch
        var errorDescription: String? {
            switch self {
            case .noInputs: return "Nothing to concatenate."
            case .openFailed(let u, let m): return "Couldn't open \(u.lastPathComponent): \(m)"
            case .writeFailed(let m): return "Couldn't write output: \(m)"
            case .formatMismatch: return "Audio chunks have different formats."
            }
        }
    }

    /// Concatenate `urls` into `out`. `silenceSeconds` between each chunk.
    static func concat(_ urls: [URL], into out: URL, silenceSeconds: Double = 0.25) throws {
        guard !urls.isEmpty else { throw ConcatError.noInputs }
        if urls.count == 1 {
            try? FileManager.default.removeItem(at: out)
            try FileManager.default.copyItem(at: urls[0], to: out)
            return
        }

        // Open the first to discover the format.
        let firstFile: AVAudioFile
        do {
            firstFile = try AVAudioFile(forReading: urls[0])
        } catch {
            throw ConcatError.openFailed(urls[0], error.localizedDescription)
        }
        let format = firstFile.processingFormat

        // Output is an interleaved Int16 WAV at the same sample rate.
        let outSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        try? FileManager.default.removeItem(at: out)
        let outFile: AVAudioFile
        do {
            outFile = try AVAudioFile(forWriting: out, settings: outSettings)
        } catch {
            throw ConcatError.writeFailed(error.localizedDescription)
        }

        let silenceFrames = AVAudioFrameCount(silenceSeconds * format.sampleRate)
        let silenceBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(1, silenceFrames))
        silenceBuf?.frameLength = silenceFrames

        try writeFile(firstFile, into: outFile)

        for (idx, url) in urls.enumerated() {
            if idx == 0 { continue }
            if silenceFrames > 0, let buf = silenceBuf {
                try outFile.write(from: buf)
            }
            let file: AVAudioFile
            do {
                file = try AVAudioFile(forReading: url)
            } catch {
                throw ConcatError.openFailed(url, error.localizedDescription)
            }
            guard file.processingFormat.sampleRate == format.sampleRate,
                  file.processingFormat.channelCount == format.channelCount else {
                throw ConcatError.formatMismatch
            }
            try writeFile(file, into: outFile)
        }
    }

    private static func writeFile(_ file: AVAudioFile, into out: AVAudioFile) throws {
        let format = file.processingFormat
        let bufSize: AVAudioFrameCount = 32_768
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufSize) else {
            throw ConcatError.writeFailed("could not allocate read buffer")
        }
        file.framePosition = 0
        while file.framePosition < file.length {
            try file.read(into: buf)
            if buf.frameLength == 0 { break }
            try out.write(from: buf)
        }
    }
}
