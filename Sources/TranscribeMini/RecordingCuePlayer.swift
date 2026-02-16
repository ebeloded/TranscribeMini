import AppKit

final class RecordingCuePlayer {
    private let startCueSound: NSSound?
    private let stopCueSound: NSSound?

    init() {
        startCueSound = Self.loadSound(namedAnyOf: ["Pop", "Morse"])
        stopCueSound = Self.loadSound(namedAnyOf: ["Bottle", "Glass", "Ping"])
        startCueSound?.volume = 0.6
        stopCueSound?.volume = 0.6
    }

    func playStartCue() {
        play(sound: startCueSound)
    }

    func playStopCue() {
        play(sound: stopCueSound)
    }

    private func play(sound: NSSound?) {
        guard let sound else {
            NSSound.beep()
            return
        }
        sound.stop()
        sound.play()
    }

    private static func loadSound(namedAnyOf names: [String]) -> NSSound? {
        for name in names {
            if let sound = NSSound(named: NSSound.Name(name)) {
                return sound
            }
        }
        return nil
    }
}
