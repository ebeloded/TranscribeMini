import XCTest
@testable import TranscribeMini

final class TranscriberFactoryTests: XCTestCase {
    func testFactoryCreatesAppleTranscriber() {
        let config = AppConfig(
            provider: .apple,
            apiKey: "",
            model: "gpt-4o-mini-transcribe",
            endpoint: nil,
            language: "en-US",
            whisperCLIPath: nil,
            whisperServerPath: nil,
            whisperServerHost: "127.0.0.1",
            whisperServerPort: 8178,
            whisperServerInferencePath: "/inference",
            useWhisperServer: true
        )

        let transcriber = TranscriberFactory.make(config: config)
        XCTAssertTrue(type(of: transcriber) == AppleSpeechTranscriber.self)
    }

    func testFactoryCreatesOpenAICompatibleTranscriber() {
        let config = AppConfig(
            provider: .openai,
            apiKey: "k",
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

        let transcriber = TranscriberFactory.make(config: config)
        XCTAssertTrue(type(of: transcriber) == OpenAICompatibleTranscriber.self)
    }

    func testFactoryCreatesWhisperCPPTranscriber() {
        let config = AppConfig(
            provider: .whispercpp,
            apiKey: "",
            model: "/tmp/model.bin",
            endpoint: nil,
            language: "en",
            whisperCLIPath: "/opt/homebrew/bin/whisper-cli",
            whisperServerPath: "/opt/homebrew/bin/whisper-server",
            whisperServerHost: "127.0.0.1",
            whisperServerPort: 8178,
            whisperServerInferencePath: "/inference",
            useWhisperServer: false
        )

        let transcriber = TranscriberFactory.make(config: config)
        XCTAssertTrue(type(of: transcriber) == WhisperCPPTranscriber.self)
    }

    func testFactoryCreatesWhisperServerTranscriberByDefault() {
        let config = AppConfig(
            provider: .whispercpp,
            apiKey: "",
            model: "/tmp/model.bin",
            endpoint: nil,
            language: "en",
            whisperCLIPath: "/opt/homebrew/bin/whisper-cli",
            whisperServerPath: "/opt/homebrew/bin/whisper-server",
            whisperServerHost: "127.0.0.1",
            whisperServerPort: 8178,
            whisperServerInferencePath: "/inference",
            useWhisperServer: true
        )

        let transcriber = TranscriberFactory.make(config: config)
        XCTAssertTrue(type(of: transcriber) == WhisperServerTranscriber.self)
    }
}
