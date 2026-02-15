import Foundation
import Speech

protocol Transcriber {
    @MainActor
    func transcribe(audioURL: URL) async throws -> String
}

enum TranscriberFactory {
    static func make(config: AppConfig) -> any Transcriber {
        switch config.provider {
        case .apple:
            return AppleSpeechTranscriber(localeIdentifier: config.language)
        case .openai, .groq:
            let endpoint = config.endpoint ?? config.provider.defaultEndpoint
            return OpenAICompatibleTranscriber(
                endpoint: endpoint,
                apiKey: config.apiKey,
                model: config.model,
                language: config.language
            )
        case .whispercpp:
            if config.useWhisperServer {
                let host = config.whisperServerHost
                let port = config.whisperServerPort
                let path = normalizedServerPath(config.whisperServerInferencePath)
                let endpoint = "http://\(host):\(port)\(path)"

                return WhisperServerTranscriber(
                    endpoint: endpoint,
                    serverPath: config.whisperServerPath ?? "/opt/homebrew/bin/whisper-server",
                    modelPath: config.model,
                    language: config.language ?? "en"
                )
            } else {
                return WhisperCPPTranscriber(
                    cliPath: config.whisperCLIPath ?? "/opt/homebrew/bin/whisper-cli",
                    modelPath: config.model,
                    language: config.language ?? "en"
                )
            }
        }
    }
}

final class AppleSpeechTranscriber: Transcriber {
    private let localeIdentifier: String

    init(localeIdentifier: String?) {
        self.localeIdentifier = localeIdentifier ?? "en-US"
    }

    func transcribe(audioURL: URL) async throws -> String {
        try await authorizeIfNeeded()

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
            throw NSError(domain: "AppleSpeechTranscriber", code: 1)
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            _ = recognizer.recognitionTask(with: request) { result, error in
                if finished { return }

                if let error {
                    finished = true
                    continuation.resume(throwing: error)
                    return
                }

                guard let result else { return }
                if result.isFinal {
                    finished = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    @MainActor
    private func authorizeIfNeeded() async throws {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return
        case .notDetermined:
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard status == .authorized else {
                throw NSError(domain: "AppleSpeechTranscriber", code: 2)
            }
        default:
            throw NSError(domain: "AppleSpeechTranscriber", code: 3)
        }
    }
}

final class OpenAICompatibleTranscriber: Transcriber {
    private let endpoint: String
    private let apiKey: String
    private let model: String
    private let language: String?

    init(endpoint: String, apiKey: String, model: String, language: String?) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
        self.language = language
    }

    func transcribe(audioURL: URL) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioURL)
        let mimeType = mimeTypeForAudioFile(url: audioURL)
        let body = MultipartFormBuilder.makeTranscriptionBody(
            boundary: boundary,
            model: model,
            language: language,
            filename: audioURL.lastPathComponent,
            audioData: audioData,
            mimeType: mimeType
        )

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Transcription failed"
            throw NSError(domain: "OpenAICompatibleTranscriber", code: 4, userInfo: [NSLocalizedDescriptionKey: message])
        }

        let decoded = try JSONDecoder().decode(OpenAITranscriptionResponse.self, from: data)
        return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class WhisperCPPTranscriber: Transcriber {
    private let cliPath: String
    private let modelPath: String
    private let language: String

    init(cliPath: String, modelPath: String, language: String) {
        self.cliPath = cliPath
        self.modelPath = modelPath
        self.language = language
    }

    func transcribe(audioURL: URL) async throws -> String {
        let outputBase = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("transcribe-mini-\(UUID().uuidString)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = [
            "--model", modelPath,
            "--language", language,
            "--output-txt",
            "--output-file", outputBase.path,
            "--no-prints",
            "--file", audioURL.path
        ]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errData, encoding: .utf8) ?? "whisper-cli failed"
            throw NSError(domain: "WhisperCPPTranscriber", code: 5, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        let txtURL = URL(fileURLWithPath: "\(outputBase.path).txt")
        defer { try? FileManager.default.removeItem(at: txtURL) }

        let transcript = try String(contentsOf: txtURL, encoding: .utf8)
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class WhisperServerTranscriber: Transcriber {
    private let endpoint: String
    private let serverPath: String
    private let modelPath: String
    private let language: String
    private let manager: WhisperServerManager

    init(
        endpoint: String,
        serverPath: String,
        modelPath: String,
        language: String,
        manager: WhisperServerManager = .shared
    ) {
        self.endpoint = endpoint
        self.serverPath = serverPath
        self.modelPath = modelPath
        self.language = language
        self.manager = manager
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let url = URL(string: endpoint), let host = url.host, let port = url.port else {
            throw NSError(domain: "WhisperServerTranscriber", code: 30, userInfo: [
                NSLocalizedDescriptionKey: "Invalid whisper-server endpoint"
            ])
        }

        try await manager.ensureRunning(
            serverPath: serverPath,
            modelPath: modelPath,
            host: host,
            port: port
        )

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioURL)
        let mimeType = mimeTypeForAudioFile(url: audioURL)
        let body = MultipartFormBuilder.makeWhisperServerBody(
            boundary: boundary,
            language: language,
            filename: audioURL.lastPathComponent,
            audioData: audioData,
            mimeType: mimeType
        )

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Whisper server transcription failed"
            throw NSError(domain: "WhisperServerTranscriber", code: 31, userInfo: [NSLocalizedDescriptionKey: message])
        }

        let decoded = try JSONDecoder().decode(OpenAITranscriptionResponse.self, from: data)
        return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct OpenAITranscriptionResponse: Decodable {
    let text: String
}

enum MultipartFormBuilder {
    static func makeTranscriptionBody(
        boundary: String,
        model: String,
        language: String?,
        filename: String,
        audioData: Data,
        mimeType: String
    ) -> Data {
        var body = Data()
        body.appendMultipartField(name: "model", value: model, boundary: boundary)
        if let language, !language.isEmpty {
            body.appendMultipartField(name: "language", value: language, boundary: boundary)
        }
        body.appendMultipartFile(
            name: "file",
            filename: filename,
            mimeType: mimeType,
            data: audioData,
            boundary: boundary
        )
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    static func makeWhisperServerBody(
        boundary: String,
        language: String,
        filename: String,
        audioData: Data,
        mimeType: String
    ) -> Data {
        var body = Data()
        body.appendMultipartField(name: "language", value: language, boundary: boundary)
        body.appendMultipartField(name: "response_format", value: "json", boundary: boundary)
        body.appendMultipartField(name: "temperature", value: "0.0", boundary: boundary)
        body.appendMultipartFile(
            name: "file",
            filename: filename,
            mimeType: mimeType,
            data: audioData,
            boundary: boundary
        )
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}

private func normalizedServerPath(_ path: String) -> String {
    path.hasPrefix("/") ? path : "/\(path)"
}

private func mimeTypeForAudioFile(url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "wav":
        return "audio/wav"
    case "mp3":
        return "audio/mpeg"
    case "ogg":
        return "audio/ogg"
    case "m4a":
        return "audio/m4a"
    case "flac":
        return "audio/flac"
    default:
        return "application/octet-stream"
    }
}

private extension Data {
    mutating func appendMultipartFile(name: String, filename: String, mimeType: String, data: Data, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }
}
