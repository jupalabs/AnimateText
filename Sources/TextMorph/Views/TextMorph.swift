import AppKit
import SwiftUI

/// A SwiftUI view that morphs a single line of arbitrary text using AppKit,
/// Core Text, and Core Animation.
@MainActor
public struct TextMorph: View {
    private var text: String
    private var appKitFont: NSFont
    private var appKitColor: NSColor
    private var morphAnimation: TextMorphAnimation
    private var morphGranularity: TextMorphGranularity
    private var morphTruncationMode: TextMorphTruncationMode
    private var completion: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    /// Creates a morphing SwiftUI text view.
    public init(
        _ text: String,
        font: NSFont = .preferredFont(forTextStyle: .body, options: [:]),
        textColor: NSColor = .labelColor,
        animation: TextMorphAnimation = .default,
        granularity: TextMorphGranularity = .automatic,
        truncationMode: TextMorphTruncationMode = .tail,
        onAnimationCompletion: (() -> Void)? = nil
    ) {
        self.text = text
        appKitFont = font
        appKitColor = textColor
        morphAnimation = animation
        morphGranularity = granularity
        morphTruncationMode = truncationMode
        completion = onAnimationCompletion
    }

    public var body: some View {
        let metrics = TextLineMetrics.measure(text: text, font: appKitFont)
        let key = LayoutAnimationKey(size: metrics.size)
        let shouldAnimateLayout =
            morphAnimation.isEnabled
            && !(morphAnimation.respectsReducedMotion && reduceMotion)

        TextMorphRepresentable(
            text: text,
            font: appKitFont,
            color: appKitColor,
            animation: morphAnimation,
            granularity: morphGranularity,
            truncationMode: morphTruncationMode,
            reduceMotion: reduceMotion,
            layoutDirection: layoutDirection,
            completion: completion
        )
        .fixedSize(horizontal: false, vertical: true)
        .animation(
            shouldAnimateLayout ? morphAnimation.swiftUIAnimation : nil,
            value: key
        )
        .alignmentGuide(.firstTextBaseline) { _ in metrics.baseline }
        .alignmentGuide(.lastTextBaseline) { _ in metrics.baseline }
    }

    /// Returns a copy using the supplied AppKit font.
    public func textFont(_ font: NSFont) -> TextMorph {
        var copy = self
        copy.appKitFont = font
        return copy
    }

    /// Returns a copy using the supplied dynamic or fixed AppKit color.
    public func textColor(_ color: NSColor) -> TextMorph {
        var copy = self
        copy.appKitColor = color
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

    /// Returns a copy using the supplied ellipsis placement when compressed.
    public func textTruncation(
        _ truncationMode: TextMorphTruncationMode
    ) -> TextMorph {
        var copy = self
        copy.morphTruncationMode = truncationMode
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
private struct TextMorphRepresentable: NSViewRepresentable {
    let text: String
    let font: NSFont
    let color: NSColor
    let animation: TextMorphAnimation
    let granularity: TextMorphGranularity
    let truncationMode: TextMorphTruncationMode
    let reduceMotion: Bool
    let layoutDirection: LayoutDirection
    let completion: (() -> Void)?

    func makeNSView(context: Context) -> TextMorphView {
        let view = TextMorphView(
            text: text,
            font: font,
            textColor: color,
            animation: animation,
            granularity: granularity,
            textAlignment: .natural,
            truncationMode: truncationMode
        )
        view.animatesIntrinsicContentSize = false
        view.onAnimationCompletion = completion
        applyLayoutDirection(to: view)
        return view
    }

    func updateNSView(_ view: TextMorphView, context: Context) {
        applyLayoutDirection(to: view)
        view.apply(
            text: text,
            font: font,
            textColor: color,
            animation: animation,
            granularity: granularity,
            textAlignment: .natural,
            truncationMode: truncationMode,
            reduceMotion: reduceMotion,
            animated: !context.transaction.disablesAnimations,
            onAnimationCompletion: completion
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: TextMorphView,
        context: Context
    ) -> CGSize? {
        let ideal = nsView.idealContentSize
        let width: CGFloat
        if let proposedWidth = proposal.width, proposedWidth.isFinite {
            width = min(max(proposedWidth, 0), ideal.width)
        } else {
            width = ideal.width
        }
        return CGSize(width: width, height: ideal.height)
    }

    static func dismantleNSView(
        _ view: TextMorphView,
        coordinator: Void
    ) {
        view.prepareForDismantling()
    }

    private func applyLayoutDirection(to view: TextMorphView) {
        view.userInterfaceLayoutDirection =
            layoutDirection == .leftToRight
            ? .leftToRight
            : .rightToLeft
        view.needsLayout = true
    }
}
