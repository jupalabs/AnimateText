import AppKit
import QuartzCore

@MainActor
protocol DisplayLinkParticipant: AnyObject {
    /// Advances to the display link's target presentation time and returns
    /// whether another frame is required.
    func advanceFrame(by duration: TimeInterval) -> Bool
}

/// Drives one morph from the display currently hosting its AppKit view.
///
/// AppKit creates display links from a view, window, or screen. Keeping one
/// driver per morph means a window moved between displays always follows the
/// correct refresh cadence without a process-global display assumption.
final class DisplayLinkDriver {
    @MainActor
    private final class Proxy: NSObject {
        weak var owner: DisplayLinkDriver?

        @objc func displayLinkDidFire(_ displayLink: CADisplayLink) {
            owner?.displayLinkDidFire(displayLink)
        }
    }

    private weak var sourceView: NSView?
    private weak var participant: (any DisplayLinkParticipant)?
    private var displayLink: CADisplayLink?
    private var proxy: Proxy?
    private var previousTargetTimestamp: CFTimeInterval?
    private var registrationGeneration: UInt64 = 0

    @MainActor
    init(sourceView: NSView? = nil) {
        self.sourceView = sourceView
    }

    deinit {
        displayLink?.invalidate()
    }

    @MainActor
    func start(_ participant: any DisplayLinkParticipant) {
        registrationGeneration &+= 1
        self.participant = participant
        startIfNeeded()
    }

    @MainActor
    func stop(_ participant: any DisplayLinkParticipant) {
        guard self.participant === participant else { return }
        registrationGeneration &+= 1
        self.participant = nil
        invalidate()
    }

    /// Rebinds an active link after the source view moves to another window or
    /// display. Idle drivers remain asleep.
    @MainActor
    func sourceViewEnvironmentDidChange() {
        restartIfActive()
    }

    /// Advances the participant directly. Tests use this deterministic seam;
    /// production calls it only from the display-link callback.
    @MainActor @discardableResult
    func advanceParticipant(by duration: TimeInterval) -> Bool {
        guard let participant else {
            invalidate()
            return false
        }

        let advancedGeneration = registrationGeneration
        let needsAnotherFrame = participant.advanceFrame(by: duration)
        if !needsAnotherFrame,
            registrationGeneration == advancedGeneration,
            self.participant === participant
        {
            registrationGeneration &+= 1
            self.participant = nil
            invalidate()
        }
        return needsAnotherFrame
    }
}

@MainActor
private extension DisplayLinkDriver {
    func startIfNeeded() {
        guard displayLink == nil,
            participant != nil,
            let sourceView,
            sourceView.window != nil
        else {
            return
        }

        let proxy = Proxy()
        proxy.owner = self
        let displayLink = sourceView.displayLink(
            target: proxy,
            selector: #selector(Proxy.displayLinkDidFire(_:))
        )
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: 60,
            maximum: 120,
            preferred: 120
        )
        displayLink.add(to: .main, forMode: .common)
        self.proxy = proxy
        self.displayLink = displayLink
        previousTargetTimestamp = nil
    }

    func restartIfActive() {
        guard participant != nil else { return }
        invalidate()
        startIfNeeded()
    }

    func invalidate() {
        displayLink?.invalidate()
        displayLink = nil
        proxy = nil
        previousTargetTimestamp = nil
    }

    func displayLinkDidFire(_ displayLink: CADisplayLink) {
        let targetTimestamp =
            displayLink.targetTimestamp > 0
            ? displayLink.targetTimestamp
            : displayLink.timestamp + displayLink.duration
        let duration: TimeInterval
        if let previousTargetTimestamp {
            duration = max(targetTimestamp - previousTargetTimestamp, 0)
        } else {
            let predictedDuration = targetTimestamp - displayLink.timestamp
            duration =
                predictedDuration > 0
                ? predictedDuration
                : displayLink.duration
        }
        previousTargetTimestamp = targetTimestamp

        advanceParticipant(by: duration)
    }
}
