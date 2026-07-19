#if canImport(UIKit)
import QuartzCore
import UIKit

@MainActor
protocol DisplayLinkParticipant: AnyObject {
    /// Advances to the display link's target presentation time and returns
    /// whether another frame is required.
    func advanceFrame(by duration: TimeInterval) -> Bool
}

@MainActor
final class SharedDisplayLinkDriver {
    static let shared = SharedDisplayLinkDriver()

    private final class WeakParticipant {
        weak var value: (any DisplayLinkParticipant)?

        init(_ value: any DisplayLinkParticipant) {
            self.value = value
        }
    }

    @MainActor
    private final class DisplayLinkProxy: NSObject {
        weak var owner: SharedDisplayLinkDriver?

        @objc func displayLinkDidFire(_ displayLink: CADisplayLink) {
            owner?.displayLinkDidFire(displayLink)
        }
    }

    private var participants: [WeakParticipant] = []
    private var displayLink: CADisplayLink?
    private var proxy: DisplayLinkProxy?
    private var previousTargetTimestamp: CFTimeInterval?
    private var isAdvancingParticipants = false

    private init() {}

    func register(_ participant: any DisplayLinkParticipant) {
        if !isAdvancingParticipants {
            pruneParticipants()
        }
        guard !participants.contains(where: { $0.value === participant }) else {
            return
        }

        participants.append(WeakParticipant(participant))
        startIfNeeded()
    }

    func unregister(_ participant: any DisplayLinkParticipant) {
        if isAdvancingParticipants {
            // Keep the array structurally stable until the frame callback ends.
            // WeakParticipant is a reference type, so clearing it does not
            // trigger copy-on-write storage or invalidate an index.
            for entry in participants where entry.value === participant {
                entry.value = nil
            }
            return
        }

        participants.removeAll {
            $0.value == nil || $0.value === participant
        }
        stopIfEmpty()
    }

    private func startIfNeeded() {
        guard displayLink == nil, !participants.isEmpty else { return }

        let proxy = DisplayLinkProxy()
        proxy.owner = self
        let displayLink = CADisplayLink(
            target: proxy,
            selector: #selector(DisplayLinkProxy.displayLinkDidFire(_:))
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

    private func displayLinkDidFire(_ displayLink: CADisplayLink) {
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

        advanceParticipants(by: duration)
    }

    func advanceParticipants(by duration: TimeInterval) {
        // Participants are allowed to finish (and therefore unregister)
        // synchronously from `advanceFrame`. Defer structural removal until the
        // frame ends so the hot path needs no temporary participant array.
        isAdvancingParticipants = true
        let frameParticipantCount = participants.count
        for index in 0..<frameParticipantCount {
            guard let participant = participants[index].value else { continue }
            if !participant.advanceFrame(by: duration) {
                participants[index].value = nil
            }
        }
        isAdvancingParticipants = false

        stopIfEmpty()
    }

    private func pruneParticipants() {
        participants.removeAll { $0.value == nil }
    }

    private func stopIfEmpty() {
        pruneParticipants()
        guard participants.isEmpty else { return }

        displayLink?.invalidate()
        displayLink = nil
        proxy = nil
        previousTargetTimestamp = nil
    }
}
#endif
