import AppKit
import XCTest
@testable import TextMorph

@MainActor
final class TextMorphViewTests: XCTestCase {
    func testInitialStateIsOneAccessibleStaticTextLine() {
        let view = TextMorphView(
            text: "Continue",
            font: .systemFont(ofSize: 24),
            textColor: .labelColor
        )

        XCTAssertTrue(view.isAccessibilityElement())
        XCTAssertEqual(view.accessibilityRole(), .staticText)
        XCTAssertEqual(view.accessibilityValue() as? String, "Continue")
        XCTAssertNil(view.hitTest(.zero))
        XCTAssertFalse(view.layer?.masksToBounds ?? true)
        XCTAssertEqual(view.layer?.sublayers?.count, 1)
        XCTAssertGreaterThan(view.intrinsicContentSize.width, 0)
        XCTAssertGreaterThan(view.intrinsicContentSize.height, 0)
    }

    func testInitialLayerContentsRenderUpright() throws {
        let view = TextMorphView(
            text: "F",
            font: .systemFont(ofSize: 96, weight: .black),
            textColor: .white
        )
        view.frame = CGRect(origin: .zero, size: view.intrinsicContentSize)

        try LayerRenderingTestSupport.assertTopHeavyGlyphsRenderUpright(
            in: view
        )
    }

    func testOffWindowUpdateFinishesImmediatelyAndExactlyOnce() {
        let view = TextMorphView(text: "Continue")
        var completionCount = 0
        view.onAnimationCompletion = { completionCount += 1 }

        view.setText("Confirm", animated: true)

        XCTAssertEqual(view.text, "Confirm")
        XCTAssertEqual(view.accessibilityValue() as? String, "Confirm")
        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(view.layer?.sublayers?.count, 1)
    }

    func testStyleRebuildDoesNotMasqueradeAsTextCompletion() {
        let view = TextMorphView(text: "Continue")
        var completionCount = 0
        view.onAnimationCompletion = { completionCount += 1 }

        view.font = .systemFont(ofSize: 28, weight: .bold)
        view.textColor = .systemRed
        view.granularity = .word

        XCTAssertEqual(completionCount, 0)
        XCTAssertEqual(view.layer?.sublayers?.count, 1)
    }

    func testEmptyTextHasZeroIntrinsicAndIdealSize() {
        let view = TextMorphView(text: "")

        XCTAssertEqual(view.intrinsicContentSize, .zero)
        XCTAssertEqual(view.idealContentSize, .zero)
        XCTAssertNil(view.layer?.sublayers)
    }

    func testConstrainedViewTruncatesRenderedTextButKeepsFullAccessibleValue() {
        let font = NSFont.monospacedSystemFont(ofSize: 20, weight: .regular)
        let view = TextMorphView(
            text: "ABCDEFGHIJ",
            font: font,
            truncationMode: .tail
        )
        view.frame = CGRect(
            origin: .zero,
            size: CGSize(
                width: TextLineMetrics.measure(text: "ABCD…", font: font).size.width,
                height: 40
            )
        )

        view.layout()

        XCTAssertEqual(view.debugRenderedText, "ABCD…")
        XCTAssertEqual(view.accessibilityValue() as? String, "ABCDEFGHIJ")
        XCTAssertEqual(
            view.intrinsicContentSize,
            TextLineMetrics.measure(text: "ABCDEFGHIJ", font: font).size
        )
    }

    func testResolvedZeroWidthDoesNotRenderOutsideItsProposedBounds() {
        let view = TextMorphView(
            text: "ABCDEFGHIJ",
            truncationMode: .tail
        )
        view.frame = CGRect(x: 0, y: 0, width: 0, height: 40)

        view.layout()

        XCTAssertEqual(view.debugRenderedText, "")
        XCTAssertEqual(view.accessibilityValue() as? String, "ABCDEFGHIJ")
        XCTAssertGreaterThan(view.intrinsicContentSize.width, 0)
        XCTAssertNil(view.layer?.sublayers)
    }
}
