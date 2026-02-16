import XCTest
@testable import TranscribeMini

final class TranscriptSanitizerTests: XCTestCase {
    func testSanitizeForPasteReturnsNilForBlankAudioPlaceholder() {
        XCTAssertNil(TranscriptSanitizer.sanitizeForPaste("[BLANK_AUDIO]"))
        XCTAssertNil(TranscriptSanitizer.sanitizeForPaste("[blank_audio]."))
    }

    func testSanitizeForPasteReturnsNilForSilencePlaceholder() {
        XCTAssertNil(TranscriptSanitizer.sanitizeForPaste("[SILENCE]"))
        XCTAssertNil(TranscriptSanitizer.sanitizeForPaste("   (silence)   "))
    }

    func testSanitizeForPasteKeepsNormalText() {
        XCTAssertEqual(
            TranscriptSanitizer.sanitizeForPaste("  hello world  "),
            "hello world"
        )
    }
}
