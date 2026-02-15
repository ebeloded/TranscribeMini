import XCTest
@testable import TranscribeMini

final class AppConfigTests: XCTestCase {
    func testLoadDefaultsWhenNoFileAndNoEnv() {
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("missing-\(UUID().uuidString).json")

        let config = AppConfig.load(from: tmpURL, env: [:])

        XCTAssertEqual(config.provider, .apple)
        XCTAssertEqual(config.apiKey, "")
        XCTAssertEqual(config.model, "gpt-4o-mini-transcribe")
        XCTAssertEqual(config.language, "en-US")
        XCTAssertNil(config.whisperCLIPath)
        XCTAssertNil(config.whisperStreamPath)
        XCTAssertTrue(config.enableStreaming)
    }

    func testLoadFromFileAndEnvOverride() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config.json")
        let json = """
        {
          "provider": "apple",
          "apiKey": "file-key",
          "model": "file-model",
          "language": "de-DE"
        }
        """
        try json.data(using: .utf8)?.write(to: configURL)

        let env: [String: String] = [
            "TRANSCRIBE_PROVIDER": "openai",
            "OPENAI_API_KEY": "env-openai-key",
            "TRANSCRIBE_MODEL": "env-model",
            "TRANSCRIBE_LANGUAGE": "en",
            "WHISPER_CLI_PATH": "/opt/homebrew/bin/whisper-cli",
            "WHISPER_STREAM_PATH": "/opt/homebrew/bin/whisper-stream",
            "TRANSCRIBE_STREAMING": "false"
        ]

        let config = AppConfig.load(from: configURL, env: env)

        XCTAssertEqual(config.provider, .openai)
        XCTAssertEqual(config.apiKey, "env-openai-key")
        XCTAssertEqual(config.model, "env-model")
        XCTAssertEqual(config.language, "en")
        XCTAssertEqual(config.whisperCLIPath, "/opt/homebrew/bin/whisper-cli")
        XCTAssertEqual(config.whisperStreamPath, "/opt/homebrew/bin/whisper-stream")
        XCTAssertFalse(config.enableStreaming)
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
}
