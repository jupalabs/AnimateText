import XCTest
@testable import TextMorph

final class TextSegmentationTests: XCTestCase {
    func testGraphemeSegmentationPreservesExtendedClusters() {
        let text = "Ae\u{301}👨‍👩‍👧‍👦🇦🇺नमस्ते"
        let segments = TextSegmenter.segments(in: text, granularity: .grapheme)

        XCTAssertEqual(
            segments.map(\.value),
            ["A", "e\u{301}", "👨‍👩‍👧‍👦", "🇦🇺", "न", "म", "स्ते"]
        )
        XCTAssertEqual(segments.map(\.value).joined(), text)
        XCTAssertRangesCoverUTF16(segments, in: text)
    }

    func testAutomaticUsesGraphemesWithoutWhitespace() {
        let segments = TextSegmenter.segments(
            in: "Continue",
            granularity: .automatic
        )
        XCTAssertEqual(segments.map(\.value), Array("Continue").map(String.init))
    }

    func testAutomaticUsesWordsAndPreservesEverySeparator() {
        let text = "Hello,  brave world!"
        let segments = TextSegmenter.segments(in: text, granularity: .automatic)

        XCTAssertEqual(
            segments.map(\.value),
            ["Hello", ",", " ", " ", "brave", " ", "world", "!"]
        )
        XCTAssertEqual(segments.map(\.value).joined(), text)
        XCTAssertRangesCoverUTF16(segments, in: text)
    }

    func testWordModeHandlesMixedDirectionTextWithoutDroppingContent() {
        let text = "abc אבג def"
        let segments = TextSegmenter.segments(in: text, granularity: .word)

        XCTAssertEqual(segments.map(\.value), ["abc", " ", "אבג", " ", "def"])
        XCTAssertEqual(segments.map(\.value).joined(), text)
        XCTAssertRangesCoverUTF16(segments, in: text)
    }

    func testEmptyTextHasNoSegments() {
        XCTAssertTrue(
            TextSegmenter.segments(in: "", granularity: .automatic).isEmpty
        )
    }

    private func XCTAssertRangesCoverUTF16(
        _ segments: [TextSegment],
        in text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var expectedLocation = 0
        for segment in segments {
            XCTAssertEqual(
                segment.range.location,
                expectedLocation,
                file: file,
                line: line
            )
            XCTAssertEqual(
                (text as NSString).substring(with: segment.range),
                segment.value,
                file: file,
                line: line
            )
            expectedLocation = NSMaxRange(segment.range)
        }
        XCTAssertEqual(
            expectedLocation,
            (text as NSString).length,
            file: file,
            line: line
        )
    }
}
