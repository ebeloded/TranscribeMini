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
    var activeProfileName: String? = nil

    static func load(
        from configURL: URL? = nil,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppConfig {
        let isDefaultPath = configURL == nil
        let url = configURL ?? defaultConfigURL
        if isDefaultPath {
            migrateLegacyConfigIfNeeded()
            ensureConfigExists(at: url)
        }

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
            useWhisperServer: true,
            activeProfileName: nil
        )

        if let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            if let profilesConfig = try? decoder.decode(ProfilesFileConfig.self, from: data),
               let profiles = profilesConfig.profiles,
               !profiles.isEmpty {
                let requestedProfile = env["TRANSCRIBE_PROFILE"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                let requestedProfileName = requestedProfile?.isEmpty == false ? requestedProfile : nil
                let sortedProfileNames = profiles.keys.sorted()

                var selectedProfileName: String?

                if let requestedProfileName {
                    if profiles[requestedProfileName] != nil {
                        selectedProfileName = requestedProfileName
                    } else {
                        tmLog("[TranscribeMini] Warning: TRANSCRIBE_PROFILE='\(requestedProfileName)' not found. Falling back.")
                    }
                }

                if selectedProfileName == nil, let defaultProfile = profilesConfig.defaultProfile {
                    if profiles[defaultProfile] != nil {
                        selectedProfileName = defaultProfile
                    } else {
                        tmLog("[TranscribeMini] Warning: defaultProfile='\(defaultProfile)' not found. Falling back.")
                    }
                }

                if selectedProfileName == nil {
                    selectedProfileName = sortedProfileNames.first
                }

                if let selectedProfileName, let selectedProfile = profiles[selectedProfileName] {
                    merged.apply(profile: selectedProfile)
                    merged.activeProfileName = selectedProfileName
                }
            } else {
                tmLog("[TranscribeMini] Warning: Config file must include non-empty 'profiles'. Using defaults/env only.")
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

        let providerScopedAPIKey: String?
        switch merged.provider {
        case .openai:
            providerScopedAPIKey = env["TRANSCRIBE_OPENAI_API_KEY"] ?? env["OPENAI_API_KEY"]
        case .groq:
            providerScopedAPIKey = env["TRANSCRIBE_GROQ_API_KEY"] ?? env["GROQ_API_KEY"]
        case .apple, .whispercpp:
            providerScopedAPIKey = nil
        }

        let envAPIKey = env["TRANSCRIBE_API_KEY"]
            ?? providerScopedAPIKey
            ?? env["TRANSCRIBE_OPENAI_API_KEY"]
            ?? env["OPENAI_API_KEY"]
            ?? env["TRANSCRIBE_GROQ_API_KEY"]
            ?? env["GROQ_API_KEY"]
        if let envAPIKey, !envAPIKey.isEmpty {
            merged.apiKey = envAPIKey
        }

        return merged
    }

    static var defaultConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("transcribe-mini")
            .appendingPathComponent("config.json")
    }

    static func availableProfiles(from configURL: URL? = nil) -> [String] {
        let url = configURL ?? defaultConfigURL
        guard let data = try? Data(contentsOf: url),
              let profilesConfig = try? JSONDecoder().decode(ProfilesFileConfig.self, from: data),
              let profiles = profilesConfig.profiles else {
            return []
        }
        return profiles.keys.sorted()
    }

    private static var legacyConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".transcribe-mini")
            .appendingPathComponent("config.json")
    }

    private static func migrateLegacyConfigIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: defaultConfigURL.path),
              fm.fileExists(atPath: legacyConfigURL.path) else {
            return
        }

        let parent = defaultConfigURL.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            try fm.moveItem(at: legacyConfigURL, to: defaultConfigURL)
            tmLog("[TranscribeMini] Migrated config to \(defaultConfigURL.path)")
        } catch {
            tmLog("[TranscribeMini] Warning: Failed to migrate legacy config: \(error.localizedDescription)")
        }
    }

    private static func ensureConfigExists(at url: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else {
            return
        }

        let parent = url.deletingLastPathComponent()
        let defaultConfig = """
        {
          "defaultProfile": "openai",
          "profiles": {
            "openai": {
              "provider": "openai",
              "model": "gpt-4o-mini-transcribe",
              "language": "en"
            }
          }
        }
        """

        do {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            try defaultConfig.write(to: url, atomically: true, encoding: .utf8)
            tmLog("[TranscribeMini] Created default config at \(url.path)")
        } catch {
            tmLog("[TranscribeMini] Warning: Failed to create default config: \(error.localizedDescription)")
        }
    }
}

private struct ProfilesFileConfig: Decodable {
    let defaultProfile: String?
    let profiles: [String: ProfileConfig]?
}

private struct ProfileConfig: Decodable {
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

private extension AppConfig {
    mutating func apply(profile: ProfileConfig) {
        if let provider = profile.provider {
            self.provider = provider
        }
        if let apiKey = profile.apiKey {
            self.apiKey = apiKey
        }
        if let model = profile.model {
            self.model = model
        }
        if let endpoint = profile.endpoint {
            self.endpoint = endpoint
        }
        if let language = profile.language {
            self.language = language
        }
        if let whisperCLIPath = profile.whisperCLIPath {
            self.whisperCLIPath = whisperCLIPath
        }
        if let whisperServerPath = profile.whisperServerPath {
            self.whisperServerPath = whisperServerPath
        }
        if let whisperServerHost = profile.whisperServerHost, !whisperServerHost.isEmpty {
            self.whisperServerHost = whisperServerHost
        }
        if let whisperServerPort = profile.whisperServerPort {
            self.whisperServerPort = whisperServerPort
        }
        if let whisperServerInferencePath = profile.whisperServerInferencePath,
           !whisperServerInferencePath.isEmpty {
            self.whisperServerInferencePath = whisperServerInferencePath
        }
        if let useWhisperServer = profile.useWhisperServer {
            self.useWhisperServer = useWhisperServer
        }
    }
}
