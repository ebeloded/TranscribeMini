import Foundation

final class WhisperStreamSession {
    var onUpdate: ((String) -> Void)?

    private let streamPath: String
    private let modelPath: String
    private let language: String

    private var process: Process?
    private var pollTimer: DispatchSourceTimer?
    private var outputURL: URL?

    private(set) var latestText = ""

    init(streamPath: String, modelPath: String, language: String) {
        self.streamPath = streamPath
        self.modelPath = modelPath
        self.language = language
    }

    deinit {
        stopProcessIfNeeded()
        pollTimer?.cancel()
    }

    func start() throws {
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("transcribe-mini-stream-\(UUID().uuidString).txt")
        self.outputURL = outputURL

        let process = Process()
        process.executableURL = URL(fileURLWithPath: streamPath)
        process.arguments = [
            "--model", modelPath,
            "--language", normalizedLanguage(language),
            "--file", outputURL.path,
            "--step", "800",
            "--length", "4000",
            "--keep", "200",
            "--keep-context"
        ]

        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        self.process = process

        startPollingOutputFile()
    }

    func stop() -> String {
        stopProcessIfNeeded()
        pollTimer?.cancel()
        pollTimer = nil

        let text = readLatestTextFromFile()

        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }

        return text
    }

    private func startPollingOutputFile() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now(), repeating: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let newText = self.readLatestTextFromFile()
            guard !newText.isEmpty, newText != self.latestText else { return }
            self.latestText = newText
            self.onUpdate?(newText)
        }
        timer.resume()
        self.pollTimer = timer
    }

    private func readLatestTextFromFile() -> String {
        guard let outputURL,
              let raw = try? String(contentsOf: outputURL, encoding: .utf8) else {
            return ""
        }

        return raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stopProcessIfNeeded() {
        guard let process else { return }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        self.process = nil
    }

    private func normalizedLanguage(_ value: String) -> String {
        let lower = value.lowercased()
        if let first = lower.split(separator: "-").first {
            return String(first)
        }
        return lower
    }
}
