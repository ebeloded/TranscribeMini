import AVFoundation
import Foundation

enum RecorderError: Error {
    case startFailed
}

final class HoldToTalkRecorder {
    private var recorder: AVAudioRecorder?
    private var currentURL: URL?

    func start() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("transcribe-mini-\(UUID().uuidString).wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw RecorderError.startFailed
        }

        self.recorder = recorder
        self.currentURL = url
    }

    func stop() -> URL? {
        recorder?.stop()
        recorder = nil
        defer { currentURL = nil }
        return currentURL
    }
}
