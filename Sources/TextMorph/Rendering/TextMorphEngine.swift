import AppKit
import QuartzCore

@MainActor
final class TextMorphEngine: DisplayLinkParticipant {
    struct DebugTokenState: Equatable {
        let identifier: UInt64
        let value: String
        let position: MotionPoint
        let target: MotionPoint
        let velocity: MotionPoint
        let scale: Double
        let opacity: Double
    }

    enum TransitionStyle {
        case motion
        case crossfade
    }

    static let maximumAnimatedUnitCount = 256
    static let maximumAnimationDuration: TimeInterval = 10

    var onPresentationSizeChange: (() -> Void)?
    var onCompletion: (() -> Void)?
    var animatesIntrinsicSize = true

    private weak var hostLayer: CALayer?
    private let fullLineLayer = CALayer()
    private var currentSnapshot: TextLineSnapshot?
    private var targetTokens: [AnimatedToken] = []
    private var exitingTokens: [AnimatedToken] = []
    private var nextIdentifier: UInt64 = 0
    private var animation = TextMorphAnimation.default
    private var layoutBounds = CGRect.zero
    private var alignment = TextMorphAlignment.natural
    private var layoutDirection = NSUserInterfaceLayoutDirection.leftToRight
    private let displayLinkDriver: DisplayLinkDriver
    private var width = ScalarSpring(value: 0)
    private var height = ScalarSpring(value: 0)
    private var isActive = false
    private var shouldNotifyCompletion = false
    private var elapsedAnimationDuration: TimeInterval = 0

    init(
        hostLayer: CALayer,
        displayLinkDriver: DisplayLinkDriver = DisplayLinkDriver()
    ) {
        self.hostLayer = hostLayer
        self.displayLinkDriver = displayLinkDriver
        fullLineLayer.contentsGravity = .resize
        fullLineLayer.minificationFilter = .linear
        fullLineLayer.magnificationFilter = .linear
        fullLineLayer.zPosition = 0
    }

    var presentationSize: CGSize {
        CGSize(
            width: CGFloat(max(width.value, 0)),
            height: CGFloat(max(height.value, 0))
        )
    }

    var targetSize: CGSize {
        CGSize(
            width: CGFloat(max(width.target, 0)),
            height: CGFloat(max(height.target, 0))
        )
    }

    var debugTargetTokens: [DebugTokenState] {
        targetTokens.map(debugState(for:))
    }

    var debugExitingTokens: [DebugTokenState] {
        exitingTokens.map(debugState(for:))
    }

    var debugIsActive: Bool {
        isActive
    }

    func setInitialSnapshot(_ snapshot: TextLineSnapshot) {
        displayLinkDriver.stop(self)
        removeAllTokenLayers()
        exitingTokens.removeAll(keepingCapacity: true)
        isActive = false
        shouldNotifyCompletion = false
        elapsedAnimationDuration = 0
        currentSnapshot = snapshot
        width = ScalarSpring(value: Double(snapshot.metrics.size.width))
        height = ScalarSpring(value: Double(snapshot.metrics.size.height))
        targetTokens =
            snapshot
            .animationUnits(maximumCount: Self.maximumAnimatedUnitCount)
            .enumerated()
            .map { index, unit in
                makeRestingToken(
                    snapshot: snapshot,
                    unit: unit,
                    logicalIndex: index
                )
            }
        showFullLine(snapshot)
    }

    func update(
        to snapshot: TextLineSnapshot,
        animation: TextMorphAnimation,
        animated: Bool,
        transitionStyle: TransitionStyle = .motion,
        forceReplacement: Bool = false,
        fontSize: CGFloat,
        notifyCompletion: Bool = true
    ) {
        guard currentSnapshot != nil else {
            self.animation = animation
            setInitialSnapshot(snapshot)
            if notifyCompletion {
                onCompletion?()
            }
            return
        }

        shouldNotifyCompletion = notifyCompletion
        elapsedAnimationDuration = 0
        self.animation = animation
        let shouldAnimate = animated && animation.isEnabled
        guard shouldAnimate else {
            finishImmediately(
                at: snapshot,
                notifyCompletion: notifyCompletion
            )
            return
        }

        materializeTargetTokens()
        removeFullLineLayer()

        let oldTokens = targetTokens
        let newUnits: [TextVisualUnit]
        if transitionStyle == .crossfade {
            newUnits = snapshot.animationUnits(maximumCount: 0)
        } else {
            let oldUnitCount = currentSnapshot?.units.count ?? oldTokens.count
            let shouldUseWholeLine =
                max(oldUnitCount, snapshot.units.count)
                > Self.maximumAnimatedUnitCount
            newUnits = snapshot.animationUnits(
                maximumCount: shouldUseWholeLine ? 0 : Self.maximumAnimatedUnitCount
            )
        }

        let reconciliation: TextReconciliation
        if forceReplacement {
            reconciliation = TextReconciliation(
                matches: [],
                insertionIndices: Array(newUnits.indices),
                removalIndices: Array(oldTokens.indices),
                changeRatio: oldTokens.isEmpty && newUnits.isEmpty ? 0 : 1
            )
        } else {
            reconciliation = TextReconciler.reconcile(
                old: oldTokens.map(\.value),
                new: newUnits.map(\.value)
            )
        }

        let targetOrigin = layoutOrigin(for: snapshot)
        var newTokens = Array<AnimatedToken?>(
            repeating: nil,
            count: newUnits.count
        )
        var persistentByNewIndex: [(Int, AnimatedToken)] = []
        persistentByNewIndex.reserveCapacity(reconciliation.matches.count)

        performWithoutLayerActions {
            for match in reconciliation.matches {
                let token = oldTokens[match.oldIndex]
                let unit = newUnits[match.newIndex]
                configure(
                    token: token,
                    snapshot: snapshot,
                    unit: unit,
                    logicalIndex: match.newIndex,
                    zBase: 10
                )
                token.position.target = MotionPoint(
                    x: Double(targetOrigin.x + unit.anchor.x),
                    y: Double(targetOrigin.y + unit.anchor.y)
                )
                token.scale.retarget(to: 1)
                if token.opacity.value < 1 {
                    token.opacity.retarget(
                        to: 1,
                        duration: min(animation.opacityDuration * 0.5, 0.08)
                    )
                } else {
                    token.opacity.retarget(to: 1, duration: 0)
                }
                newTokens[match.newIndex] = token
                persistentByNewIndex.append((match.newIndex, token))
            }
        }

        let resurrectionCandidateCount = exitingTokens.count
        let movementScale = max(reconciliation.changeRatio, 0.35)
        let verticalDistance =
            Double(fontSize) * animation.verticalOffset
            * movementScale

        performWithoutLayerActions {
            for newIndex in reconciliation.insertionIndices {
                let unit = newUnits[newIndex]
                let target = MotionPoint(
                    x: Double(targetOrigin.x + unit.anchor.x),
                    y: Double(targetOrigin.y + unit.anchor.y)
                )

                if let candidateIndex = resurrectionCandidate(
                    value: unit.value,
                    target: target,
                    candidateCount: resurrectionCandidateCount
                ) {
                    let token = exitingTokens.remove(at: candidateIndex)
                    configure(
                        token: token,
                        snapshot: snapshot,
                        unit: unit,
                        logicalIndex: newIndex,
                        zBase: 10
                    )
                    token.position.target = target
                    token.scale.retarget(to: 1)
                    token.opacity.retarget(
                        to: 1,
                        duration: min(animation.opacityDuration * 0.5, 0.08)
                    )
                    newTokens[newIndex] = token
                    persistentByNewIndex.append((newIndex, token))
                    continue
                }

                let anchor = nearestPersistentToken(
                    to: target,
                    candidates: persistentByNewIndex.map(\.1),
                    useTargetPosition: true
                )
                let anchorDisplacement =
                    anchor.map {
                        $0.position.value - $0.position.target
                    } ?? .zero
                let initialPosition =
                    target
                    + anchorDisplacement
                    + MotionPoint(x: 0, y: verticalDistance)
                let initialVelocity = anchor?.position.velocity ?? .zero
                let token = AnimatedToken(
                    identifier: allocateIdentifier(),
                    value: unit.value,
                    snapshot: snapshot,
                    visualUnit: unit,
                    logicalIndex: newIndex,
                    position: PointSpring(
                        value: initialPosition,
                        velocity: initialVelocity
                    ),
                    scale: ScalarSpring(
                        value: transitionStyle == .motion ? animation.scale : 1,
                        target: 1
                    ),
                    opacity: LinearTransition(value: 0)
                )
                token.position.target = target
                token.opacity.retarget(
                    to: 1,
                    duration: animation.opacityDuration,
                    delay: animation.insertionDelay
                )
                configure(
                    token: token,
                    snapshot: snapshot,
                    unit: unit,
                    logicalIndex: newIndex,
                    zBase: 20
                )
                newTokens[newIndex] = token
            }
        }

        let persistentTokens = persistentByNewIndex.map(\.1)
        performWithoutLayerActions {
            for oldIndex in reconciliation.removalIndices {
                let token = oldTokens[oldIndex]
                let anchor = nearestPersistentToken(
                    to: token.position.value,
                    candidates: persistentTokens,
                    useTargetPosition: false
                )
                let remainingAnchorMovement =
                    anchor.map {
                        $0.position.target - $0.position.value
                    } ?? .zero
                token.position.target =
                    transitionStyle == .crossfade
                    ? token.position.value
                    : token.position.value
                        + remainingAnchorMovement
                        + MotionPoint(x: 0, y: -verticalDistance)
                token.scale.retarget(
                    to: transitionStyle == .motion ? animation.scale : 1
                )
                token.opacity.retarget(
                    to: 0,
                    duration: min(animation.opacityDuration * 0.72, 0.12)
                )
                token.layer?.zPosition = CGFloat(oldIndex) * 0.0001
                exitingTokens.append(token)
            }
        }

        targetTokens = newTokens.compactMap { $0 }
        currentSnapshot = snapshot
        width.retarget(to: Double(snapshot.metrics.size.width))
        height.retarget(to: Double(snapshot.metrics.size.height))
        if transitionStyle == .crossfade || !animatesIntrinsicSize {
            width.snapToTarget()
            height.snapToTarget()
            onPresentationSizeChange?()
        }

        if transitionStyle == .crossfade {
            for token in targetTokens {
                token.position.snapToTarget()
                token.scale.snapToTarget()
            }
            for token in exitingTokens {
                token.position.snapToTarget()
                token.scale.snapToTarget()
            }
        }

        applyLayerStates()
        isActive = true
        displayLinkDriver.start(self)
    }

    func layout(
        in bounds: CGRect,
        alignment: TextMorphAlignment,
        layoutDirection: NSUserInterfaceLayoutDirection
    ) {
        layoutBounds = bounds
        self.alignment = alignment
        self.layoutDirection = layoutDirection

        guard let snapshot = currentSnapshot else { return }
        let origin = layoutOrigin(for: snapshot)

        if isActive {
            for token in targetTokens {
                token.position.target = MotionPoint(
                    x: Double(origin.x + token.visualUnit.anchor.x),
                    y: Double(origin.y + token.visualUnit.anchor.y)
                )
            }
        } else {
            for token in targetTokens {
                token.position = PointSpring(
                    value: MotionPoint(
                        x: Double(origin.x + token.visualUnit.anchor.x),
                        y: Double(origin.y + token.visualUnit.anchor.y)
                    )
                )
            }
            performWithoutLayerActions {
                fullLineLayer.frame = snapshot.fullFrame.offsetBy(
                    dx: origin.x,
                    dy: origin.y
                )
            }
        }
    }

    func advanceFrame(by duration: TimeInterval) -> Bool {
        guard isActive else { return false }
        guard duration <= 0.25 else {
            finishCurrentAnimation(
                notifyCompletion: shouldNotifyCompletion
            )
            return false
        }
        elapsedAnimationDuration += duration
        guard elapsedAnimationDuration < Self.maximumAnimationDuration else {
            finishCurrentAnimation(
                notifyCompletion: shouldNotifyCompletion
            )
            return false
        }

        let step = SpringStep(
            parameters: SpringParameters(animation: animation),
            duration: duration
        )
        var targetIsSettled = true

        for token in targetTokens {
            token.position.advance(using: step)
            token.scale.advance(using: step)
            token.opacity.advance(by: duration)
            settleIfNeeded(token)
            targetIsSettled = targetIsSettled && token.isAtTarget
        }

        for index in exitingTokens.indices.reversed() {
            let token = exitingTokens[index]
            token.position.advance(using: step)
            token.scale.advance(using: step)
            token.opacity.advance(by: duration)

            if token.opacity.isSettled, token.opacity.value <= 0 {
                removeLayer(from: token)
                exitingTokens.remove(at: index)
            }
        }

        let previousSize = presentationSize
        width.advance(using: step)
        height.advance(using: step)
        settleSizeIfNeeded()
        if presentationSize.differsVisibly(from: previousSize) {
            onPresentationSizeChange?()
        }

        applyLayerStates()

        let sizeIsSettled =
            width.isSettled(
                positionTolerance: 0.01,
                velocityTolerance: 0.05
            )
            && height.isSettled(
                positionTolerance: 0.01,
                velocityTolerance: 0.05
            )
        if targetIsSettled, exitingTokens.isEmpty, sizeIsSettled {
            finishCurrentAnimation(
                notifyCompletion: shouldNotifyCompletion
            )
            return false
        }

        return true
    }

    func finishCurrentAnimation(notifyCompletion: Bool) {
        guard isActive, let snapshot = currentSnapshot else { return }

        for token in targetTokens {
            token.position.snapToTarget()
            token.scale.snapToTarget()
            token.opacity.snapToTarget()
        }
        width.snapToTarget()
        height.snapToTarget()
        for token in exitingTokens {
            removeLayer(from: token)
        }
        exitingTokens.removeAll(keepingCapacity: true)
        consolidate(snapshot)
        isActive = false
        displayLinkDriver.stop(self)
        onPresentationSizeChange?()
        shouldNotifyCompletion = false
        elapsedAnimationDuration = 0
        if notifyCompletion {
            onCompletion?()
        }
    }

    func cancelForRemovalFromWindow() {
        guard isActive else { return }
        finishCurrentAnimation(notifyCompletion: false)
    }
}

private extension TextMorphEngine {
    final class AnimatedToken {
        let identifier: UInt64
        var value: String
        var snapshot: TextLineSnapshot
        var visualUnit: TextVisualUnit
        var logicalIndex: Int
        var position: PointSpring
        var scale: ScalarSpring
        var opacity: LinearTransition
        var layer: CALayer?

        init(
            identifier: UInt64,
            value: String,
            snapshot: TextLineSnapshot,
            visualUnit: TextVisualUnit,
            logicalIndex: Int,
            position: PointSpring,
            scale: ScalarSpring,
            opacity: LinearTransition
        ) {
            self.identifier = identifier
            self.value = value
            self.snapshot = snapshot
            self.visualUnit = visualUnit
            self.logicalIndex = logicalIndex
            self.position = position
            self.scale = scale
            self.opacity = opacity
        }

        var isAtTarget: Bool {
            position.isSettled(
                positionTolerance: 0.01,
                velocityTolerance: 0.05
            )
                && scale.isSettled(
                    positionTolerance: 0.0001,
                    velocityTolerance: 0.002
                ) && opacity.isSettled
        }
    }

    func allocateIdentifier() -> UInt64 {
        defer { nextIdentifier &+= 1 }
        return nextIdentifier
    }

    func debugState(for token: AnimatedToken) -> DebugTokenState {
        DebugTokenState(
            identifier: token.identifier,
            value: token.value,
            position: token.position.value,
            target: token.position.target,
            velocity: token.position.velocity,
            scale: token.scale.value,
            opacity: token.opacity.value
        )
    }

    func makeRestingToken(
        snapshot: TextLineSnapshot,
        unit: TextVisualUnit,
        logicalIndex: Int
    ) -> AnimatedToken {
        let origin = layoutOrigin(for: snapshot)
        return AnimatedToken(
            identifier: allocateIdentifier(),
            value: unit.value,
            snapshot: snapshot,
            visualUnit: unit,
            logicalIndex: logicalIndex,
            position: PointSpring(
                value: MotionPoint(
                    x: Double(origin.x + unit.anchor.x),
                    y: Double(origin.y + unit.anchor.y)
                )
            ),
            scale: ScalarSpring(value: 1),
            opacity: LinearTransition(value: 1)
        )
    }

    func finishImmediately(
        at snapshot: TextLineSnapshot,
        notifyCompletion: Bool
    ) {
        displayLinkDriver.stop(self)
        removeAllTokenLayers()
        currentSnapshot = snapshot
        width = ScalarSpring(value: Double(snapshot.metrics.size.width))
        height = ScalarSpring(value: Double(snapshot.metrics.size.height))
        targetTokens =
            snapshot
            .animationUnits(maximumCount: Self.maximumAnimatedUnitCount)
            .enumerated()
            .map { index, unit in
                makeRestingToken(
                    snapshot: snapshot,
                    unit: unit,
                    logicalIndex: index
                )
            }
        exitingTokens.removeAll(keepingCapacity: true)
        isActive = false
        shouldNotifyCompletion = false
        elapsedAnimationDuration = 0
        showFullLine(snapshot)
        onPresentationSizeChange?()
        if notifyCompletion {
            onCompletion?()
        }
    }

    func materializeTargetTokens() {
        performWithoutLayerActions {
            for token in targetTokens {
                configure(
                    token: token,
                    snapshot: token.snapshot,
                    unit: token.visualUnit,
                    logicalIndex: token.logicalIndex,
                    zBase: 10
                )
            }
            applyLayerStates()
        }
    }

    func configure(
        token: AnimatedToken,
        snapshot: TextLineSnapshot,
        unit: TextVisualUnit,
        logicalIndex: Int,
        zBase: CGFloat
    ) {
        token.value = unit.value
        token.snapshot = snapshot
        token.visualUnit = unit
        token.logicalIndex = logicalIndex

        guard unit.hasInk, let image = snapshot.image else {
            removeLayer(from: token)
            return
        }

        let layer: CALayer
        if let existing = token.layer {
            layer = existing
        } else {
            layer = CALayer()
            layer.contentsGravity = .resize
            layer.minificationFilter = .linear
            layer.magnificationFilter = .linear
            layer.allowsEdgeAntialiasing = true
            hostLayer?.addSublayer(layer)
            token.layer = layer
        }

        layer.contents = image
        layer.contentsScale = snapshot.scale
        layer.contentsRect = unit.contentsRect
        layer.bounds = unit.layerBounds
        layer.anchorPoint = unit.layerAnchorPoint
        layer.zPosition = zBase + CGFloat(logicalIndex) * 0.0001
    }

    func applyLayerStates() {
        performWithoutLayerActions {
            for token in targetTokens {
                applyLayerState(token)
            }
            for token in exitingTokens {
                applyLayerState(token)
            }
        }
    }

    func applyLayerState(_ token: AnimatedToken) {
        guard let layer = token.layer else { return }
        layer.position = CGPoint(
            x: CGFloat(token.position.value.x),
            y: CGFloat(token.position.value.y)
        )
        layer.opacity = Float(min(max(token.opacity.value, 0), 1))
        let scale = CGFloat(token.scale.value)
        layer.transform = CATransform3DMakeScale(scale, scale, 1)
    }

    func settleIfNeeded(_ token: AnimatedToken) {
        if token.position.isSettled(
            positionTolerance: 0.01,
            velocityTolerance: 0.05
        ) {
            token.position.snapToTarget()
        }
        if token.scale.isSettled(
            positionTolerance: 0.0001,
            velocityTolerance: 0.002
        ) {
            token.scale.snapToTarget()
        }
        if token.opacity.isSettled {
            token.opacity.snapToTarget()
        }
    }

    func settleSizeIfNeeded() {
        if width.isSettled(
            positionTolerance: 0.01,
            velocityTolerance: 0.05
        ) {
            width.snapToTarget()
        }
        if height.isSettled(
            positionTolerance: 0.01,
            velocityTolerance: 0.05
        ) {
            height.snapToTarget()
        }
    }

    func nearestPersistentToken(
        to point: MotionPoint,
        candidates: [AnimatedToken],
        useTargetPosition: Bool
    ) -> AnimatedToken? {
        candidates.min { lhs, rhs in
            let lhsPoint =
                useTargetPosition
                ? lhs.position.target
                : lhs.position.value
            let rhsPoint =
                useTargetPosition
                ? rhs.position.target
                : rhs.position.value
            let lhsDistance = lhsPoint.distanceSquared(to: point)
            let rhsDistance = rhsPoint.distanceSquared(to: point)
            if lhsDistance == rhsDistance {
                return lhs.logicalIndex < rhs.logicalIndex
            }
            return lhsDistance < rhsDistance
        }
    }

    func resurrectionCandidate(
        value: String,
        target: MotionPoint,
        candidateCount: Int
    ) -> Int? {
        guard candidateCount > 0, !exitingTokens.isEmpty else { return nil }
        let upperBound = min(candidateCount, exitingTokens.count)
        var bestIndex: Int?
        var bestDistance = Double.infinity

        for index in 0..<upperBound where exitingTokens[index].value == value {
            let distance = exitingTokens[index].position.value
                .distanceSquared(to: target)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    func layoutOrigin(for snapshot: TextLineSnapshot) -> CGPoint {
        let horizontal: CGFloat
        let isLeftToRight = layoutDirection == .leftToRight

        switch alignment {
        case .natural:
            horizontal =
                isLeftToRight
                ? 0
                : layoutBounds.width - snapshot.metrics.size.width
        case .leading:
            horizontal =
                isLeftToRight
                ? 0
                : layoutBounds.width - snapshot.metrics.size.width
        case .center:
            horizontal = (layoutBounds.width - snapshot.metrics.size.width) / 2
        case .trailing:
            horizontal =
                isLeftToRight
                ? layoutBounds.width - snapshot.metrics.size.width
                : 0
        }

        return CGPoint(
            x: horizontal,
            y: (layoutBounds.height - snapshot.metrics.size.height) / 2
        )
    }

    func showFullLine(_ snapshot: TextLineSnapshot) {
        performWithoutLayerActions {
            guard let image = snapshot.image else {
                removeFullLineLayer()
                return
            }
            if fullLineLayer.superlayer == nil {
                hostLayer?.addSublayer(fullLineLayer)
            }
            fullLineLayer.contents = image
            fullLineLayer.contentsScale = snapshot.scale
            let origin = layoutOrigin(for: snapshot)
            fullLineLayer.frame = snapshot.fullFrame.offsetBy(
                dx: origin.x,
                dy: origin.y
            )
            fullLineLayer.opacity = 1
            fullLineLayer.transform = CATransform3DIdentity
        }
    }

    func consolidate(_ snapshot: TextLineSnapshot) {
        removeAllTokenLayers()
        let units = snapshot.animationUnits(
            maximumCount: Self.maximumAnimatedUnitCount
        )
        if targetTokens.map(\.value) == units.map(\.value) {
            let origin = layoutOrigin(for: snapshot)
            for (index, pair) in zip(targetTokens, units).enumerated() {
                let (token, unit) = pair
                token.snapshot = snapshot
                token.visualUnit = unit
                token.logicalIndex = index
                token.position = PointSpring(
                    value: MotionPoint(
                        x: Double(origin.x + unit.anchor.x),
                        y: Double(origin.y + unit.anchor.y)
                    )
                )
                token.scale = ScalarSpring(value: 1)
                token.opacity = LinearTransition(value: 1)
            }
        } else {
            targetTokens = units.enumerated().map { index, unit in
                makeRestingToken(
                    snapshot: snapshot,
                    unit: unit,
                    logicalIndex: index
                )
            }
        }
        showFullLine(snapshot)
    }

    func removeFullLineLayer() {
        fullLineLayer.removeFromSuperlayer()
        fullLineLayer.contents = nil
    }

    func removeLayer(from token: AnimatedToken) {
        token.layer?.removeFromSuperlayer()
        token.layer?.contents = nil
        token.layer = nil
    }

    func removeAllTokenLayers() {
        for token in targetTokens {
            removeLayer(from: token)
        }
        for token in exitingTokens {
            removeLayer(from: token)
        }
    }

    func performWithoutLayerActions(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }
}

private extension CGSize {
    func differsVisibly(from other: CGSize) -> Bool {
        abs(width - other.width) > 0.001 || abs(height - other.height) > 0.001
    }
}
