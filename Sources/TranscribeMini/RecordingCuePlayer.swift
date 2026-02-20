import AppKit
import AVFoundation

final class RecordingCuePlayer {
    private let startCuePlayer: AVAudioPlayer?
    private let stopCuePlayer: AVAudioPlayer?

    init() {
        startCuePlayer = Self.makeBundledPlayer(named: "dictation-start")
        stopCuePlayer = Self.makeBundledPlayer(named: "dictation-stop")
        tmLog("[TranscribeMini] Cue start source=\(startCuePlayer != nil ? "bundle" : "missing")")
        tmLog("[TranscribeMini] Cue stop source=\(stopCuePlayer != nil ? "bundle" : "missing")")
        prewarm()
    }

    func playStartCue() {
        play(player: startCuePlayer)
    }

    func playStopCue() {
        play(player: stopCuePlayer)
    }

    private func play(player: AVAudioPlayer?) {
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }

    private func prewarm() {
        startCuePlayer?.prepareToPlay()
        stopCuePlayer?.prepareToPlay()
    }

    private static func makeBundledPlayer(named name: String) -> AVAudioPlayer? {
        guard let url = bundledCueURL(named: name) else {
            tmLog("[TranscribeMini] Cue file not found in bundle: \(name).wav")
            return nil
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.5
            return player
        } catch {
            tmLog("[TranscribeMini] Failed to load cue \(name).wav: \(error.localizedDescription)")
            return nil
        }
    }

    private static func bundledCueURL(named name: String) -> URL? {
        if let url = Bundle.module.url(
            forResource: name,
            withExtension: "wav",
            subdirectory: "Sounds"
        ) {
            return url
        }

        if let url = Bundle.module.url(
            forResource: name,
            withExtension: "wav"
        ) {
            return url
        }

        // Last-resort scan for environments where SwiftPM changes resource layout.
        if let resourceURL = Bundle.module.resourceURL,
           let enumerator = FileManager.default.enumerator(
               at: resourceURL,
               includingPropertiesForKeys: nil
           ) {
            for case let fileURL as URL in enumerator where fileURL.lastPathComponent == "\(name).wav" {
                return fileURL
            }
        }

        return nil
    }
}
