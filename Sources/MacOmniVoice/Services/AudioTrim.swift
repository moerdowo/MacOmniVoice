import AVFoundation
import Foundation

enum AudioTrim {
    enum TrimError: LocalizedError {
        case readFailed(String)
        case writeFailed(String)
        case badRange
        var errorDescription: String? {
            switch self {
            case .readFailed(let m): return "Couldn't read input: \(m)"
            case .writeFailed(let m): return "Couldn't write output: \(m)"
            case .badRange: return "Trim range is empty."
            }
        }
    }

    /// Crop `input` to [startSec, endSec) and write a new WAV at `output`.
    /// Output is always interleaved 16-bit PCM at the source sample rate.
    static func trim(input: URL, to output: URL,
                     startSec: Double, endSec: Double) throws {
        guard endSec > startSec else { throw TrimError.badRange }

        let inFile: AVAudioFile
        do {
            inFile = try AVAudioFile(forReading: input)
        } catch {
            throw TrimError.readFailed(error.localizedDescription)
        }
        let inputFormat = inFile.processingFormat
        let sampleRate = inputFormat.sampleRate

        let startFrame = AVAudioFramePosition(max(0, startSec * sampleRate))
        let endFrame = AVAudioFramePosition(min(Double(inFile.length), endSec * sampleRate))
        if endFrame <= startFrame { throw TrimError.badRange }

        try? FileManager.default.removeItem(at: output)
        let outSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: inputFormat.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let outFile: AVAudioFile
        do {
            outFile = try AVAudioFile(forWriting: output, settings: outSettings)
        } catch {
            throw TrimError.writeFailed(error.localizedDescription)
        }

        inFile.framePosition = startFrame
        let chunk: AVAudioFrameCount = 32_768
        guard let buf = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: chunk) else {
            throw TrimError.writeFailed("buffer alloc failed")
        }
        var remaining = AVAudioFrameCount(endFrame - startFrame)
        while remaining > 0 {
            buf.frameLength = 0
            let toRead = min(chunk, remaining)
            try inFile.read(into: buf, frameCount: toRead)
            if buf.frameLength == 0 { break }
            try outFile.write(from: buf)
            remaining = remaining > buf.frameLength ? remaining - buf.frameLength : 0
        }
    }
}
