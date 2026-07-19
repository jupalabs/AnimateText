import Foundation

struct LinearTransition: Equatable, Sendable {
    private(set) var value: Double
    private(set) var target: Double
    private var startValue: Double
    private var duration: TimeInterval
    private var elapsed: TimeInterval
    private var delayRemaining: TimeInterval

    init(value: Double) {
        self.value = value
        target = value
        startValue = value
        duration = 0
        elapsed = 0
        delayRemaining = 0
    }

    mutating func retarget(
        to target: Double,
        duration: TimeInterval,
        delay: TimeInterval = 0
    ) {
        self.target = target
        startValue = value
        self.duration = max(duration, 0)
        elapsed = 0
        delayRemaining = max(delay, 0)

        if self.duration == 0, delayRemaining == 0 {
            value = target
        }
    }

    mutating func advance(by duration: TimeInterval) {
        var remaining = max(duration, 0)

        if delayRemaining > 0 {
            let consumed = min(delayRemaining, remaining)
            delayRemaining -= consumed
            remaining -= consumed
        }

        guard delayRemaining == 0 else { return }
        guard self.duration > 0 else {
            value = target
            return
        }
        guard remaining > 0 else { return }

        elapsed = min(elapsed + remaining, self.duration)
        let progress = elapsed / self.duration
        value = startValue + (target - startValue) * progress
    }

    mutating func snapToTarget() {
        value = target
        startValue = target
        duration = 0
        elapsed = 0
        delayRemaining = 0
    }

    var isSettled: Bool {
        delayRemaining == 0
            && (duration == 0 || elapsed >= duration)
            && abs(value - target) <= 1e-9
    }
}
