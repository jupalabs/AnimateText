#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// A SwiftUI view that morphs a single line of arbitrary text.
@MainActor
public struct TextMorph: View {
    private var text: String
    private var uiFont: UIFont
    private var uiColor: UIColor
    private var morphAnimation: TextMorphAnimation
    private var morphGranularity: TextMorphGranularity
    private var completion: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    /// Creates a morphing SwiftUI text view.
    ///
    /// - Parameters:
    ///   - text: The complete target line.
    ///   - font: The uniform font used for shaping and rendering.
    ///   - textColor: The dynamic or fixed text color.
    ///   - animation: The transition used when `text` changes.
    ///   - granularity: The preferred unit of identity reconciliation.
    ///   - onAnimationCompletion: Called when the latest uninterrupted morph
    ///     reaches its exact target.
    public init(
        _ text: String,
        font: UIFont = .preferredFont(forTextStyle: .body),
        textColor: UIColor = .label,
        animation: TextMorphAnimation = .default,
        granularity: TextMorphGranularity = .automatic,
        onAnimationCompletion: (() -> Void)? = nil
    ) {
        self.text = text
        uiFont = font
        uiColor = textColor
        morphAnimation = animation
        morphGranularity = granularity
        completion = onAnimationCompletion
    }

    /// The composed morphing text content.
    public var body: some View {
        let metrics = TextLineMetrics.measure(text: text, font: uiFont)
        let key = LayoutAnimationKey(size: metrics.size)
        let shouldAnimateLayout =
            morphAnimation.isEnabled
            && !(morphAnimation.respectsReducedMotion && reduceMotion)

        TextMorphRepresentable(
            text: text,
            font: uiFont,
            color: uiColor,
            animation: morphAnimation,
            granularity: morphGranularity,
            layoutDirection: layoutDirection,
            completion: completion
        )
        .frame(width: metrics.size.width, height: metrics.size.height)
        .animation(
            shouldAnimateLayout ? morphAnimation.swiftUIAnimation : nil,
            value: key
        )
        .alignmentGuide(.firstTextBaseline) { _ in metrics.baseline }
        .alignmentGuide(.lastTextBaseline) { _ in metrics.baseline }
    }

    /// Returns a copy using the supplied UIKit font.
    public func textFont(_ font: UIFont) -> TextMorph {
        var copy = self
        copy.uiFont = font
        return copy
    }

    /// Returns a copy using the supplied dynamic or fixed UIKit color.
    public func textColor(_ color: UIColor) -> TextMorph {
        var copy = self
        copy.uiColor = color
        return copy
    }

    /// Returns a copy using the supplied morph transition.
    public func morphAnimation(
        _ animation: TextMorphAnimation
    ) -> TextMorph {
        var copy = self
        copy.morphAnimation = animation
        return copy
    }

    /// Returns a copy using the supplied reconciliation granularity.
    public func granularity(
        _ granularity: TextMorphGranularity
    ) -> TextMorph {
        var copy = self
        copy.morphGranularity = granularity
        return copy
    }

    /// Returns a copy whose closure runs after the latest morph settles.
    public func onAnimationCompletion(
        _ completion: (() -> Void)?
    ) -> TextMorph {
        var copy = self
        copy.completion = completion
        return copy
    }
}

private struct LayoutAnimationKey: Equatable {
    let width: CGFloat
    let height: CGFloat

    init(size: CGSize) {
        width = size.width
        height = size.height
    }
}

private extension TextMorphAnimation {
    var swiftUIAnimation: Animation {
        let omega = 2 * Double.pi / response
        return .interpolatingSpring(
            mass: 1,
            stiffness: omega * omega,
            damping: 2 * dampingRatio * omega,
            initialVelocity: 0
        )
    }
}

@MainActor
private struct TextMorphRepresentable: UIViewRepresentable {
    let text: String
    let font: UIFont
    let color: UIColor
    let animation: TextMorphAnimation
    let granularity: TextMorphGranularity
    let layoutDirection: LayoutDirection
    let completion: (() -> Void)?

    func makeUIView(context: Context) -> TextMorphLabel {
        let view = TextMorphLabel(
            text: text,
            font: font,
            textColor: color,
            animation: animation,
            granularity: granularity,
            textAlignment: .natural
        )
        view.animatesIntrinsicContentSize = false
        view.onAnimationCompletion = completion
        applyLayoutDirection(to: view)
        return view
    }

    func updateUIView(_ view: TextMorphLabel, context: Context) {
        applyLayoutDirection(to: view)
        view.apply(
            text: text,
            font: font,
            textColor: color,
            animation: animation,
            granularity: granularity,
            textAlignment: .natural,
            animated: !context.transaction.disablesAnimations,
            onAnimationCompletion: completion
        )
    }

    static func dismantleUIView(
        _ view: TextMorphLabel,
        coordinator: Void
    ) {
        view.onAnimationCompletion = nil
    }

    private func applyLayoutDirection(to view: TextMorphLabel) {
        view.semanticContentAttribute =
            layoutDirection == .leftToRight
            ? .forceLeftToRight
            : .forceRightToLeft
    }
}
#endif
