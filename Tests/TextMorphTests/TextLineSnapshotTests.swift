import AppKit
import XCTest
@testable import TextMorph

@MainActor
final class TextLineSnapshotTests: XCTestCase {
    func testSystemLatinTextRemainsGraphemeAddressable() {
        let snapshot = makeSnapshot("Continue")
        XCTAssertEqual(
            snapshot.units.map(\.value),
            Array("Continue").map(String.init)
        )
        assertValidSlices(snapshot)
    }

    func testExtendedGraphemesRemainAtomic() {
        let text = "Ae\u{301}👨‍👩‍👧‍👦B"
        let snapshot = makeSnapshot(text)
        XCTAssertEqual(snapshot.units.map(\.value), ["A", "e\u{301}", "👨‍👩‍👧‍👦", "B"])
        assertValidSlices(snapshot)
    }

    func testContextSensitiveRTLRunIsKeptIntact() {
        let snapshot = makeSnapshot("مرحبا")
        XCTAssertEqual(snapshot.units.map(\.value), ["مرحبا"])
        assertValidSlices(snapshot)
    }

    func testMixedDirectionTextPreservesLogicalOrderAndVisualSlices() {
        let snapshot = makeSnapshot("abc אבג def", granularity: .word)
        XCTAssertEqual(
            snapshot.units.map(\.value),
            ["abc", " ", "אבג", " ", "def"]
        )
        assertValidSlices(snapshot)
    }

    func testFontLigatureIsCoalescedRatherThanCut() throws {
        let font = try XCTUnwrap(NSFont(name: "HoeflerText-Regular", size: 32))
        let snapshot = makeSnapshot("office", font: font)

        XCTAssertEqual(snapshot.units.map(\.value), ["o", "ffi", "c", "e"])
        assertValidSlices(snapshot)
    }

    func testEmptyTextHasZeroMetricsAndNoBackingImage() {
        let snapshot = makeSnapshot("")
        XCTAssertEqual(snapshot.metrics, .zero)
        XCTAssertNil(snapshot.image)
        XCTAssertTrue(snapshot.units.isEmpty)
    }

    func testLongTextFallsBackToOneAnimationUnit() {
        let snapshot = makeSnapshot(String(repeating: "a", count: 300))
        let units = snapshot.animationUnits(maximumCount: 256)

        XCTAssertEqual(units.count, 1)
        XCTAssertEqual(units[0].value, snapshot.text)
        XCTAssertEqual(units[0].contentsRect, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testOversizedLineBoundsItsBackingStoreWithoutChangingMetrics() throws {
        let text = String(repeating: "😀", count: 600)
        let snapshot = makeSnapshot(text, font: .systemFont(ofSize: 64))
        let image = try XCTUnwrap(snapshot.image)

        XCTAssertLessThan(snapshot.scale, 3)
        XCTAssertLessThanOrEqual(image.width, 16_384)
        XCTAssertLessThanOrEqual(image.height, 16_384)
        XCTAssertLessThanOrEqual(image.width * image.height, 16_777_216)
        XCTAssertGreaterThan(snapshot.metrics.size.width, 16_384 / 3)
    }

    func testAsymmetricGlyphRasterKeepsInkAboveItsBaseline() throws {
        let snapshot = makeSnapshot(
            "F",
            font: .systemFont(ofSize: 96, weight: .black)
        )
        let image = try XCTUnwrap(snapshot.image)
        let provider = try XCTUnwrap(image.dataProvider)
        let data = try XCTUnwrap(provider.data)
        let bytes = CFDataGetBytePtr(data)
        let baselineRow = Int(
            ((snapshot.metrics.baseline - snapshot.fullFrame.minY) * snapshot.scale)
                .rounded(.up)
        )
        var inkAboveBaseline = 0
        var inkBelowBaseline = 0

        for row in 0..<image.height {
            for column in 0..<image.width {
                let alphaOffset = row * image.bytesPerRow + column * 4 + 3
                guard bytes?[alphaOffset] ?? 0 > 8 else { continue }
                if row < baselineRow {
                    inkAboveBaseline += 1
                } else {
                    inkBelowBaseline += 1
                }
            }
        }

        XCTAssertGreaterThan(inkAboveBaseline, 0)
        XCTAssertLessThan(
            inkBelowBaseline,
            max(inkAboveBaseline / 10, 1),
            "An uppercase F has no descender; substantial ink below the baseline indicates a vertically flipped raster"
        )
    }

    private func makeSnapshot(
        _ text: String,
        font: NSFont = .systemFont(ofSize: 32),
        granularity: TextMorphGranularity = .grapheme
    ) -> TextLineSnapshot {
        TextLineSnapshot.make(
            text: text,
            font: font,
            color: .black,
            scale: 3,
            granularity: granularity
        )
    }

    private func assertValidSlices(
        _ snapshot: TextLineSnapshot,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let visible = snapshot.units
            .filter(\.hasInk)
            .sorted { $0.contentsRect.minX < $1.contentsRect.minX }

        for unit in visible {
            XCTAssertGreaterThan(unit.layerBounds.width, 0, file: file, line: line)
            XCTAssertGreaterThan(unit.layerBounds.height, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(unit.contentsRect.minX, 0, file: file, line: line)
            XCTAssertLessThanOrEqual(unit.contentsRect.maxX, 1.000_001, file: file, line: line)
            XCTAssertTrue(unit.anchor.x.isFinite, file: file, line: line)
            XCTAssertTrue(unit.anchor.y.isFinite, file: file, line: line)
        }

        for pair in zip(visible, visible.dropFirst()) {
            XCTAssertLessThanOrEqual(
                pair.0.contentsRect.maxX,
                pair.1.contentsRect.minX + 0.000_001,
                file: file,
                line: line
            )
        }
    }
}
