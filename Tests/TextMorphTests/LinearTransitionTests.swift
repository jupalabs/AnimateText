import XCTest
@testable import TextMorph

final class LinearTransitionTests: XCTestCase {
    func testDelayAndDurationAreFrameRateIndependent() {
        var direct = LinearTransition(value: 0)
        var stepped = LinearTransition(value: 0)
        direct.retarget(to: 1, duration: 0.12, delay: 0.03)
        stepped.retarget(to: 1, duration: 0.12, delay: 0.03)

        direct.advance(by: 0.09)
        for _ in 0..<9 {
            stepped.advance(by: 0.01)
        }

        XCTAssertEqual(direct.value, stepped.value, accuracy: 1e-12)
        XCTAssertEqual(direct.value, 0.5, accuracy: 1e-12)
    }

    func testRetargetStartsAtTheCurrentPresentationValue() {
        var transition = LinearTransition(value: 0)
        transition.retarget(to: 1, duration: 0.1)
        transition.advance(by: 0.04)
        let value = transition.value

        transition.retarget(to: 0, duration: 0.1)
        XCTAssertEqual(transition.value, value)
        transition.advance(by: 0.05)
        XCTAssertEqual(transition.value, value / 2, accuracy: 1e-12)
    }

    func testZeroDurationSnapsAfterItsDelay() {
        var transition = LinearTransition(value: 0)
        transition.retarget(to: 1, duration: 0, delay: 0.02)
        transition.advance(by: 0.01)
        XCTAssertEqual(transition.value, 0)
        transition.advance(by: 0.01)
        XCTAssertEqual(transition.value, 0)
        transition.advance(by: 0.001)
        XCTAssertEqual(transition.value, 1)
        XCTAssertTrue(transition.isSettled)
    }
}
