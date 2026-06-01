import AVFoundation
import Combine
import Foundation

/// Records a mono 24 kHz WAV to disk — matches OmniVoice's expected
/// reference-audio sample rate so no resample is needed on the Python side.
@MainActor
final class AudioRecorderService: NSObject, ObservableObject {

    enum RecorderError: LocalizedError {
        case permissionDenied
        case setupFailed(String)
        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Microphone access denied. Enable it in System Settings → Privacy & Security → Microphone."
            case .setupFailed(let m):
                return "Could not start recording: \(m)"
            }
        }
    }

    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var level: Float = 0          // 0…1 normalised
    @Published var currentURL: URL? = nil

    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    /// Asks the OS for mic permission if not yet decided.
    func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    cont.resume(returning: granted)
                }
            }
        @unknown default: return false
        }
    }

    /// Returns the file URL being written to.
    @discardableResult
    func start() async throws -> URL {
        guard await requestPermission() else { throw RecorderError.permissionDenied }

        let dir = PythonRuntime.appSupportDir
            .appendingPathComponent("recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let ts = ISO8601DateFormatter()
        ts.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        let stamp = ts.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let url = dir.appendingPathComponent("ref-\(stamp).wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 24_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]

        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.isMeteringEnabled = true
            rec.delegate = self
            guard rec.prepareToRecord(), rec.record() else {
                throw RecorderError.setupFailed("prepareToRecord/record returned false")
            }
            self.recorder = rec
            self.currentURL = url
            self.isRecording = true
            self.elapsed = 0
            self.level = 0
            startTimer()
            return url
        } catch let e as RecorderError {
            throw e
        } catch {
            throw RecorderError.setupFailed(error.localizedDescription)
        }
    }

    /// Stop and finalise the file. Returns the recorded URL.
    @discardableResult
    func stop() -> URL? {
        guard let rec = recorder, rec.isRecording else { return currentURL }
        let url = rec.url
        rec.stop()
        recorder = nil
        isRecording = false
        stopTimer()
        currentURL = url
        return url
    }

    /// Stop and discard the file.
    func cancel() {
        guard let rec = recorder else { return }
        let url = rec.url
        rec.stop()
        recorder = nil
        isRecording = false
        stopTimer()
        try? FileManager.default.removeItem(at: url)
        currentURL = nil
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let rec = self.recorder else { return }
                self.elapsed = rec.currentTime
                rec.updateMeters()
                // averagePower is in dBFS, [-160 … 0]. Map roughly to [0 … 1].
                let db = rec.averagePower(forChannel: 0)
                let clamped = max(-50, min(0, db))
                self.level = pow(10, clamped / 20)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

extension AudioRecorderService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            self.isRecording = false
            self.stopTimer()
        }
    }
}
