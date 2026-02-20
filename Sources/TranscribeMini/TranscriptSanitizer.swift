import Foundation

enum TranscriptSanitizer {
    static func sanitizeForPaste(_ transcript: String) -> String? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?"))
            .lowercased()

        if normalized == "[blank_audio]"
            || normalized == "[silence]"
            || normalized == "(silence)" {
            return nil
        }

        return trimmed
    }
}
