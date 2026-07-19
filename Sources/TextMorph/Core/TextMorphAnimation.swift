import Foundation

/// The timing and visual character of a text morph.
///
/// Position, scale, and intrinsic-size changes use a physical damped spring.
/// Opacity remains a short linear transition so entering and exiting text does
/// not linger or flash during rapid updates.
public struct TextMorphAnimation: Hashable, Sendable {
    /// Whether updates should animate.
    public let isEnabled: Bool

    /// The period, in seconds, of the corresponding undamped spring.
    /// Smaller values feel faster.
    public let response: TimeInterval

    /// The damping ratio of the spring. `1` is critically damped; values below
    /// `1` may overshoot.
    public let dampingRatio: Double

    /// The duration of insertion fades, in seconds.
    public let opacityDuration: TimeInterval

    /// The delay before a newly inserted unit begins fading in.
    public let insertionDelay: TimeInterval

    /// The initial scale of inserted units and final scale of removed units.
    public let scale: Double

    /// A restrained vertical displacement expressed as a fraction of the
    /// current font size.
    public let verticalOffset: Double

    /// Whether the system Reduce Motion preference should override motion.
    public let respectsReducedMotion: Bool

    /// Creates a text-morph transition.
    ///
    /// - Parameters:
    ///   - isEnabled: Whether updates animate.
    ///   - response: The period, in seconds, of the corresponding undamped
    ///     spring. Smaller values settle faster.
    ///   - dampingRatio: The spring's damping ratio. `1` is critically damped.
    ///   - opacityDuration: The insertion fade duration, in seconds.
    ///   - insertionDelay: The delay before inserted text fades in.
    ///   - scale: The initial insertion and final removal scale.
    ///   - verticalOffset: The vertical travel as a fraction of font size.
    ///   - respectsReducedMotion: Whether accessibility motion preferences
    ///     override this transition.
    public init(
        isEnabled: Bool = true,
        response: TimeInterval = 0.44,
        dampingRatio: Double = 0.86,
        opacityDuration: TimeInterval = 0.14,
        insertionDelay: TimeInterval = 0.03,
        scale: Double = 0.96,
        verticalOffset: Double = 0.06,
        respectsReducedMotion: Bool = true
    ) {
        precondition(
            response.isFinite && response > 0,
            "response must be finite and greater than zero"
        )
        precondition(
            dampingRatio.isFinite && dampingRatio >= 0,
            "dampingRatio must be finite and cannot be negative"
        )
        precondition(
            opacityDuration.isFinite && opacityDuration >= 0,
            "opacityDuration must be finite and cannot be negative"
        )
        precondition(
            insertionDelay.isFinite && insertionDelay >= 0,
            "insertionDelay must be finite and cannot be negative"
        )
        precondition(
            scale.isFinite && scale > 0,
            "scale must be finite and greater than zero"
        )
        precondition(
            verticalOffset.isFinite && verticalOffset >= 0,
            "verticalOffset must be finite and cannot be negative"
        )

        self.isEnabled = isEnabled
        self.response = response
        self.dampingRatio = dampingRatio
        self.opacityDuration = opacityDuration
        self.insertionDelay = insertionDelay
        self.scale = scale
        self.verticalOffset = verticalOffset
        self.respectsReducedMotion = respectsReducedMotion
    }

    /// A composed default with a quick response and nearly imperceptible
    /// overshoot.
    public static let `default` = TextMorphAnimation()

    /// A critically damped, slightly slower transition.
    public static let smooth = TextMorphAnimation(
        response: 0.52,
        dampingRatio: 1,
        opacityDuration: 0.15,
        insertionDelay: 0.035,
        scale: 0.97,
        verticalOffset: 0.04
    )

    /// A fast transition for compact, frequently updated controls.
    public static let snappy = TextMorphAnimation(
        response: 0.32,
        dampingRatio: 0.9,
        opacityDuration: 0.1,
        insertionDelay: 0.02,
        scale: 0.97,
        verticalOffset: 0.04
    )

    /// A more expressive spring with a controlled amount of overshoot.
    public static let bouncy = TextMorphAnimation(
        response: 0.5,
        dampingRatio: 0.72,
        opacityDuration: 0.14,
        insertionDelay: 0.03,
        scale: 0.94,
        verticalOffset: 0.08
    )

    /// Disables all interpolation and updates immediately.
    public static let disabled = TextMorphAnimation(isEnabled: false)
}
