#if canImport(UIKit)
import QuartzCore
import XCTest
import UIKit
@testable import TextMorph

@MainActor
private final class SelfRemovingDisplayLinkParticipant: DisplayLinkParticipant {
    private(set) var callCount = 0

    func advanceFrame(by duration: TimeInterval) -> Bool {
        callCount += 1
        SharedDisplayLinkDriver.shared.unregister(self)
        return false
    }
}

@MainActor
private final class OneShotDisplayLinkParticipant: DisplayLinkParticipant {
    private(set) var callCount = 0

    func advanceFrame(by duration: TimeInterval) -> Bool {
        callCount += 1
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

    func testDisplayLinkIterationToleratesSynchronousUnregistration() {
        let selfRemoving = SelfRemovingDisplayLinkParticipant()
        let oneShot = OneShotDisplayLinkParticipant()
        let driver = SharedDisplayLinkDriver.shared
        driver.register(selfRemoving)
        driver.register(oneShot)

        driver.advanceParticipants(by: 1.0 / 120)

        XCTAssertEqual(selfRemoving.callCount, 1)
        XCTAssertEqual(oneShot.callCount, 1)
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

    private func makeFixture(text: String) -> (engine: TextMorphEngine, host: CALayer) {
        let host = CALayer()
        host.bounds = CGRect(x: 0, y: 0, width: 400, height: 80)
        let engine = TextMorphEngine(hostLayer: host)
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
        return (engine, host)
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
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(
            size: layer.bounds.size,
            format: format
        ).image { context in
            layer.render(in: context.cgContext)
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        let provider = try XCTUnwrap(cgImage.dataProvider)
        return try XCTUnwrap(provider.data) as Data
    }
}
#endif
