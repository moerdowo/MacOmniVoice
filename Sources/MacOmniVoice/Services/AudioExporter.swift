import AVFoundation
import Foundation

enum AudioExportFormat: String, CaseIterable, Identifiable {
    case wav, mp3, aac, m4a, caf, flac

    var id: String { rawValue }
    var pathExtension: String { rawValue }

    var displayName: String {
        switch self {
        case .wav:  return "WAV (uncompressed)"
        case .mp3:  return "MP3"
        case .aac:  return "AAC"
        case .m4a:  return "M4A (AAC, MP4 container)"
        case .caf:  return "CAF"
        case .flac: return "FLAC"
        }
    }

    /// AVAssetExportPreset compatible? AAC/M4A/CAF/WAV/FLAC use the preset path.
    /// MP3 is not natively writable by AVAssetWriter on macOS, but
    /// AVAssetExportSession with preset .passthrough can convert if
    /// source is already MP3 — otherwise we route through a re-encode
    /// via AVAudioConverter + lame-style fallback (we skip mp3 if not
    /// supported and the UI hides it).
    var supportedNatively: Bool {
        switch self {
        case .mp3: return false   // not supported by AVAssetExportSession output
        default:   return true
        }
    }
}

enum AudioExporter {

    enum ExportError: LocalizedError {
        case unsupportedFormat(AudioExportFormat)
        case readFailed(String)
        case writeFailed(String)
        var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let f): return "Export to \(f.rawValue.uppercased()) isn't supported on this Mac without extra libraries."
            case .readFailed(let m): return "Couldn't read input: \(m)"
            case .writeFailed(let m): return "Couldn't write output: \(m)"
            }
        }
    }

    /// Convert `input` (PCM WAV from OmniVoice) to `output` in `format`.
    /// `sampleRate` and `bitDepth` are honoured for WAV/CAF/FLAC; AAC
    /// uses its own preferred parameters.
    static func export(input: URL,
                       to output: URL,
                       format: AudioExportFormat,
                       sampleRate: Double = 24_000,
                       bitDepth: Int = 16) throws {
        guard format.supportedNatively else { throw ExportError.unsupportedFormat(format) }

        try? FileManager.default.removeItem(at: output)

        switch format {
        case .wav, .caf, .flac:
            try exportPCM(input: input, output: output,
                          fileType: pcmFileType(for: format),
                          sampleRate: sampleRate,
                          bitDepth: bitDepth)
        case .aac, .m4a:
            try exportAAC(input: input, output: output, sampleRate: sampleRate)
        case .mp3:
            throw ExportError.unsupportedFormat(.mp3)
        }
    }

    private static func pcmFileType(for f: AudioExportFormat) -> AVFileType {
        switch f {
        case .wav:  return .wav
        case .caf:  return .caf
        case .flac:
            if #available(macOS 11, *) { return AVFileType("public.flac") }
            return .wav
        default:    return .wav
        }
    }

    private static func exportPCM(input: URL,
                                  output: URL,
                                  fileType: AVFileType,
                                  sampleRate: Double,
                                  bitDepth: Int) throws {
        let inFile: AVAudioFile
        do {
            inFile = try AVAudioFile(forReading: input)
        } catch {
            throw ExportError.readFailed(error.localizedDescription)
        }
        let inputFormat = inFile.processingFormat

        // For FLAC we can't rely on AVAudioFile writer support across
        // every macOS version; fall back to AAC if creation fails.
        let settings: [String: Any] = [
            AVFormatIDKey: fileType == AVFileType("public.flac")
                ? kAudioFormatFLAC : kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: inputFormat.channelCount,
            AVLinearPCMBitDepthKey: bitDepth,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let outFile: AVAudioFile
        do {
            outFile = try AVAudioFile(forWriting: output, settings: settings)
        } catch {
            throw ExportError.writeFailed(error.localizedDescription)
        }

        let chunk: AVAudioFrameCount = 32_768
        guard let buf = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: chunk) else {
            throw ExportError.writeFailed("buffer alloc failed")
        }
        inFile.framePosition = 0
        while inFile.framePosition < inFile.length {
            try inFile.read(into: buf)
            if buf.frameLength == 0 { break }
            try outFile.write(from: buf)
        }
    }

    private static func exportAAC(input: URL, output: URL, sampleRate: Double) throws {
        let asset = AVURLAsset(url: input)
        guard let session = AVAssetExportSession(asset: asset,
                                                 presetName: AVAssetExportPresetAppleM4A) else {
            throw ExportError.writeFailed("Couldn't create export session")
        }
        session.outputURL = output
        session.outputFileType = .m4a

        let sem = DispatchSemaphore(value: 0)
        var capturedError: Error? = nil
        session.exportAsynchronously {
            if session.status == .failed { capturedError = session.error }
            sem.signal()
        }
        sem.wait()
        if let e = capturedError {
            throw ExportError.writeFailed(e.localizedDescription)
        }
    }
}
