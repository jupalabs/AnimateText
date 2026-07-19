import AppKit

/// An AppKit view that morphs a single line of arbitrary text while preserving
/// shared textual units across updates.
@MainActor
public final class TextMorphView: NSView {
    private struct SnapshotCacheEntry {
        let text: String
        let font: NSFont
        let color: NSColor
        let scale: CGFloat
        let granularity: TextMorphGranularity
        let snapshot: TextLineSnapshot

        func matches(
            text: String,
            font: NSFont,
            color: NSColor,
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
    private var renderedText = ""
    private var lastSnapshotScale: CGFloat = 0
    private var suppressesPropertyRebuild = false
    private var snapshotCache: [SnapshotCacheEntry] = []
    private var reduceMotionOverride: Bool?

    private lazy var displayLinkDriver = DisplayLinkDriver(sourceView: self)

    private lazy var morphEngine: TextMorphEngine = {
        guard let layer else {
            preconditionFailure("TextMorphView must be layer-backed")
        }

        let engine = TextMorphEngine(
            hostLayer: layer,
            displayLinkDriver: displayLinkDriver
        )
        engine.onPresentationSizeChange = { [weak self] in
            guard let self else { return }
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
        engine.onCompletion = { [weak self] in
            self?.onAnimationCompletion?()
        }
        return engine
    }()

    /// The complete target text exposed to accessibility. Assigning a
    /// different value starts a morph using ``animation``.
    public var text: String {
        get { storedText }
        set { setText(newValue, animated: true) }
    }

    /// The AppKit font used to shape, measure, and render the line.
    public var font: NSFont = .preferredFont(forTextStyle: .body, options: [:]) {
        didSet {
            guard !suppressesPropertyRebuild, oldValue != font else { return }
            rebuildForStyleChange()
        }
    }

    /// The foreground color. Semantic colors are resolved against the view's
    /// effective appearance before snapshots enter the cache.
    public var textColor: NSColor = .labelColor {
        didSet {
            guard !suppressesPropertyRebuild,
                !oldValue.isEqual(textColor)
            else {
                return
            }
            rebuildForStyleChange()
        }
    }

    /// The transition used for subsequent text updates.
    public var animation: TextMorphAnimation = .default

    /// The preferred unit of textual identity reconciliation.
    public var granularity: TextMorphGranularity = .automatic {
        didSet {
            guard !suppressesPropertyRebuild,
                oldValue != granularity
            else {
                return
            }
            rebuildForStyleChange()
        }
    }

    /// Horizontal alignment when the view is wider than its natural line.
    public var textAlignment: TextMorphAlignment = .natural {
        didSet {
            guard !suppressesPropertyRebuild,
                oldValue != textAlignment
            else {
                return
            }
            needsLayout = true
        }
    }

    /// Ellipsis placement when the view is narrower than the natural line.
    public var truncationMode: TextMorphTruncationMode = .tail {
        didSet {
            guard !suppressesPropertyRebuild,
                oldValue != truncationMode
            else {
                return
            }
            rebuildForStyleChange()
        }
    }

    /// Controls whether an unconstrained AppKit view reports the interpolated
    /// intrinsic size during a morph. Constrained views continue to report the
    /// natural line size so Auto Layout can make a stable compression decision.
    public var animatesIntrinsicContentSize = true {
        didSet {
            morphEngine.animatesIntrinsicSize = animatesIntrinsicContentSize
            invalidateIntrinsicContentSize()
        }
    }

    /// Called after the latest uninterrupted text update reaches its target.
    /// Interrupted generations do not call this closure.
    public var onAnimationCompletion: (() -> Void)?

    /// Creates a morphing AppKit text view.
    public init(
        text: String,
        font: NSFont = .preferredFont(forTextStyle: .body, options: [:]),
        textColor: NSColor = .labelColor,
        animation: TextMorphAnimation = .default,
        granularity: TextMorphGranularity = .automatic,
        textAlignment: TextMorphAlignment = .natural,
        truncationMode: TextMorphTruncationMode = .tail
    ) {
        storedText = text
        renderedText = text
        self.font = font
        self.textColor = textColor
        self.animation = animation
        self.granularity = granularity
        self.textAlignment = textAlignment
        self.truncationMode = truncationMode
        super.init(frame: .zero)
        commonInit()
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Updates the complete target text.
    public func setText(_ text: String, animated: Bool) {
        guard text != storedText else { return }

        updateText(
            to: text,
            animated: animated,
            forceReplacement: false,
            notifyCompletion: true
        )
    }

    public override var isFlipped: Bool { true }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    public override var intrinsicContentSize: NSSize {
        let naturalSize = naturalMetrics.size
        guard animatesIntrinsicContentSize,
            !isHorizontallyConstrained(naturalWidth: naturalSize.width)
        else {
            return naturalSize
        }
        return morphEngine.presentationSize
    }

    public override var firstBaselineOffsetFromTop: CGFloat {
        naturalMetrics.baseline
    }

    public override var lastBaselineOffsetFromBottom: CGFloat {
        let metrics = naturalMetrics
        return max(metrics.size.height - metrics.baseline, 0)
    }

    public override func layout() {
        super.layout()
        rebuildForAvailableWidthIfNeeded()
        morphEngine.layout(
            in: bounds,
            alignment: textAlignment,
            layoutDirection: userInterfaceLayoutDirection
        )
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerWindowObservers()
        displayLinkDriver.sourceViewEnvironmentDidChange()

        guard window != nil else {
            morphEngine.cancelForRemovalFromWindow()
            return
        }

        rebuildForBackingScaleIfNeeded()
        needsLayout = true
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        displayLinkDriver.sourceViewEnvironmentDidChange()
        rebuildForBackingScaleIfNeeded()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        rebuildForStyleChange()
    }

    public override func viewDidHide() {
        super.viewDidHide()
        morphEngine.cancelForRemovalFromWindow()
    }
}

extension TextMorphView {
    var idealContentSize: CGSize {
        naturalMetrics.size
    }

    var debugRenderedText: String {
        renderedText
    }

    func apply(
        text: String,
        font: NSFont,
        textColor: NSColor,
        animation: TextMorphAnimation,
        granularity: TextMorphGranularity,
        textAlignment: TextMorphAlignment,
        truncationMode: TextMorphTruncationMode,
        reduceMotion: Bool,
        animated: Bool,
        onAnimationCompletion: (() -> Void)?
    ) {
        let styleChanged =
            self.font != font
            || !self.textColor.isEqual(textColor)
            || self.granularity != granularity
            || self.truncationMode != truncationMode
        let alignmentChanged = self.textAlignment != textAlignment
        let textChanged = storedText != text

        suppressesPropertyRebuild = true
        self.font = font
        self.textColor = textColor
        self.animation = animation
        self.granularity = granularity
        self.textAlignment = textAlignment
        self.truncationMode = truncationMode
        suppressesPropertyRebuild = false
        reduceMotionOverride = reduceMotion
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
            needsLayout = true
        }
    }
}

private extension TextMorphView {
    var naturalMetrics: TextLineMetrics {
        TextLineMetrics.measure(text: storedText, font: font)
    }

    var effectiveDisplayScale: CGFloat {
        max(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1, 1)
    }

    var shouldReduceMotion: Bool {
        reduceMotionOverride
            ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var canAnimate: Bool {
        guard let window else { return false }
        return !isHiddenOrHasHiddenAncestor
            && !window.isMiniaturized
            && window.occlusionState.contains(.visible)
    }

    func updateText(
        to text: String,
        animated: Bool,
        forceReplacement: Bool,
        notifyCompletion: Bool
    ) {
        storedText = text
        setAccessibilityValue(text)
        let targetText = displayedText(for: bounds.width)

        guard targetText != renderedText else {
            invalidateIntrinsicContentSize()
            if notifyCompletion {
                onAnimationCompletion?()
            }
            return
        }

        renderedText = targetText
        let snapshot = makeSnapshot(text: targetText)
        let reduceMotion = animation.respectsReducedMotion && shouldReduceMotion

        morphEngine.update(
            to: snapshot,
            animation: animation,
            animated: animated && canAnimate,
            transitionStyle: reduceMotion ? .crossfade : .motion,
            forceReplacement: forceReplacement,
            fontSize: font.pointSize,
            notifyCompletion: notifyCompletion
        )
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    func commonInit() {
        wantsLayer = true
        if layer == nil {
            layer = CALayer()
        }
        layer?.masksToBounds = false

        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityValue(storedText)

        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)

        renderedText = storedText
        morphEngine.animatesIntrinsicSize = animatesIntrinsicContentSize
        morphEngine.setInitialSnapshot(makeSnapshot(text: renderedText))

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsDidChange(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    func displayedText(for availableWidth: CGFloat) -> String {
        guard availableWidth > 0 else { return storedText }
        return TextTruncator.truncate(
            storedText,
            toWidth: availableWidth,
            font: font,
            mode: truncationMode
        )
    }

    func makeSnapshot(text: String) -> TextLineSnapshot {
        let scale = effectiveDisplayScale
        let color = resolvedTextColor
        lastSnapshotScale = scale

        if let cacheIndex = snapshotCache.firstIndex(where: {
            $0.matches(
                text: text,
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
            text: text,
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
                    text: text,
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

    var resolvedTextColor: NSColor {
        var resolved = textColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = textColor.usingColorSpace(.sRGB) ?? textColor
        }
        return resolved
    }

    func rebuildForAvailableWidthIfNeeded() {
        let targetText = displayedText(for: bounds.width)
        guard targetText != renderedText else { return }
        renderedText = targetText
        rebuildSnapshotWithoutAnimation()
    }

    func rebuildForStyleChange() {
        guard lastSnapshotScale > 0 else { return }
        renderedText = displayedText(for: bounds.width)
        rebuildSnapshotWithoutAnimation()
    }

    func rebuildForBackingScaleIfNeeded() {
        guard lastSnapshotScale > 0,
            abs(effectiveDisplayScale - lastSnapshotScale) > 0.001
        else {
            return
        }
        displayLinkDriver.sourceViewEnvironmentDidChange()
        rebuildSnapshotWithoutAnimation()
    }

    func rebuildSnapshotWithoutAnimation() {
        let snapshot = makeSnapshot(text: renderedText)
        morphEngine.update(
            to: snapshot,
            animation: .disabled,
            animated: false,
            forceReplacement: true,
            fontSize: font.pointSize,
            notifyCompletion: false
        )
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    func isHorizontallyConstrained(naturalWidth: CGFloat) -> Bool {
        bounds.width > 0 && bounds.width + 0.5 < naturalWidth
    }

    func registerWindowObservers() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didChangeScreenNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didChangeOcclusionStateNotification,
        ]
        for name in names {
            center.removeObserver(self, name: name, object: nil)
        }

        guard let window else { return }
        for name in names {
            center.addObserver(
                self,
                selector: #selector(windowEnvironmentDidChange(_:)),
                name: name,
                object: window
            )
        }
    }

    @objc func accessibilityDisplayOptionsDidChange(_ notification: Notification) {
        guard animation.respectsReducedMotion, shouldReduceMotion else { return }
        morphEngine.finishCurrentAnimation(notifyCompletion: true)
    }

    @objc func windowEnvironmentDidChange(_ notification: Notification) {
        if notification.name == NSWindow.didChangeScreenNotification {
            displayLinkDriver.sourceViewEnvironmentDidChange()
            rebuildForBackingScaleIfNeeded()
        } else if !canAnimate {
            morphEngine.cancelForRemovalFromWindow()
        }
    }
}
