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
            whisperStreamPath: nil,
            enableStreaming: true
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
            whisperStreamPath: nil,
            enableStreaming: true
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
            whisperStreamPath: "/opt/homebrew/bin/whisper-stream",
            enableStreaming: true
        )

        let transcriber = TranscriberFactory.make(config: config)
        XCTAssertTrue(type(of: transcriber) == WhisperCPPTranscriber.self)
    }
}
