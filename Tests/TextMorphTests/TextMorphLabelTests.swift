#if canImport(UIKit)
import UIKit
import XCTest
@testable import TextMorph

@MainActor
final class TextMorphLabelTests: XCTestCase {
    func testInitialStateIsOneAccessibleStaticTextLine() {
        let label = TextMorphLabel(
            text: "Continue",
            font: .systemFont(ofSize: 24),
            textColor: .label
        )

        XCTAssertTrue(label.isAccessibilityElement)
        XCTAssertEqual(label.accessibilityTraits, .staticText)
        XCTAssertEqual(label.accessibilityLabel, "Continue")
        XCTAssertFalse(label.isUserInteractionEnabled)
        XCTAssertFalse(label.clipsToBounds)
        XCTAssertEqual(label.layer.sublayers?.count, 1)
        XCTAssertGreaterThan(label.intrinsicContentSize.width, 0)
        XCTAssertGreaterThan(label.intrinsicContentSize.height, 0)
    }

    func testOffWindowUpdateFinishesImmediatelyAndExactlyOnce() {
        let label = TextMorphLabel(text: "Continue")
        var completionCount = 0
        label.onAnimationCompletion = { completionCount += 1 }

        label.setText("Confirm", animated: true)

        XCTAssertEqual(label.text, "Confirm")
        XCTAssertEqual(label.accessibilityLabel, "Confirm")
        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(label.layer.sublayers?.count, 1)
    }

    func testStyleRebuildDoesNotMasqueradeAsTextCompletion() {
        let label = TextMorphLabel(text: "Continue")
        var completionCount = 0
        label.onAnimationCompletion = { completionCount += 1 }

        label.font = .systemFont(ofSize: 28, weight: .bold)
        label.textColor = .systemRed
        label.granularity = .word

        XCTAssertEqual(completionCount, 0)
        XCTAssertEqual(label.layer.sublayers?.count, 1)
    }

    func testEmptyTextHasZeroIntrinsicSize() {
        let label = TextMorphLabel(text: "")

        XCTAssertEqual(label.intrinsicContentSize, .zero)
        XCTAssertEqual(label.sizeThatFits(.zero), .zero)
        XCTAssertNil(label.layer.sublayers)
    }
}
#endif
