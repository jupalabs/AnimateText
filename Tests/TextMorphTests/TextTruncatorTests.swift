import AppKit
import XCTest
@testable import TextMorph

@MainActor
final class TextTruncatorTests: XCTestCase {
    private let font = NSFont.monospacedSystemFont(ofSize: 20, weight: .regular)

    func testTailTruncationKeepsTheBeginning() {
        let text = "ABCDEFGHIJ"
        let expected = "ABCD…"
        let nextCandidate = "ABCDE…"

        XCTAssertEqual(
            TextTruncator.truncate(
                text,
                toWidth: widthBetween(expected, nextCandidate),
                font: font,
                mode: .tail
            ),
            expected
        )
    }

    func testHeadTruncationKeepsTheEnd() {
        let text = "ABCDEFGHIJ"
        let expected = "…GHIJ"
        let nextCandidate = "…FGHIJ"

        XCTAssertEqual(
            TextTruncator.truncate(
                text,
                toWidth: widthBetween(expected, nextCandidate),
                font: font,
                mode: .head
            ),
            expected
        )
    }

    func testMiddleTruncationKeepsBothEnds() {
        let text = "ABCDEFGHIJ"
        let expected = "AB…IJ"
        let nextCandidate = "ABC…IJ"

        XCTAssertEqual(
            TextTruncator.truncate(
                text,
                toWidth: widthBetween(expected, nextCandidate),
                font: font,
                mode: .middle
            ),
            expected
        )
    }

    func testTruncationDoesNotSplitExtendedGraphemes() {
        let text = "Ae\u{301}👨‍👩‍👧‍👦B"
        let expected = "Ae\u{301}…"
        let nextCandidate = "Ae\u{301}👨‍👩‍👧‍👦…"

        XCTAssertEqual(
            TextTruncator.truncate(
                text,
                toWidth: widthBetween(expected, nextCandidate),
                font: font,
                mode: .tail
            ),
            expected
        )
    }

    func testResultNeverExceedsAvailableWidth() {
        let text = "ABCDEFGHIJ"
        let maximumWidth = width(of: "ABCD…")

        for mode in [
            TextMorphTruncationMode.head,
            .middle,
            .tail,
        ] {
            let result = TextTruncator.truncate(
                text,
                toWidth: maximumWidth,
                font: font,
                mode: mode
            )
            XCTAssertLessThanOrEqual(
                width(of: result),
                maximumWidth + 0.001,
                "\(mode) produced an over-width result"
            )
        }

        XCTAssertEqual(
            TextTruncator.truncate(
                text,
                toWidth: 0,
                font: font,
                mode: .tail
            ),
            ""
        )
        XCTAssertEqual(
            TextTruncator.truncate(
                text,
                toWidth: width(of: text),
                font: font,
                mode: .tail
            ),
            text
        )
    }

    private func widthBetween(_ fitting: String, _ overflowing: String) -> CGFloat {
        let fittingWidth = width(of: fitting)
        let overflowingWidth = width(of: overflowing)
        XCTAssertLessThan(fittingWidth, overflowingWidth)
        return fittingWidth + (overflowingWidth - fittingWidth) / 2
    }

    private func width(of text: String) -> CGFloat {
        TextLineMetrics.measure(text: text, font: font).size.width
    }
}
