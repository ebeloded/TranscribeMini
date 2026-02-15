import XCTest
@testable import TranscribeMini

final class MultipartFormBuilderTests: XCTestCase {
    func testTranscriptionBodyContainsExpectedParts() throws {
        let boundary = "Boundary-test"
        let audioData = Data("abc123".utf8)

        let body = MultipartFormBuilder.makeTranscriptionBody(
            boundary: boundary,
            model: "gpt-4o-mini-transcribe",
            language: "en",
            filename: "clip.m4a",
            audioData: audioData,
            mimeType: "audio/m4a"
        )

        let bodyString = try XCTUnwrap(String(data: body, encoding: .utf8))

        XCTAssertTrue(bodyString.contains("--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\ngpt-4o-mini-transcribe\r\n"))
        XCTAssertTrue(bodyString.contains("--\(boundary)\r\nContent-Disposition: form-data; name=\"language\"\r\n\r\nen\r\n"))
        XCTAssertTrue(bodyString.contains("Content-Disposition: form-data; name=\"file\"; filename=\"clip.m4a\"\r\n"))
        XCTAssertTrue(bodyString.contains("Content-Type: audio/m4a\r\n\r\nabc123\r\n"))
        XCTAssertTrue(bodyString.hasSuffix("--\(boundary)--\r\n"))
    }

    func testTranscriptionBodyOmitsLanguageWhenEmpty() throws {
        let boundary = "Boundary-test"
        let body = MultipartFormBuilder.makeTranscriptionBody(
            boundary: boundary,
            model: "m",
            language: "",
            filename: "clip.m4a",
            audioData: Data("a".utf8),
            mimeType: "audio/m4a"
        )

        let bodyString = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertFalse(bodyString.contains("name=\"language\""))
    }
}
