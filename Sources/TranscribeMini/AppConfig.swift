import Foundation

enum Provider: String, Decodable {
    case apple
    case openai
    case groq
    case whispercpp

    var defaultEndpoint: String {
        switch self {
        case .openai:
            return "https://api.openai.com/v1/audio/transcriptions"
        case .groq:
            return "https://api.groq.com/openai/v1/audio/transcriptions"
        case .apple, .whispercpp:
            return ""
        }
    }
}

struct AppConfig: Decodable {
    var provider: Provider
    var apiKey: String
    var model: String
    var endpoint: String?
    var language: String?
    var whisperCLIPath: String?
    var whisperServerPath: String?
    var whisperServerHost: String
    var whisperServerPort: Int
    var whisperServerInferencePath: String
    var useWhisperServer: Bool

    static func load(
        from configURL: URL? = nil,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppConfig {
        let url = configURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".transcribe-mini.json")

        var merged = AppConfig(
            provider: .openai,
            apiKey: "",
            model: "gpt-4o-mini-transcribe",
            endpoint: nil,
            language: "en",
            whisperCLIPath: nil,
            whisperServerPath: nil,
            whisperServerHost: "127.0.0.1",
            whisperServerPort: 8178,
            whisperServerInferencePath: "/inference",
            useWhisperServer: true
        )

        if let data = try? Data(contentsOf: url),
           let fileConfig = try? JSONDecoder().decode(FileConfig.self, from: data) {
            if let provider = fileConfig.provider {
                merged.provider = provider
            }
            if let apiKey = fileConfig.apiKey {
                merged.apiKey = apiKey
            }
            if let model = fileConfig.model {
                merged.model = model
            }
            if let endpoint = fileConfig.endpoint {
                merged.endpoint = endpoint
            }
            if let language = fileConfig.language {
                merged.language = language
            }
            if let whisperCLIPath = fileConfig.whisperCLIPath {
                merged.whisperCLIPath = whisperCLIPath
            }
            if let whisperServerPath = fileConfig.whisperServerPath {
                merged.whisperServerPath = whisperServerPath
            }
            if let whisperServerHost = fileConfig.whisperServerHost, !whisperServerHost.isEmpty {
                merged.whisperServerHost = whisperServerHost
            }
            if let whisperServerPort = fileConfig.whisperServerPort {
                merged.whisperServerPort = whisperServerPort
            }
            if let whisperServerInferencePath = fileConfig.whisperServerInferencePath,
               !whisperServerInferencePath.isEmpty {
                merged.whisperServerInferencePath = whisperServerInferencePath
            }
            if let useWhisperServer = fileConfig.useWhisperServer {
                merged.useWhisperServer = useWhisperServer
            }
        }

        if let providerValue = env["TRANSCRIBE_PROVIDER"]?.lowercased(),
           let provider = Provider(rawValue: providerValue) {
            merged.provider = provider
        }

        if let model = env["TRANSCRIBE_MODEL"], !model.isEmpty {
            merged.model = model
        }
        if let endpoint = env["TRANSCRIBE_ENDPOINT"], !endpoint.isEmpty {
            merged.endpoint = endpoint
        }
        if let language = env["TRANSCRIBE_LANGUAGE"], !language.isEmpty {
            merged.language = language
        }
        if let whisperCLIPath = env["WHISPER_CLI_PATH"], !whisperCLIPath.isEmpty {
            merged.whisperCLIPath = whisperCLIPath
        }
        if let whisperServerPath = env["WHISPER_SERVER_PATH"], !whisperServerPath.isEmpty {
            merged.whisperServerPath = whisperServerPath
        }
        if let whisperServerHost = env["WHISPER_SERVER_HOST"], !whisperServerHost.isEmpty {
            merged.whisperServerHost = whisperServerHost
        }
        if let whisperServerPort = env["WHISPER_SERVER_PORT"], let value = Int(whisperServerPort) {
            merged.whisperServerPort = value
        }
        if let whisperServerInferencePath = env["WHISPER_SERVER_INFERENCE_PATH"], !whisperServerInferencePath.isEmpty {
            merged.whisperServerInferencePath = whisperServerInferencePath
        }
        if let useWhisperServer = env["TRANSCRIBE_USE_WHISPER_SERVER"]?.lowercased() {
            merged.useWhisperServer = ["1", "true", "yes", "on"].contains(useWhisperServer)
        }
        if let localModelPath = env["TRANSCRIBE_LOCAL_MODEL"], !localModelPath.isEmpty {
            merged.model = localModelPath
        }

        let envAPIKey = env["TRANSCRIBE_API_KEY"]
            ?? env["OPENAI_API_KEY"]
            ?? env["GROQ_API_KEY"]
        if let envAPIKey, !envAPIKey.isEmpty {
            merged.apiKey = envAPIKey
        }

        return merged
    }
}

private struct FileConfig: Decodable {
    let provider: Provider?
    let apiKey: String?
    let model: String?
    let endpoint: String?
    let language: String?
    let whisperCLIPath: String?
    let whisperServerPath: String?
    let whisperServerHost: String?
    let whisperServerPort: Int?
    let whisperServerInferencePath: String?
    let useWhisperServer: Bool?
}
