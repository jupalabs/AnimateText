#if canImport(UIKit)
import UIKit

/// A UIKit view that morphs a single line of arbitrary text while preserving
/// shared textual units across updates.
@MainActor
public final class TextMorphLabel: UIView {
    private struct SnapshotCacheEntry {
        let text: String
        let font: UIFont
        let color: UIColor
        let scale: CGFloat
        let granularity: TextMorphGranularity
        let snapshot: TextLineSnapshot

        func matches(
            text: String,
            font: UIFont,
            color: UIColor,
            scale: CGFloat,
            granularity: TextMorphGranularity
        ) -> Bool {
            self.text == text
                && self.font == font
                && self.color.isEqual(color)
                && abs(self.scale - scale) <= 0.001
                && self.granularity == granularity
        }
    }

    private static let maximumCachedSnapshotCount = 3
    private static let maximumCachedSnapshotPixelCount = 1_500_000

    private var storedText = ""
    private var lastSnapshotScale: CGFloat = 0
    private var suppressesPropertyRebuild = false
    private var snapshotCache: [SnapshotCacheEntry] = []

    private lazy var morphEngine: TextMorphEngine = {
        let engine = TextMorphEngine(hostLayer: layer)
        engine.onPresentationSizeChange = { [weak self] in
            guard let self else { return }
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
        engine.onCompletion = { [weak self] in
            self?.onAnimationCompletion?()
        }
        return engine
    }()

    /// The complete target text exposed to accessibility and rendering.
    /// Assigning a different value starts a morph using ``animation``.
    public var text: String {
        get { storedText }
        set { setText(newValue, animated: true) }
    }

    /// The font used to shape and render the line.
    public var font: UIFont = .preferredFont(forTextStyle: .body) {
        didSet {
            guard !suppressesPropertyRebuild, oldValue != font else { return }
            rebuildForStyleChange()
        }
    }

    /// The foreground color of the rendered text. Dynamic colors are resolved
    /// against the view's current trait collection.
    public var textColor: UIColor = .label {
        didSet {
            guard !suppressesPropertyRebuild,
                !oldValue.isEqual(textColor)
            else { return }
            rebuildForStyleChange()
        }
    }

    /// The transition used for subsequent text updates.
    public var animation: TextMorphAnimation = .default

    /// The preferred reconciliation granularity.
    public var granularity: TextMorphGranularity = .automatic {
        didSet {
            guard !suppressesPropertyRebuild,
                oldValue != granularity
            else { return }
            rebuildForStyleChange()
        }
    }

    /// Horizontal alignment when the view is wider than its intrinsic line.
    public var textAlignment: TextMorphAlignment = .natural {
        didSet {
            guard !suppressesPropertyRebuild,
                oldValue != textAlignment
            else { return }
            setNeedsLayout()
        }
    }

    /// Controls whether this UIKit view reports its interpolated intrinsic size
    /// during a morph. The SwiftUI adapter manages its own animated frame and
    /// disables this automatically.
    public var animatesIntrinsicContentSize = true {
        didSet {
            morphEngine.animatesIntrinsicSize = animatesIntrinsicContentSize
            invalidateIntrinsicContentSize()
        }
    }

    /// Called on the main actor when the most recent requested morph reaches
    /// its exact target representation. Interrupted generations do not call it.
    public var onAnimationCompletion: (() -> Void)?

    /// Creates a morphing UIKit text label.
    ///
    /// - Parameters:
    ///   - text: The complete initial line.
    ///   - font: The uniform font used for shaping and rendering.
    ///   - textColor: The dynamic or fixed text color.
    ///   - animation: The transition used for subsequent text changes.
    ///   - granularity: The preferred unit of identity reconciliation.
    ///   - textAlignment: Horizontal alignment when bounds exceed the line.
    public init(
        text: String,
        font: UIFont = .preferredFont(forTextStyle: .body),
        textColor: UIColor = .label,
        animation: TextMorphAnimation = .default,
        granularity: TextMorphGranularity = .automatic,
        textAlignment: TextMorphAlignment = .natural
    ) {
        storedText = text
        self.font = font
        self.textColor = textColor
        self.animation = animation
        self.granularity = granularity
        self.textAlignment = textAlignment
        super.init(frame: .zero)
        commonInit()
    }

    /// Creates an initially empty morphing label with the supplied frame.
    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    /// Creates an initially empty morphing label from an archive.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Updates the target text.
    ///
    /// - Parameters:
    ///   - text: The new complete line.
    ///   - animated: Pass `false` to move directly to the new presentation.
    public func setText(_ text: String, animated: Bool) {
        guard text != storedText else { return }

        updateText(
            to: text,
            animated: animated,
            forceReplacement: false,
            notifyCompletion: true
        )
    }

    func apply(
        text: String,
        font: UIFont,
        textColor: UIColor,
        animation: TextMorphAnimation,
        granularity: TextMorphGranularity,
        textAlignment: TextMorphAlignment,
        animated: Bool,
        onAnimationCompletion: (() -> Void)?
    ) {
        let styleChanged =
            self.font != font
            || !self.textColor.isEqual(textColor)
            || self.granularity != granularity
        let alignmentChanged = self.textAlignment != textAlignment
        let textChanged = storedText != text

        suppressesPropertyRebuild = true
        self.font = font
        self.textColor = textColor
        self.animation = animation
        self.granularity = granularity
        self.textAlignment = textAlignment
        suppressesPropertyRebuild = false
        self.onAnimationCompletion = onAnimationCompletion

        if textChanged {
            updateText(
                to: text,
                animated: animated,
                forceReplacement: styleChanged,
                notifyCompletion: true
            )
        } else if styleChanged {
            rebuildForStyleChange()
        } else if alignmentChanged {
            setNeedsLayout()
        }
    }

    public override var intrinsicContentSize: CGSize {
        animatesIntrinsicContentSize
            ? morphEngine.presentationSize
            : morphEngine.targetSize
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        intrinsicContentSize
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        morphEngine.layout(
            in: bounds,
            alignment: textAlignment,
            layoutDirection: effectiveUserInterfaceLayoutDirection
        )
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()

        guard window != nil else {
            morphEngine.cancelForRemovalFromWindow()
            return
        }

        let scale = effectiveDisplayScale
        if lastSnapshotScale > 0, abs(scale - lastSnapshotScale) > 0.001 {
            rebuildForStyleChange()
        }
    }
}

private extension TextMorphLabel {
    func updateText(
        to text: String,
        animated: Bool,
        forceReplacement: Bool,
        notifyCompletion: Bool
    ) {
        storedText = text
        accessibilityLabel = text
        let snapshot = makeSnapshot()
        let reduceMotion =
            animation.respectsReducedMotion
            && UIAccessibility.isReduceMotionEnabled
        let shouldCrossfade =
            reduceMotion
            && UIAccessibility.prefersCrossFadeTransitions
        let canAnimate =
            animated
            && window != nil
            && (!reduceMotion || shouldCrossfade)

        morphEngine.update(
            to: snapshot,
            animation: animation,
            animated: canAnimate,
            transitionStyle: shouldCrossfade ? .crossfade : .motion,
            forceReplacement: forceReplacement,
            fontSize: font.pointSize,
            notifyCompletion: notifyCompletion
        )
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func commonInit() {
        isOpaque = false
        isUserInteractionEnabled = false
        clipsToBounds = false
        layer.masksToBounds = false
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        accessibilityLabel = storedText

        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)

        morphEngine.animatesIntrinsicSize = animatesIntrinsicContentSize
        morphEngine.setInitialSnapshot(makeSnapshot())

        registerForTraitChanges([
            UITraitUserInterfaceStyle.self,
            UITraitDisplayScale.self,
        ]) { (view: TextMorphLabel, _) in
            view.rebuildForStyleChange()
        }
        registerForTraitChanges([UITraitLayoutDirection.self]) {
            (view: TextMorphLabel, _) in
            view.setNeedsLayout()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityMotionPreferenceDidChange),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidReceiveMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    var effectiveDisplayScale: CGFloat {
        let scale = window?.screen.scale ?? traitCollection.displayScale
        return max(scale, 1)
    }

    func makeSnapshot() -> TextLineSnapshot {
        let scale = effectiveDisplayScale
        let color = textColor.resolvedColor(with: traitCollection)
        lastSnapshotScale = scale

        if let cacheIndex = snapshotCache.firstIndex(where: {
            $0.matches(
                text: storedText,
                font: font,
                color: color,
                scale: scale,
                granularity: granularity
            )
        }) {
            let entry = snapshotCache.remove(at: cacheIndex)
            snapshotCache.insert(entry, at: 0)
            return entry.snapshot
        }

        let snapshot = TextLineSnapshot.make(
            text: storedText,
            font: font,
            color: color,
            scale: scale,
            granularity: granularity
        )
        let pixelCount = snapshot.image.map { image in
            image.width.multipliedReportingOverflow(by: image.height)
        }
        if let pixelCount,
            !pixelCount.overflow,
            pixelCount.partialValue <= Self.maximumCachedSnapshotPixelCount
        {
            snapshotCache.insert(
                SnapshotCacheEntry(
                    text: storedText,
                    font: font,
                    color: color,
                    scale: scale,
                    granularity: granularity,
                    snapshot: snapshot
                ),
                at: 0
            )
            if snapshotCache.count > Self.maximumCachedSnapshotCount {
                snapshotCache.removeLast(
                    snapshotCache.count - Self.maximumCachedSnapshotCount
                )
            }
        }
        return snapshot
    }

    func rebuildForStyleChange() {
        guard isViewLoadedForMorphing else { return }
        let snapshot = makeSnapshot()
        morphEngine.update(
            to: snapshot,
            animation: .disabled,
            animated: false,
            forceReplacement: true,
            fontSize: font.pointSize,
            notifyCompletion: false
        )
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    var isViewLoadedForMorphing: Bool {
        // Accessing the lazy engine during initialization is intentional, but a
        // property observer can run before `super.init` only through future API
        // changes. A nonzero snapshot scale marks completed common setup.
        lastSnapshotScale > 0
    }

    @objc func accessibilityMotionPreferenceDidChange() {
        if animation.respectsReducedMotion,
            UIAccessibility.isReduceMotionEnabled
        {
            morphEngine.finishCurrentAnimation(notifyCompletion: true)
        }
    }

    @objc func applicationDidEnterBackground() {
        morphEngine.cancelForRemovalFromWindow()
    }

    @objc func applicationDidReceiveMemoryWarning() {
        snapshotCache.removeAll(keepingCapacity: true)
    }
}
#endif
