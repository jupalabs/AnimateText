import XCTest
@testable import TextMorph

final class SpringTests: XCTestCase {
    func testUnderCriticalAndOverdampedSpringsAreFrameRateInvariant() {
        for dampingRatio in [0.72, 1, 1.3] {
            let parameters = SpringParameters(
                response: 0.44,
                dampingRatio: dampingRatio
            )
            var sixty = ScalarSpring(value: -20, velocity: 75, target: 140)
            var oneTwenty = sixty

            for _ in 0..<60 {
                sixty.advance(
                    using: SpringStep(parameters: parameters, duration: 1.0 / 60)
                )
            }
            for _ in 0..<120 {
                oneTwenty.advance(
                    using: SpringStep(parameters: parameters, duration: 1.0 / 120)
                )
            }

            XCTAssertEqual(sixty.value, oneTwenty.value, accuracy: 1e-9)
            XCTAssertEqual(sixty.velocity, oneTwenty.velocity, accuracy: 1e-9)
        }
    }

    func testIrregularFrameIntervalsProduceTheSameState() {
        let parameters = SpringParameters(response: 0.5, dampingRatio: 0.84)
        var direct = ScalarSpring(value: 5, velocity: -12, target: 80)
        var irregular = direct
        let durations = [0.004, 0.021, 0.008, 0.033, 0.017, 0.002, 0.115]
        let total = durations.reduce(0, +)

        direct.advance(using: SpringStep(parameters: parameters, duration: total))
        for duration in durations {
            irregular.advance(
                using: SpringStep(parameters: parameters, duration: duration)
            )
        }

        XCTAssertEqual(direct.value, irregular.value, accuracy: 1e-10)
        XCTAssertEqual(direct.velocity, irregular.velocity, accuracy: 1e-10)
    }

    func testRetargetingPreservesValueAndVelocity() {
        let parameters = SpringParameters(response: 0.44, dampingRatio: 0.86)
        let step = SpringStep(parameters: parameters, duration: 1.0 / 120)
        var spring = ScalarSpring(value: 0, target: 100)

        for _ in 0..<5 {
            spring.advance(using: step)
        }
        let value = spring.value
        let velocity = spring.velocity
        spring.retarget(to: -20)

        XCTAssertEqual(spring.value, value)
        XCTAssertEqual(spring.velocity, velocity)
    }

    func testPointSpringAdvancesBothDimensionsAndSnapsExactly() {
        let parameters = SpringParameters(response: 0.4, dampingRatio: 0.9)
        var spring = PointSpring(value: .zero)
        spring.target = MotionPoint(x: 20, y: -12)
        spring.advance(using: SpringStep(parameters: parameters, duration: 0.1))

        XCTAssertNotEqual(spring.value, .zero)
        XCTAssertNotEqual(spring.value, spring.target)

        spring.snapToTarget()
        XCTAssertEqual(spring.value, MotionPoint(x: 20, y: -12))
        XCTAssertEqual(spring.velocity, .zero)
        XCTAssertTrue(
            spring.isSettled(positionTolerance: 0, velocityTolerance: 0)
        )
    }
}
