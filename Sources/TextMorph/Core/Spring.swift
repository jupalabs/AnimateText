import Foundation

struct SpringParameters: Equatable, Sendable {
    let response: TimeInterval
    let dampingRatio: Double

    init(response: TimeInterval, dampingRatio: Double) {
        // Sub-microsecond response values are visually equivalent to a snap and
        // can overflow the angular-frequency calculation.
        self.response =
            response.isFinite
            ? max(response, 0.000_001)
            : TextMorphAnimation.default.response
        self.dampingRatio =
            dampingRatio.isFinite
            ? max(dampingRatio, 0)
            : 1
    }

    init(animation: TextMorphAnimation) {
        self.init(
            response: animation.response,
            dampingRatio: animation.dampingRatio
        )
    }

    var naturalFrequency: Double {
        2 * .pi / response
    }
}

/// A state transition matrix for an exact damped harmonic oscillator step.
/// The coefficients are computed once per frame and shared by every scalar
/// spring owned by a view.
struct SpringStep: Equatable, Sendable {
    let positionFromPosition: Double
    let positionFromVelocity: Double
    let velocityFromPosition: Double
    let velocityFromVelocity: Double

    init(parameters: SpringParameters, duration: TimeInterval) {
        let duration = max(duration, 0)
        let omega = parameters.naturalFrequency
        let damping = parameters.dampingRatio
        let criticalTolerance = 1e-7

        if damping < 1 - criticalTolerance {
            let dampedOmega = omega * sqrt(1 - damping * damping)
            let envelope = exp(-damping * omega * duration)
            let sine = sin(dampedOmega * duration)
            let cosine = cos(dampedOmega * duration)
            let dampingTerm = damping * omega / dampedOmega

            positionFromPosition = envelope * (cosine + dampingTerm * sine)
            positionFromVelocity = envelope * sine / dampedOmega
            velocityFromPosition =
                -envelope * omega * omega * sine
                / dampedOmega
            velocityFromVelocity = envelope * (cosine - dampingTerm * sine)
        } else if damping <= 1 + criticalTolerance {
            let envelope = exp(-omega * duration)
            positionFromPosition = envelope * (1 + omega * duration)
            positionFromVelocity = envelope * duration
            velocityFromPosition = -envelope * omega * omega * duration
            velocityFromVelocity = envelope * (1 - omega * duration)
        } else {
            let root = sqrt(damping - 1) * sqrt(damping + 1)
            let rootSum = damping + root
            // `(damping - root) * (damping + root) == 1`. Using
            // the reciprocal avoids catastrophic cancellation for heavily
            // overdamped springs.
            let firstRoot = -omega / rootSum
            let secondRoot = -omega * rootSum

            guard rootSum.isFinite, secondRoot.isFinite else {
                if duration == 0 {
                    positionFromPosition = 1
                    positionFromVelocity = 0
                    velocityFromPosition = 0
                    velocityFromVelocity = 1
                } else {
                    // At an unrepresentably large damping ratio, the fast mode
                    // decays below floating-point precision immediately while
                    // the slow mode is effectively stationary.
                    positionFromPosition = 1
                    positionFromVelocity = 0
                    velocityFromPosition = 0
                    velocityFromVelocity = 0
                }
                return
            }
            let denominator = firstRoot - secondRoot
            let firstEnvelope = exp(firstRoot * duration)
            let secondEnvelope = exp(secondRoot * duration)

            positionFromPosition =
                (-secondRoot * firstEnvelope
                    + firstRoot * secondEnvelope) / denominator
            positionFromVelocity = (firstEnvelope - secondEnvelope) / denominator
            velocityFromPosition =
                firstRoot * secondRoot
                * (secondEnvelope - firstEnvelope) / denominator
            velocityFromVelocity =
                (firstRoot * firstEnvelope
                    - secondRoot * secondEnvelope) / denominator
        }
    }
}

struct ScalarSpring: Equatable, Sendable {
    var value: Double
    var velocity: Double
    var target: Double

    init(value: Double, velocity: Double = 0, target: Double? = nil) {
        self.value = value
        self.velocity = velocity
        self.target = target ?? value
    }

    mutating func retarget(to target: Double) {
        self.target = target
    }

    mutating func advance(using step: SpringStep) {
        let displacement = value - target
        let nextDisplacement =
            step.positionFromPosition * displacement
            + step.positionFromVelocity * velocity
        let nextVelocity =
            step.velocityFromPosition * displacement
            + step.velocityFromVelocity * velocity
        value = target + nextDisplacement
        velocity = nextVelocity
    }

    mutating func snapToTarget() {
        value = target
        velocity = 0
    }

    func isSettled(
        positionTolerance: Double,
        velocityTolerance: Double
    ) -> Bool {
        abs(value - target) <= positionTolerance
            && abs(velocity) <= velocityTolerance
    }
}

struct MotionPoint: Equatable, Hashable, Sendable {
    var x: Double
    var y: Double

    static let zero = MotionPoint(x: 0, y: 0)

    static func + (lhs: MotionPoint, rhs: MotionPoint) -> MotionPoint {
        MotionPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func - (lhs: MotionPoint, rhs: MotionPoint) -> MotionPoint {
        MotionPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    func distanceSquared(to other: MotionPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return dx * dx + dy * dy
    }
}

struct PointSpring: Equatable, Sendable {
    var x: ScalarSpring
    var y: ScalarSpring

    init(value: MotionPoint, velocity: MotionPoint = .zero) {
        x = ScalarSpring(value: value.x, velocity: velocity.x)
        y = ScalarSpring(value: value.y, velocity: velocity.y)
    }

    var value: MotionPoint {
        MotionPoint(x: x.value, y: y.value)
    }

    var velocity: MotionPoint {
        MotionPoint(x: x.velocity, y: y.velocity)
    }

    var target: MotionPoint {
        get { MotionPoint(x: x.target, y: y.target) }
        set {
            x.target = newValue.x
            y.target = newValue.y
        }
    }

    mutating func advance(using step: SpringStep) {
        x.advance(using: step)
        y.advance(using: step)
    }

    mutating func snapToTarget() {
        x.snapToTarget()
        y.snapToTarget()
    }

    func isSettled(
        positionTolerance: Double,
        velocityTolerance: Double
    ) -> Bool {
        x.isSettled(
            positionTolerance: positionTolerance,
            velocityTolerance: velocityTolerance
        )
            && y.isSettled(
                positionTolerance: positionTolerance,
                velocityTolerance: velocityTolerance
            )
    }
}
