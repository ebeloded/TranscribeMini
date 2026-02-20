import XCTest
@testable import TranscribeMini

final class AppConfigTests: XCTestCase {
    func testLoadDefaultsWhenNoFileAndNoEnv() {
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("missing-\(UUID().uuidString).json")

        let config = AppConfig.load(from: tmpURL, env: [:])

        XCTAssertEqual(config.provider, .openai)
        XCTAssertEqual(config.apiKey, "")
        XCTAssertEqual(config.model, "gpt-4o-mini-transcribe")
        XCTAssertEqual(config.language, "en")
        XCTAssertNil(config.whisperCLIPath)
        XCTAssertNil(config.whisperServerPath)
        XCTAssertEqual(config.whisperServerHost, "127.0.0.1")
        XCTAssertEqual(config.whisperServerPort, 8178)
        XCTAssertEqual(config.whisperServerInferencePath, "/inference")
        XCTAssertTrue(config.useWhisperServer)
        XCTAssertNil(config.activeProfileName)
    }

    func testSelectsDefaultProfileFromProfilesFile() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config.json")
        let json = """
        {
          "defaultProfile": "apple",
          "profiles": {
            "openai": {
              "provider": "openai",
              "model": "gpt-4o-mini-transcribe",
              "language": "en"
            },
            "apple": {
              "provider": "apple",
              "language": "en-US"
            }
          }
        }
        """
        try json.data(using: .utf8)?.write(to: configURL)

        let config = AppConfig.load(from: configURL, env: [:])

        XCTAssertEqual(config.activeProfileName, "apple")
        XCTAssertEqual(config.provider, .apple)
        XCTAssertEqual(config.language, "en-US")
    }

    func testSelectsProfileFromEnvOverride() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config.json")
        let json = """
        {
          "defaultProfile": "apple",
          "profiles": {
            "openai": {
              "provider": "openai",
              "model": "gpt-4o-mini-transcribe"
            },
            "apple": {
              "provider": "apple",
              "language": "en-US"
            }
          }
        }
        """
        try json.data(using: .utf8)?.write(to: configURL)

        let config = AppConfig.load(
            from: configURL,
            env: [
                "TRANSCRIBE_PROFILE": "openai",
                "OPENAI_API_KEY": "env-openai-key"
            ]
        )

        XCTAssertEqual(config.activeProfileName, "openai")
        XCTAssertEqual(config.provider, .openai)
        XCTAssertEqual(config.apiKey, "env-openai-key")
    }

    func testAppliesEnvOverridesAfterProfileSelection() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config.json")
        let json = """
        {
          "defaultProfile": "openai",
          "profiles": {
            "openai": {
              "provider": "openai",
              "model": "file-model",
              "language": "de-DE"
            },
            "apple": {
              "provider": "apple",
              "language": "en-US"
            }
          }
        }
        """
        try json.data(using: .utf8)?.write(to: configURL)

        let env: [String: String] = [
            "TRANSCRIBE_PROFILE": "openai",
            "TRANSCRIBE_PROVIDER": "groq",
            "OPENAI_API_KEY": "env-openai-key",
            "TRANSCRIBE_MODEL": "env-model",
            "TRANSCRIBE_LANGUAGE": "en",
            "WHISPER_CLI_PATH": "/opt/homebrew/bin/whisper-cli",
            "WHISPER_SERVER_PATH": "/opt/homebrew/bin/whisper-server",
            "WHISPER_SERVER_HOST": "localhost",
            "WHISPER_SERVER_PORT": "9000",
            "WHISPER_SERVER_INFERENCE_PATH": "inference2",
            "TRANSCRIBE_USE_WHISPER_SERVER": "false"
        ]

        let config = AppConfig.load(from: configURL, env: env)

        XCTAssertEqual(config.activeProfileName, "openai")
        XCTAssertEqual(config.provider, .groq)
        XCTAssertEqual(config.apiKey, "env-openai-key")
        XCTAssertEqual(config.model, "env-model")
        XCTAssertEqual(config.language, "en")
        XCTAssertEqual(config.whisperCLIPath, "/opt/homebrew/bin/whisper-cli")
        XCTAssertEqual(config.whisperServerPath, "/opt/homebrew/bin/whisper-server")
        XCTAssertEqual(config.whisperServerHost, "localhost")
        XCTAssertEqual(config.whisperServerPort, 9000)
        XCTAssertEqual(config.whisperServerInferencePath, "inference2")
        XCTAssertFalse(config.useWhisperServer)
    }

    func testInvalidProfileFallsBackToDeterministicProfile() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config.json")
        let json = """
        {
          "defaultProfile": "missing-default",
          "profiles": {
            "whispercpp": {
              "provider": "whispercpp",
              "model": "/tmp/model.bin",
              "useWhisperServer": false
            },
            "apple": {
              "provider": "apple",
              "language": "en-US"
            }
          }
        }
        """
        try json.data(using: .utf8)?.write(to: configURL)

        let config = AppConfig.load(
            from: configURL,
            env: ["TRANSCRIBE_PROFILE": "does-not-exist"]
        )

        XCTAssertEqual(config.activeProfileName, "apple")
        XCTAssertEqual(config.provider, .apple)
        XCTAssertEqual(config.language, "en-US")
    }

    func testInvalidSchemaFallsBackToDefaultsAndEnv() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config.json")
        let json = """
        {
          "provider": "apple",
          "model": "legacy-model",
          "language": "de-DE"
        }
        """
        try json.data(using: .utf8)?.write(to: configURL)

        let config = AppConfig.load(
            from: configURL,
            env: [
                "TRANSCRIBE_PROVIDER": "apple",
                "TRANSCRIBE_LANGUAGE": "en-US"
            ]
        )
        XCTAssertNil(config.activeProfileName)
        XCTAssertEqual(config.provider, .apple)
        XCTAssertEqual(config.apiKey, "")
        XCTAssertEqual(config.model, "gpt-4o-mini-transcribe")
        XCTAssertEqual(config.language, "en-US")
    }

    func testLocalModelEnvOverridesModel() {
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("missing-\(UUID().uuidString).json")
        let env: [String: String] = [
            "TRANSCRIBE_LOCAL_MODEL": "/tmp/ggml-tiny.en.bin"
        ]

        let config = AppConfig.load(from: tmpURL, env: env)
        XCTAssertEqual(config.model, "/tmp/ggml-tiny.en.bin")
    }

    func testUsesTranscribeOpenAIAPIKeyWhenProviderIsOpenAI() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config.json")
        let json = """
        {
          "defaultProfile": "openai",
          "profiles": {
            "openai": {
              "provider": "openai",
              "model": "gpt-4o-mini-transcribe"
            }
          }
        }
        """
        try json.data(using: .utf8)?.write(to: configURL)

        let config = AppConfig.load(
            from: configURL,
            env: [
                "TRANSCRIBE_OPENAI_API_KEY": "transcribe-openai-key",
                "OPENAI_API_KEY": "openai-key"
            ]
        )

        XCTAssertEqual(config.provider, .openai)
        XCTAssertEqual(config.apiKey, "transcribe-openai-key")
    }

    func testUsesTranscribeGroqAPIKeyWhenProviderIsGroq() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config.json")
        let json = """
        {
          "defaultProfile": "groq",
          "profiles": {
            "groq": {
              "provider": "groq",
              "model": "whisper-large-v3"
            }
          }
        }
        """
        try json.data(using: .utf8)?.write(to: configURL)

        let config = AppConfig.load(
            from: configURL,
            env: [
                "TRANSCRIBE_GROQ_API_KEY": "transcribe-groq-key",
                "GROQ_API_KEY": "groq-key"
            ]
        )

        XCTAssertEqual(config.provider, .groq)
        XCTAssertEqual(config.apiKey, "transcribe-groq-key")
    }

    func testAvailableProfilesReturnsSortedProfileNames() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config.json")
        let json = """
        {
          "defaultProfile": "groq",
          "profiles": {
            "whispercpp": { "provider": "whispercpp", "model": "/tmp/model.bin" },
            "apple": { "provider": "apple" },
            "groq": { "provider": "groq", "model": "whisper-large-v3" }
          }
        }
        """
        try json.data(using: .utf8)?.write(to: configURL)

        XCTAssertEqual(AppConfig.availableProfiles(from: configURL), ["apple", "groq", "whispercpp"])
    }
}
