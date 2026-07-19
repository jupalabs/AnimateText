import AppKit
import XCTest

@MainActor
enum LayerRenderingTestSupport {
    static func assertViewContainsRedInk(
        _ view: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        view.layoutSubtreeIfNeeded()
        let representation = try XCTUnwrap(
            view.bitmapImageRepForCachingDisplay(in: view.bounds),
            file: file,
            line: line
        )
        view.cacheDisplay(in: view.bounds, to: representation)
        var redPixelCount = 0

        for y in 0..<representation.pixelsHigh {
            for x in 0..<representation.pixelsWide {
                guard let color = representation.colorAt(x: x, y: y) else {
                    continue
                }
                if color.alphaComponent > 0.05,
                    color.redComponent > color.greenComponent * 1.5,
                    color.redComponent > color.blueComponent * 1.5
                {
                    redPixelCount += 1
                }
            }
        }

        XCTAssertGreaterThan(redPixelCount, 0, file: file, line: line)
    }

    static func assertTopHeavyGlyphsRenderUpright(
        in view: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        view.layoutSubtreeIfNeeded()

        let representation = try XCTUnwrap(
            view.bitmapImageRepForCachingDisplay(in: view.bounds),
            file: file,
            line: line
        )
        view.cacheDisplay(in: view.bounds, to: representation)

        // Encoding and decoding normalizes AppKit's backing representation to
        // the same top-down row order a user sees on screen. Inspecting the
        // source snapshot bytes directly cannot catch a CALayer content flip.
        let pngData = try XCTUnwrap(
            representation.representation(using: .png, properties: [:]),
            file: file,
            line: line
        )
        let rendered = try XCTUnwrap(
            NSBitmapImageRep(data: pngData),
            file: file,
            line: line
        )

        var topHalfInk = 0
        var bottomHalfInk = 0
        for y in 0..<rendered.pixelsHigh {
            for x in 0..<rendered.pixelsWide {
                guard
                    let color = rendered.colorAt(x: x, y: y),
                    color.alphaComponent > 0.05
                else {
                    continue
                }

                if y < rendered.pixelsHigh / 2 {
                    topHalfInk += 1
                } else {
                    bottomHalfInk += 1
                }
            }
        }

        XCTAssertGreaterThan(topHalfInk, 0, file: file, line: line)
        XCTAssertGreaterThan(
            topHalfInk,
            bottomHalfInk,
            "An uppercase F has more ink in its top half; the inverse indicates vertically flipped layer contents",
            file: file,
            line: line
        )
    }
}

@MainActor
final class FlippedLayerHostView: NSView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
