import AppKit
import QuartzCore
import XCTest
@testable import TextMorph

@MainActor
private final class SelfRemovingDisplayLinkParticipant: DisplayLinkParticipant {
    private(set) var callCount = 0
    weak var driver: DisplayLinkDriver?

    func advanceFrame(by duration: TimeInterval) -> Bool {
        callCount += 1
        driver?.stop(self)
        return false
    }
}

@MainActor
private final class ReRegisteringDisplayLinkParticipant: DisplayLinkParticipant {
    private(set) var callCount = 0
    weak var driver: DisplayLinkDriver?

    func advanceFrame(by duration: TimeInterval) -> Bool {
        callCount += 1
        if callCount == 1 {
            driver?.stop(self)
            driver?.start(self)
        }
        return false
    }
}

@MainActor
final class TextMorphEngineTests: XCTestCase {
    func testSharedIdentitySurvivesContinueToConfirm() throws {
        let fixture = makeFixture(text: "Continue")
        let initial = fixture.engine.debugTargetTokens

        fixture.engine.update(
            to: snapshot("Confirm"),
            animation: .default,
            animated: true,
            fontSize: 32
        )

        let target = fixture.engine.debugTargetTokens
        XCTAssertEqual(target[0].identifier, initial[0].identifier)
        XCTAssertEqual(target[1].identifier, initial[1].identifier)
        XCTAssertEqual(target[2].identifier, initial[2].identifier)
        XCTAssertEqual(target[4].identifier, initial[4].identifier)
        XCTAssertEqual(fixture.engine.debugExitingTokens.count, 4)
    }

    func testImmediateInternalUpdateCanSuppressCompletion() {
        let fixture = makeFixture(text: "Continue")
        var completionCount = 0
        fixture.engine.onCompletion = { completionCount += 1 }

        fixture.engine.update(
            to: snapshot("Confirm"),
            animation: .disabled,
            animated: false,
            forceReplacement: true,
            fontSize: 32,
            notifyCompletion: false
        )

        XCTAssertEqual(completionCount, 0)
    }

    func testRapidReversalResurrectsAnExitingVisualAndRetainsContinuity() throws {
        let fixture = makeFixture(text: "Continue")
        let originalE = try XCTUnwrap(
            fixture.engine.debugTargetTokens.last { $0.value == "e" }
        )

        fixture.engine.update(
            to: snapshot("Confirm"),
            animation: .default,
            animated: true,
            fontSize: 32
        )
        for _ in 0..<4 {
            _ = fixture.engine.advanceFrame(by: 1.0 / 120)
        }
        let exitingE = try XCTUnwrap(
            fixture.engine.debugExitingTokens.first { $0.identifier == originalE.identifier }
        )

        fixture.engine.update(
            to: snapshot("Continue"),
            animation: .default,
            animated: true,
            fontSize: 32
        )
        let resurrectedE = try XCTUnwrap(
            fixture.engine.debugTargetTokens.first { $0.identifier == originalE.identifier }
        )

        XCTAssertEqual(resurrectedE.position, exitingE.position)
        XCTAssertEqual(resurrectedE.velocity, exitingE.velocity)
        XCTAssertEqual(resurrectedE.opacity, exitingE.opacity)
    }

    func testAnimationConsolidatesToOneExactLineLayerAtRest() {
        let fixture = makeFixture(text: "Continue")
        fixture.engine.update(
            to: snapshot("Confirm"),
            animation: .default,
            animated: true,
            fontSize: 32
        )

        for _ in 0..<600 where fixture.engine.debugIsActive {
            _ = fixture.engine.advanceFrame(by: 1.0 / 120)
        }

        XCTAssertFalse(fixture.engine.debugIsActive)
        XCTAssertTrue(fixture.engine.debugExitingTokens.isEmpty)
        XCTAssertEqual(fixture.host.sublayers?.count, 1)
        XCTAssertEqual(fixture.engine.presentationSize, fixture.engine.targetSize)
    }

    func testMaterializedSlicesReconstructTheExactFullLinePixels() throws {
        let fixture = makeFixture(text: "Continue")
        let before = try render(fixture.host, scale: 3)

        fixture.engine.update(
            to: snapshot("Continue"),
            animation: .default,
            animated: true,
            fontSize: 32
        )
        let after = try render(fixture.host, scale: 3)

        XCTAssertEqual(before, after)
        fixture.engine.finishCurrentAnimation(notifyCompletion: false)
    }

    func testMaterializedSliceLayersRenderUprightInAFlippedAppKitView() throws {
        let font = NSFont.systemFont(ofSize: 96, weight: .black)
        let snapshot = TextLineSnapshot.make(
            text: "FFF",
            font: font,
            color: .white,
            scale: 2,
            granularity: .grapheme
        )
        let hostView = FlippedLayerHostView(
            frame: CGRect(origin: .zero, size: snapshot.metrics.size)
        )
        let hostLayer = try XCTUnwrap(hostView.layer)
        let engine = TextMorphEngine(hostLayer: hostLayer)
        engine.layout(
            in: hostView.bounds,
            alignment: .leading,
            layoutDirection: .leftToRight
        )
        engine.setInitialSnapshot(snapshot)
        engine.layout(
            in: hostView.bounds,
            alignment: .leading,
            layoutDirection: .leftToRight
        )

        engine.update(
            to: snapshot,
            animation: .default,
            animated: true,
            fontSize: font.pointSize
        )

        XCTAssertEqual(hostLayer.sublayers?.count, 3)
        try LayerRenderingTestSupport.assertTopHeavyGlyphsRenderUpright(
            in: hostView
        )
        engine.finishCurrentAnimation(notifyCompletion: false)
    }

    func testCrossfadeDoesNotTranslateOutgoingText() throws {
        let fixture = makeFixture(text: "Continue")
        let originalPosition = try XCTUnwrap(
            fixture.engine.debugTargetTokens.first
        ).position

        fixture.engine.update(
            to: snapshot("Confirm"),
            animation: .default,
            animated: true,
            transitionStyle: .crossfade,
            fontSize: 32
        )

        let exit = try XCTUnwrap(fixture.engine.debugExitingTokens.first)
        XCTAssertEqual(exit.position, originalPosition)
        XCTAssertEqual(exit.target, originalPosition)
    }

    func testLayoutChangeRetargetsExitingVisualsWithTheLine() throws {
        let fixture = makeFixture(text: "Continue")
        fixture.engine.layout(
            in: fixture.host.bounds,
            alignment: .center,
            layoutDirection: .leftToRight
        )
        fixture.engine.update(
            to: snapshot("Confirm"),
            animation: .default,
            animated: true,
            fontSize: 32
        )
        let exitingIdentifier = try XCTUnwrap(
            fixture.engine.debugExitingTokens.first?.identifier
        )
        let previousTarget = try XCTUnwrap(
            fixture.engine.debugExitingTokens.first {
                $0.identifier == exitingIdentifier
            }?.target
        )

        fixture.host.bounds.size.width += 200
        fixture.engine.layout(
            in: fixture.host.bounds,
            alignment: .center,
            layoutDirection: .leftToRight
        )

        let retargeted = try XCTUnwrap(
            fixture.engine.debugExitingTokens.first {
                $0.identifier == exitingIdentifier
            }
        )
        XCTAssertEqual(retargeted.target.x, previousTarget.x + 100, accuracy: 0.001)
        XCTAssertEqual(retargeted.target.y, previousTarget.y, accuracy: 0.001)
    }

    func testLongLineTransitionBoundsBothSidesToWholeLineVisuals() {
        let longText = String(repeating: "a", count: 300)
        let fixture = makeFixture(text: longText)

        fixture.engine.update(
            to: snapshot("Short"),
            animation: .default,
            animated: true,
            fontSize: 32
        )

        XCTAssertEqual(fixture.engine.debugTargetTokens.count, 1)
        XCTAssertEqual(fixture.engine.debugExitingTokens.count, 1)
        XCTAssertEqual(fixture.host.sublayers?.count, 2)
    }

    func testRapidFullUnitReplacementBoundsCumulativeExitingVisuals() {
        let unitCount = TextMorphEngine.maximumAnimatedUnitCount
        let fixture = makeFixture(text: String(repeating: "a", count: unitCount))

        for character in ["b", "c", "d", "e"] {
            fixture.engine.update(
                to: snapshot(String(repeating: character, count: unitCount)),
                animation: .default,
                animated: true,
                fontSize: 32
            )
        }

        XCTAssertEqual(fixture.engine.debugTargetTokens.count, unitCount)
        XCTAssertLessThanOrEqual(
            fixture.engine.debugExitingTokens.count,
            TextMorphEngine.maximumExitingUnitCount
        )
        XCTAssertLessThanOrEqual(
            fixture.host.sublayers?.count ?? 0,
            TextMorphEngine.maximumAnimatedUnitCount
                + TextMorphEngine.maximumExitingUnitCount
        )
    }

    func testDisplayLinkAdvanceToleratesSynchronousStop() {
        let driver = DisplayLinkDriver()
        let selfRemoving = SelfRemovingDisplayLinkParticipant()
        selfRemoving.driver = driver
        driver.start(selfRemoving)

        XCTAssertFalse(driver.advanceParticipant(by: 1.0 / 120))
        XCTAssertFalse(driver.advanceParticipant(by: 1.0 / 120))

        XCTAssertEqual(selfRemoving.callCount, 1)
    }

    func testOldCallbackCannotClearASynchronousReplacementRegistration() {
        let driver = DisplayLinkDriver()
        let participant = ReRegisteringDisplayLinkParticipant()
        participant.driver = driver
        driver.start(participant)

        XCTAssertFalse(driver.advanceParticipant(by: 1.0 / 120))
        XCTAssertEqual(participant.callCount, 1)

        XCTAssertFalse(driver.advanceParticipant(by: 1.0 / 120))
        XCTAssertFalse(driver.advanceParticipant(by: 1.0 / 120))
        XCTAssertEqual(participant.callCount, 2)
    }

    func testCompletionCanSynchronouslyStartTheNextMorph() {
        let fixture = makeFixture(text: "Continue")
        let engine = fixture.engine
        var completionCount = 0
        engine.onCompletion = { [unowned engine] in
            completionCount += 1
            if completionCount == 1 {
                engine.update(
                    to: self.snapshot("Done"),
                    animation: .default,
                    animated: true,
                    fontSize: 32
                )
            }
        }
        engine.update(
            to: snapshot("Confirm"),
            animation: .default,
            animated: true,
            fontSize: 32
        )

        for _ in 0..<1_200 where engine.debugIsActive {
            _ = fixture.driver.advanceParticipant(by: 1.0 / 120)
        }

        XCTAssertEqual(completionCount, 2)
        XCTAssertFalse(engine.debugIsActive)
        XCTAssertEqual(engine.debugTargetTokens.map(\.value), Array("Done").map(String.init))
        XCTAssertEqual(fixture.host.sublayers?.count, 1)
    }

    func testUndampedCustomSpringCannotKeepTheDisplayLinkAliveForever() {
        let fixture = makeFixture(text: "Continue")
        let undamped = TextMorphAnimation(
            response: 0.44,
            dampingRatio: 0
        )
        fixture.engine.update(
            to: snapshot("Confirm"),
            animation: undamped,
            animated: true,
            fontSize: 32
        )

        for _ in 0..<1_300 where fixture.engine.debugIsActive {
            _ = fixture.engine.advanceFrame(by: 1.0 / 120)
        }

        XCTAssertFalse(fixture.engine.debugIsActive)
        XCTAssertEqual(fixture.host.sublayers?.count, 1)
    }

    func testInvalidFrameDurationConsolidatesInsteadOfPoisoningMotionState() {
        for duration in [TimeInterval.nan, -.infinity, -0.001, 0.251] {
            let fixture = makeFixture(text: "Continue")
            fixture.engine.update(
                to: snapshot("Confirm"),
                animation: .default,
                animated: true,
                fontSize: 32
            )

            XCTAssertFalse(fixture.engine.advanceFrame(by: duration))
            XCTAssertFalse(fixture.engine.debugIsActive)
            XCTAssertEqual(fixture.host.sublayers?.count, 1)
        }
    }

    func testOnlyTheLatestInterruptedGenerationCompletes() {
        let fixture = makeFixture(text: "Continue")
        var completionCount = 0
        fixture.engine.onCompletion = { completionCount += 1 }
        fixture.engine.update(
            to: snapshot("Confirm"),
            animation: .default,
            animated: true,
            fontSize: 32
        )
        for _ in 0..<4 {
            _ = fixture.engine.advanceFrame(by: 1.0 / 120)
        }

        fixture.engine.update(
            to: snapshot("Continue"),
            animation: .default,
            animated: true,
            fontSize: 32
        )
        for _ in 0..<600 where fixture.engine.debugIsActive {
            _ = fixture.engine.advanceFrame(by: 1.0 / 120)
        }

        XCTAssertEqual(completionCount, 1)
    }

    private func makeFixture(
        text: String
    ) -> (engine: TextMorphEngine, host: CALayer, driver: DisplayLinkDriver) {
        let host = CALayer()
        host.bounds = CGRect(x: 0, y: 0, width: 400, height: 80)
        let driver = DisplayLinkDriver()
        let engine = TextMorphEngine(
            hostLayer: host,
            displayLinkDriver: driver
        )
        engine.layout(
            in: host.bounds,
            alignment: .leading,
            layoutDirection: .leftToRight
        )
        engine.setInitialSnapshot(snapshot(text))
        engine.layout(
            in: host.bounds,
            alignment: .leading,
            layoutDirection: .leftToRight
        )
        return (engine, host, driver)
    }

    private func snapshot(_ text: String) -> TextLineSnapshot {
        TextLineSnapshot.make(
            text: text,
            font: .systemFont(ofSize: 32),
            color: .black,
            scale: 3,
            granularity: .grapheme
        )
    }

    private func render(_ layer: CALayer, scale: CGFloat) throws -> Data {
        let pixelWidth = max(Int((layer.bounds.width * scale).rounded()), 1)
        let pixelHeight = max(Int((layer.bounds.height * scale).rounded()), 1)
        let colorSpace =
            CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo =
            CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        )
        context.scaleBy(x: scale, y: scale)
        layer.render(in: context)
        let cgImage = try XCTUnwrap(context.makeImage())
        let provider = try XCTUnwrap(cgImage.dataProvider)
        return try XCTUnwrap(provider.data) as Data
    }
}
