import Foundation
import XCTest
@testable import TranscribeMini

final class OpenAICompatibleIntegrationTests: XCTestCase {
    func testOpenAITranscriptionIntegration() async throws {
        try requireIntegrationEnabled()

        let env = ProcessInfo.processInfo.environment
        guard let apiKey = env["TRANSCRIBE_OPENAI_API_KEY"] ?? env["OPENAI_API_KEY"], !apiKey.isEmpty else {
            throw XCTSkip("Missing OpenAI API key env var.")
        }

        let model = env["OPENAI_TRANSCRIBE_MODEL"] ?? "gpt-4o-mini-transcribe"
        let transcriber = OpenAICompatibleTranscriber(
            endpoint: Provider.openai.defaultEndpoint,
            apiKey: apiKey,
            model: model,
            language: "en"
        )

        let audioData = makeIntegrationWAV()
        _ = try await transcriber.transcribe(
            audioData: audioData,
            mimeType: "audio/wav",
            filename: "integration.wav"
        )
    }

    func testGroqTranscriptionIntegration() async throws {
        try requireIntegrationEnabled()

        let env = ProcessInfo.processInfo.environment
        guard let apiKey = env["TRANSCRIBE_GROQ_API_KEY"] ?? env["GROQ_API_KEY"], !apiKey.isEmpty else {
            throw XCTSkip("Missing Groq API key env var.")
        }

        let model = env["GROQ_TRANSCRIBE_MODEL"] ?? "whisper-large-v3"
        let transcriber = OpenAICompatibleTranscriber(
            endpoint: Provider.groq.defaultEndpoint,
            apiKey: apiKey,
            model: model,
            language: "en"
        )

        let audioData = makeIntegrationWAV()
        _ = try await transcriber.transcribe(
            audioData: audioData,
            mimeType: "audio/wav",
            filename: "integration.wav"
        )
    }

    private func requireIntegrationEnabled() throws {
        let enabled = ProcessInfo.processInfo.environment["RUN_INTEGRATION_TESTS"]
        if enabled != "1" {
            throw XCTSkip("Integration tests disabled. Set RUN_INTEGRATION_TESTS=1 to enable.")
        }
    }

    private func makeIntegrationWAV(sampleRate: Int = 16_000, durationSeconds: Double = 4.0) -> Data {
        let frameCount = Int(Double(sampleRate) * durationSeconds)
        var pcm = Data(capacity: frameCount * 2)

        for i in 0 ..< frameCount {
            let t = Double(i) / Double(sampleRate)
            let voiced = sin(2.0 * .pi * 180.0 * t)
                + 0.6 * sin(2.0 * .pi * 320.0 * t)
                + 0.3 * sin(2.0 * .pi * 510.0 * t)
            let envelope = 0.55 + 0.45 * sin(2.0 * .pi * 1.9 * t)
            let sample = max(-1.0, min(1.0, 0.25 * envelope * voiced))
            let int16 = Int16(sample * Double(Int16.max))
            pcm.appendLE(int16)
        }

        let byteRate = UInt32(sampleRate * 2)
        let blockAlign: UInt16 = 2
        let dataChunkSize = UInt32(pcm.count)
        let riffChunkSize = 36 + dataChunkSize

        var wav = Data()
        wav.append("RIFF".data(using: .ascii)!)
        wav.appendLE(riffChunkSize)
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!)
        wav.appendLE(UInt32(16))
        wav.appendLE(UInt16(1))
        wav.appendLE(UInt16(1))
        wav.appendLE(UInt32(sampleRate))
        wav.appendLE(byteRate)
        wav.appendLE(blockAlign)
        wav.appendLE(UInt16(16))
        wav.append("data".data(using: .ascii)!)
        wav.appendLE(dataChunkSize)
        wav.append(pcm)
        return wav
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append($0.bindMemory(to: UInt8.self)) }
    }

    mutating func appendLE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append($0.bindMemory(to: UInt8.self)) }
    }

    mutating func appendLE(_ value: Int16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append($0.bindMemory(to: UInt8.self)) }
    }
}
