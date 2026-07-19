import AppKit
import CoreText

struct TextLineMetrics: Equatable {
    let size: CGSize
    let baseline: CGFloat

    static let zero = TextLineMetrics(size: .zero, baseline: 0)

    static func measure(text: String, font: NSFont) -> TextLineMetrics {
        guard !text.isEmpty else { return .zero }

        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [.font: font])
        )
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        )

        return TextLineMetrics(
            size: CGSize(
                width: max(width, 0),
                height: max(ascent + descent + leading, 0)
            ),
            baseline: ascent + leading / 2
        )
    }
}

struct TextVisualUnit {
    let value: String
    let range: NSRange
    let anchor: CGPoint
    let layerBounds: CGRect
    let layerAnchorPoint: CGPoint
    let contentsRect: CGRect
    let hasInk: Bool
}

@MainActor
final class TextLineSnapshot {
    static let maximumIndividuallyAnimatedUnitCount = 256

    let text: String
    let metrics: TextLineMetrics
    let image: CGImage?
    let scale: CGFloat
    let fullFrame: CGRect
    let units: [TextVisualUnit]
    let requiresWholeLineAnimation: Bool
    let containsInk: Bool

    var rasterPixelCount: Int {
        guard let image else { return 0 }
        let result = image.width.multipliedReportingOverflow(by: image.height)
        return result.overflow ? .max : result.partialValue
    }

    private init(
        text: String,
        metrics: TextLineMetrics,
        image: CGImage?,
        scale: CGFloat,
        fullFrame: CGRect,
        units: [TextVisualUnit],
        requiresWholeLineAnimation: Bool,
        containsInk: Bool
    ) {
        self.text = text
        self.metrics = metrics
        self.image = image
        self.scale = scale
        self.fullFrame = fullFrame
        self.units = units
        self.requiresWholeLineAnimation = requiresWholeLineAnimation
        self.containsInk = containsInk
    }

    static func make(
        text: String,
        font: NSFont,
        color: NSColor,
        scale requestedScale: CGFloat,
        granularity: TextMorphGranularity
    ) -> TextLineSnapshot {
        guard !text.isEmpty else {
            return TextLineSnapshot(
                text: text,
                metrics: .zero,
                image: nil,
                scale: max(requestedScale, 1),
                fullFrame: .zero,
                units: [],
                requiresWholeLineAnimation: false,
                containsInk: false
            )
        }

        let nativeScale = max(requestedScale, 1)
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
            ]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let lineWidth = CGFloat(
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        )
        let metrics = TextLineMetrics(
            size: CGSize(
                width: max(lineWidth, 0),
                height: max(ascent + descent + leading, 0)
            ),
            baseline: ascent + leading / 2
        )

        let typographicRect = CGRect(
            x: 0,
            y: -descent - leading / 2,
            width: max(lineWidth, 0),
            height: max(ascent + descent + leading, 0)
        )
        let imageBounds = CTLineGetImageBounds(line, nil)
        var drawingBounds = typographicRect
        if imageBounds.hasFiniteArea {
            drawingBounds = drawingBounds.union(imageBounds)
        }
        let containsInk = imageBounds.hasFiniteArea

        let scale = safeRasterScale(
            for: drawingBounds,
            requestedScale: nativeScale
        )
        let onePixel = 1 / scale
        let canvas =
            drawingBounds
            .insetBy(dx: -onePixel, dy: -onePixel)
            .pixelAlignedOutward(scale: scale)
        let pixelWidth = max(Int((canvas.width * scale).rounded()), 1)
        let pixelHeight = max(Int((canvas.height * scale).rounded()), 1)
        let rendererSize = CGSize(
            width: CGFloat(pixelWidth) / scale,
            height: CGFloat(pixelHeight) / scale
        )

        let colorSpace =
            CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo =
            CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        let context: CGContext?
        if containsInk {
            context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        } else {
            context = nil
        }
        let cgImage: CGImage?
        if let context {
            context.saveGState()
            context.scaleBy(x: scale, y: scale)
            // `CALayer.contents` consumes a raw `CGImage` in Quartz's native
            // bottom-up image coordinate system on macOS. Keep the raster in
            // that orientation; applying AppKit's top-down view transform here
            // would make the layer display the image upside down.
            context.translateBy(x: -canvas.minX, y: -canvas.minY)
            context.textPosition = .zero
            CTLineDraw(line, context)
            context.restoreGState()
            cgImage = context.makeImage()
        } else {
            cgImage = nil
        }

        let fullFrame = CGRect(
            x: canvas.minX,
            y: metrics.baseline - canvas.maxY,
            width: rendererSize.width,
            height: rendererSize.height
        )
        let rawSegments = TextSegmenter.segments(
            in: text,
            granularity: granularity
        )
        let requiresWholeLineAnimation =
            rawSegments.count > Self.maximumIndividuallyAnimatedUnitCount
        let units =
            requiresWholeLineAnimation
            ? [
                wholeLineUnit(
                    text: text,
                    metrics: metrics,
                    fullFrame: fullFrame,
                    hasInk: containsInk
                )
            ]
            : makeVisualUnits(
                text: text,
                line: line,
                segments: rawSegments,
                canvas: canvas,
                metrics: metrics,
                imagePixelWidth: cgImage?.width ?? pixelWidth,
                scale: scale
            )

        return TextLineSnapshot(
            text: text,
            metrics: metrics,
            image: cgImage,
            scale: scale,
            fullFrame: fullFrame,
            units: units,
            requiresWholeLineAnimation: requiresWholeLineAnimation,
            containsInk: containsInk
        )
    }

    func animationUnits(maximumCount: Int) -> [TextVisualUnit] {
        guard requiresWholeLineAnimation || units.count > maximumCount else {
            return units
        }
        guard image != nil, fullFrame.width > 0, fullFrame.height > 0 else {
            return []
        }
        return [
            Self.wholeLineUnit(
                text: text,
                metrics: metrics,
                fullFrame: fullFrame,
                hasInk: containsInk
            )
        ]
    }
}

private extension TextLineSnapshot {
    static let maximumRasterDimension: CGFloat = 16_384
    static let maximumRasterPixelCount: CGFloat = 16_777_216

    static func wholeLineUnit(
        text: String,
        metrics: TextLineMetrics,
        fullFrame: CGRect,
        hasInk: Bool
    ) -> TextVisualUnit {
        let anchor = CGPoint(
            x: metrics.size.width / 2,
            y: metrics.baseline
        )
        return TextVisualUnit(
            value: text,
            range: NSRange(location: 0, length: (text as NSString).length),
            anchor: anchor,
            layerBounds: CGRect(origin: .zero, size: fullFrame.size),
            layerAnchorPoint: CGPoint(
                x: fullFrame.width > 0
                    ? (anchor.x - fullFrame.minX) / fullFrame.width
                    : 0.5,
                y: fullFrame.height > 0
                    ? (anchor.y - fullFrame.minY) / fullFrame.height
                    : 0.5
            ),
            contentsRect: CGRect(x: 0, y: 0, width: 1, height: 1),
            hasInk: hasInk
        )
    }

    static func safeRasterScale(
        for bounds: CGRect,
        requestedScale: CGFloat
    ) -> CGFloat {
        let minimumPointDimension = 1 / requestedScale
        let width = max(bounds.width, minimumPointDimension)
        let height = max(bounds.height, minimumPointDimension)
        let dimensionScale = min(
            (maximumRasterDimension - 2) / width,
            (maximumRasterDimension - 2) / height
        )

        // Reserve half of the pixel budget for the one-pixel transparent
        // perimeter and extreme aspect ratios. Typical interface text remains
        // at native display scale; only pathological lines are downsampled.
        let areaScale = sqrt(
            (maximumRasterPixelCount * 0.5) / (width * height)
        )
        return max(
            min(requestedScale, dimensionScale, areaScale),
            0.000_001
        )
    }

    struct HorizontalExtent {
        var minimum: CGFloat
        var maximum: CGFloat

        init(_ first: CGFloat, _ second: CGFloat) {
            minimum = min(first, second)
            maximum = max(first, second)
        }

        mutating func formUnion(_ other: HorizontalExtent) {
            minimum = min(minimum, other.minimum)
            maximum = max(maximum, other.maximum)
        }
    }

    struct GlyphCluster {
        let range: NSRange
        let typographicExtent: HorizontalExtent
        let inkBounds: CGRect
    }

    struct ShapingGroup {
        let segmentIndices: [Int]
        let range: NSRange
        let value: String
        var typographicExtent: HorizontalExtent
        var inkBounds: CGRect
    }

    struct DisjointSet {
        private var parents: [Int]

        init(count: Int) {
            parents = Array(0..<count)
        }

        mutating func root(of index: Int) -> Int {
            if parents[index] != index {
                parents[index] = root(of: parents[index])
            }
            return parents[index]
        }

        mutating func merge(_ lhs: Int, _ rhs: Int) {
            let lhsRoot = root(of: lhs)
            let rhsRoot = root(of: rhs)
            if lhsRoot != rhsRoot {
                parents[rhsRoot] = lhsRoot
            }
        }

        mutating func mergeContiguous(_ indices: [Int]) {
            guard let lower = indices.min(), let upper = indices.max() else {
                return
            }
            guard lower < upper else { return }
            for index in (lower + 1)...upper {
                merge(lower, index)
            }
        }
    }

    static func makeVisualUnits(
        text: String,
        line: CTLine,
        segments: [TextSegment],
        canvas: CGRect,
        metrics: TextLineMetrics,
        imagePixelWidth: Int,
        scale: CGFloat
    ) -> [TextVisualUnit] {
        guard !segments.isEmpty, imagePixelWidth > 0 else { return [] }

        var disjointSet = DisjointSet(count: segments.count)
        let clusters = glyphClusters(
            line: line,
            segments: segments,
            disjointSet: &disjointSet
        )

        var groups = shapingGroups(
            text: text,
            line: line,
            segments: segments,
            clusters: clusters,
            disjointSet: &disjointSet
        )

        // If two independently moving units have overlapping ink, a vertical
        // snapshot cut would divide or duplicate glyph pixels. Coalesce the
        // complete logical range instead. This catches italic overhangs and
        // reordered marks in addition to explicit ligature clusters.
        let safety = 1 / scale
        var didMerge = true
        while didMerge, groups.count > 1 {
            didMerge = false
            let visible = groups.indices
                .filter { groups[$0].inkBounds.hasFiniteArea }
                .sorted {
                    groups[$0].typographicExtent.minimum
                        < groups[$1].typographicExtent.minimum
                }

            guard let firstVisible = visible.first else { break }
            var componentSegments = groups[firstVisible].segmentIndices
            var componentMaximumX = groups[firstVisible].inkBounds.maxX
            var componentGroupCount = 1

            func mergeComponentIfNeeded() {
                guard componentGroupCount > 1 else { return }
                disjointSet.mergeContiguous(componentSegments)
                didMerge = true
            }

            for groupIndex in visible.dropFirst() {
                let group = groups[groupIndex]
                if componentMaximumX + safety
                    > group.inkBounds.minX - safety
                {
                    componentSegments.append(contentsOf: group.segmentIndices)
                    componentMaximumX = max(
                        componentMaximumX,
                        group.inkBounds.maxX
                    )
                    componentGroupCount += 1
                } else {
                    mergeComponentIfNeeded()
                    componentSegments = group.segmentIndices
                    componentMaximumX = group.inkBounds.maxX
                    componentGroupCount = 1
                }
            }
            mergeComponentIfNeeded()

            if didMerge {
                groups = shapingGroups(
                    text: text,
                    line: line,
                    segments: segments,
                    clusters: clusters,
                    disjointSet: &disjointSet
                )
            }
        }

        let visualOrder = groups.indices.sorted {
            let lhs = groups[$0].typographicExtent
            let rhs = groups[$1].typographicExtent
            if lhs.minimum == rhs.minimum {
                return lhs.maximum < rhs.maximum
            }
            return lhs.minimum < rhs.minimum
        }
        guard !visualOrder.isEmpty else { return [] }

        var boundaries = Array(
            repeating: CGFloat.zero,
            count: visualOrder.count + 1
        )
        boundaries[0] = canvas.minX
        boundaries[visualOrder.count] = canvas.maxX

        if visualOrder.count > 1 {
            var nearestInkMaximumToLeft = Array(
                repeating: -CGFloat.infinity,
                count: visualOrder.count
            )
            var leftInkMaximum = -CGFloat.infinity
            for visualIndex in visualOrder.indices {
                let ink = groups[visualOrder[visualIndex]].inkBounds
                if ink.hasFiniteArea {
                    leftInkMaximum = ink.maxX + safety
                }
                nearestInkMaximumToLeft[visualIndex] = leftInkMaximum
            }

            var nearestInkMinimumToRight = Array(
                repeating: CGFloat.infinity,
                count: visualOrder.count
            )
            var rightInkMinimum = CGFloat.infinity
            for visualIndex in visualOrder.indices.reversed() {
                let ink = groups[visualOrder[visualIndex]].inkBounds
                if ink.hasFiniteArea {
                    rightInkMinimum = ink.minX - safety
                }
                nearestInkMinimumToRight[visualIndex] = rightInkMinimum
            }

            for visualIndex in 0..<(visualOrder.count - 1) {
                let lhs = groups[visualOrder[visualIndex]]
                let rhs = groups[visualOrder[visualIndex + 1]]
                let desired =
                    (lhs.typographicExtent.maximum
                        + rhs.typographicExtent.minimum) / 2
                let lowerBound = nearestInkMaximumToLeft[visualIndex]
                let upperBound = nearestInkMinimumToRight[visualIndex + 1]

                let boundary: CGFloat
                if lowerBound <= upperBound {
                    boundary = min(max(desired, lowerBound), upperBound)
                } else {
                    boundary = desired
                }
                boundaries[visualIndex + 1] = min(
                    max(boundary, boundaries[visualIndex]),
                    canvas.maxX
                )
            }
        }

        var pixelBoundaries = boundaries.map { boundary in
            Int(((boundary - canvas.minX) * scale).rounded())
        }
        pixelBoundaries[0] = 0
        pixelBoundaries[pixelBoundaries.count - 1] = imagePixelWidth
        if pixelBoundaries.count > 2 {
            for index in 1..<(pixelBoundaries.count - 1) {
                pixelBoundaries[index] = min(
                    max(pixelBoundaries[index], pixelBoundaries[index - 1]),
                    imagePixelWidth
                )
            }
        }
        var resultByLogicalIndex: [Int: TextVisualUnit] = [:]
        resultByLogicalIndex.reserveCapacity(groups.count)

        for visualIndex in visualOrder.indices {
            let logicalIndex = visualOrder[visualIndex]
            let group = groups[logicalIndex]
            let pixelStart = pixelBoundaries[visualIndex]
            let pixelEnd = pixelBoundaries[visualIndex + 1]
            let sliceWidth = CGFloat(max(pixelEnd - pixelStart, 0)) / scale
            let frame = CGRect(
                x: canvas.minX + CGFloat(pixelStart) / scale,
                y: metrics.baseline - canvas.maxY,
                width: sliceWidth,
                height: canvas.height
            )
            let anchor = CGPoint(
                x: (group.typographicExtent.minimum
                    + group.typographicExtent.maximum) / 2,
                y: metrics.baseline
            )
            let anchorPoint = CGPoint(
                x: frame.width > 0
                    ? (anchor.x - frame.minX) / frame.width
                    : 0.5,
                y: frame.height > 0
                    ? (anchor.y - frame.minY) / frame.height
                    : 0.5
            )
            let contentsRect = CGRect(
                x: CGFloat(pixelStart) / CGFloat(imagePixelWidth),
                y: 0,
                width: CGFloat(max(pixelEnd - pixelStart, 0))
                    / CGFloat(imagePixelWidth),
                height: 1
            )

            resultByLogicalIndex[logicalIndex] = TextVisualUnit(
                value: group.value,
                range: group.range,
                anchor: anchor,
                layerBounds: CGRect(origin: .zero, size: frame.size),
                layerAnchorPoint: anchorPoint,
                contentsRect: contentsRect,
                hasInk: group.inkBounds.hasFiniteArea && sliceWidth > 0
            )
        }

        return groups.indices.compactMap { resultByLogicalIndex[$0] }
    }

    static func glyphClusters(
        line: CTLine,
        segments: [TextSegment],
        disjointSet: inout DisjointSet
    ) -> [GlyphCluster] {
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        var result: [GlyphCluster] = []

        for run in runs {
            let glyphCount = CTRunGetGlyphCount(run)
            guard glyphCount > 0 else { continue }

            let runRange = CTRunGetStringRange(run)
            let nsRunRange = NSRange(
                location: runRange.location,
                length: runRange.length
            )
            let runSegmentIndices = intersectingSegmentIndices(
                nsRunRange,
                segments: segments
            )
            let status = CTRunGetStatus(run)

            if status.contains(.rightToLeft)
                || status.contains(.nonMonotonic)
            {
                var chunk: [Int] = []
                for segmentIndex in runSegmentIndices {
                    if segments[segmentIndex].value.allSatisfy(\.isWhitespace) {
                        disjointSet.mergeContiguous(chunk)
                        chunk.removeAll(keepingCapacity: true)
                    } else {
                        chunk.append(segmentIndex)
                    }
                }
                disjointSet.mergeContiguous(chunk)
            }

            var stringIndices = Array(repeating: CFIndex(), count: glyphCount)
            var positions = Array(repeating: CGPoint.zero, count: glyphCount)
            var advances = Array(repeating: CGSize.zero, count: glyphCount)
            CTRunGetStringIndices(
                run,
                CFRange(location: 0, length: 0),
                &stringIndices
            )
            CTRunGetPositions(
                run,
                CFRange(location: 0, length: 0),
                &positions
            )
            CTRunGetAdvances(
                run,
                CFRange(location: 0, length: 0),
                &advances
            )

            var glyphIndicesByStringStart: [CFIndex: [Int]] = [:]
            glyphIndicesByStringStart.reserveCapacity(glyphCount)
            for glyphIndex in stringIndices.indices {
                let stringStart = stringIndices[glyphIndex]
                guard stringStart != kCFNotFound else { continue }
                glyphIndicesByStringStart[stringStart, default: []].append(
                    glyphIndex
                )
            }
            let validStarts = glyphIndicesByStringStart.keys.sorted()
            guard !validStarts.isEmpty else {
                disjointSet.mergeContiguous(runSegmentIndices)
                continue
            }

            for (startOffset, rawStart) in validStarts.enumerated() {
                let rawEnd =
                    startOffset + 1 < validStarts.count
                    ? validStarts[startOffset + 1]
                    : runRange.location + runRange.length
                let start = max(rawStart, runRange.location)
                let end = min(rawEnd, runRange.location + runRange.length)
                guard end > start else { continue }

                let clusterRange = NSRange(
                    location: start,
                    length: end - start
                )
                let clusterSegmentIndices = intersectingSegmentIndices(
                    clusterRange,
                    segments: segments
                )
                disjointSet.mergeContiguous(clusterSegmentIndices)
                let clusterIsWhitespace = clusterSegmentIndices.allSatisfy {
                    segments[$0].value.allSatisfy(\.isWhitespace)
                }

                guard
                    let glyphIndices = glyphIndicesByStringStart[rawStart],
                    let firstGlyph = glyphIndices.first
                else { continue }

                var typographicExtent = HorizontalExtent(
                    positions[firstGlyph].x,
                    positions[firstGlyph].x + advances[firstGlyph].width
                )
                var inkBounds = CGRect.null

                for glyphIndex in glyphIndices {
                    typographicExtent.formUnion(
                        HorizontalExtent(
                            positions[glyphIndex].x,
                            positions[glyphIndex].x
                                + advances[glyphIndex].width
                        )
                    )
                    if !clusterIsWhitespace {
                        let glyphInk = CTRunGetImageBounds(
                            run,
                            nil,
                            CFRange(location: glyphIndex, length: 1)
                        )
                        if glyphInk.hasFiniteArea {
                            inkBounds =
                                inkBounds.hasFiniteArea
                                ? inkBounds.union(glyphInk)
                                : glyphInk
                        }
                    }
                }

                result.append(
                    GlyphCluster(
                        range: clusterRange,
                        typographicExtent: typographicExtent,
                        inkBounds: inkBounds
                    )
                )
            }
        }

        return result
    }

    static func shapingGroups(
        text: String,
        line: CTLine,
        segments: [TextSegment],
        clusters: [GlyphCluster],
        disjointSet: inout DisjointSet
    ) -> [ShapingGroup] {
        var groupedIndices: [[Int]] = []
        var rootToGroup: [Int: Int] = [:]
        var groupForSegment = Array(repeating: 0, count: segments.count)

        for segmentIndex in segments.indices {
            let root = disjointSet.root(of: segmentIndex)
            let groupIndex: Int
            if let existingGroupIndex = rootToGroup[root] {
                groupIndex = existingGroupIndex
                groupedIndices[groupIndex].append(segmentIndex)
            } else {
                groupIndex = groupedIndices.count
                rootToGroup[root] = groupIndex
                groupedIndices.append([segmentIndex])
            }
            groupForSegment[segmentIndex] = groupIndex
        }

        var clusterExtents = Array<HorizontalExtent?>(
            repeating: nil,
            count: groupedIndices.count
        )
        var clusterInkBounds = Array(
            repeating: CGRect.null,
            count: groupedIndices.count
        )
        for cluster in clusters {
            let clusterSegments = intersectingSegmentIndices(
                cluster.range,
                segments: segments
            )
            var previousGroupIndex: Int?
            for segmentIndex in clusterSegments {
                let groupIndex = groupForSegment[segmentIndex]
                guard groupIndex != previousGroupIndex else { continue }

                if var extent = clusterExtents[groupIndex] {
                    extent.formUnion(cluster.typographicExtent)
                    clusterExtents[groupIndex] = extent
                } else {
                    clusterExtents[groupIndex] = cluster.typographicExtent
                }
                if cluster.inkBounds.hasFiniteArea {
                    clusterInkBounds[groupIndex] =
                        clusterInkBounds[groupIndex].hasFiniteArea
                        ? clusterInkBounds[groupIndex].union(cluster.inkBounds)
                        : cluster.inkBounds
                }
                previousGroupIndex = groupIndex
            }
        }

        let nsText = text as NSString
        return groupedIndices.enumerated().map { groupIndex, indices in
            let firstRange = segments[indices[0]].range
            let lastRange = segments[indices[indices.count - 1]].range
            let range = NSRange(
                location: firstRange.location,
                length: NSMaxRange(lastRange) - firstRange.location
            )

            let typographicExtent: HorizontalExtent
            if let extent = clusterExtents[groupIndex] {
                typographicExtent = extent
            } else {
                let startPrimary = CTLineGetOffsetForStringIndex(
                    line,
                    range.location,
                    nil
                )
                let endPrimary = CTLineGetOffsetForStringIndex(
                    line,
                    NSMaxRange(range),
                    nil
                )
                typographicExtent = HorizontalExtent(startPrimary, endPrimary)
            }

            return ShapingGroup(
                segmentIndices: indices,
                range: range,
                value: nsText.substring(with: range),
                typographicExtent: typographicExtent,
                inkBounds: clusterInkBounds[groupIndex]
            )
        }
    }

    static func intersectingSegmentIndices(
        _ range: NSRange,
        segments: [TextSegment]
    ) -> [Int] {
        guard range.length > 0, !segments.isEmpty else { return [] }

        var lowerBound = 0
        var upperBound = segments.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if NSMaxRange(segments[middle].range) <= range.location {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        let rangeEnd = NSMaxRange(range)
        var result: [Int] = []
        var index = lowerBound
        while index < segments.count,
            segments[index].range.location < rangeEnd
        {
            if NSIntersectionRange(range, segments[index].range).length > 0 {
                result.append(index)
            }
            index += 1
        }
        return result
    }
}

private extension CGRect {
    var hasFiniteArea: Bool {
        !isNull
            && !isInfinite
            && width > 0
            && height > 0
            && minX.isFinite
            && minY.isFinite
            && maxX.isFinite
            && maxY.isFinite
    }

    func pixelAlignedOutward(scale: CGFloat) -> CGRect {
        let minimumX = floor(minX * scale) / scale
        let minimumY = floor(minY * scale) / scale
        let maximumX = ceil(maxX * scale) / scale
        let maximumY = ceil(maxY * scale) / scale
        return CGRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX,
            height: maximumY - minimumY
        )
    }
}
