import Foundation

struct TextMatch: Equatable, Hashable, Sendable {
    let oldIndex: Int
    let newIndex: Int
}

struct TextReconciliation: Equatable, Sendable {
    let matches: [TextMatch]
    let insertionIndices: [Int]
    let removalIndices: [Int]
    let changeRatio: Double
}

enum TextReconciler {
    private static let maximumMatrixCells = 4_000_000

    static func reconcile<T: Equatable & Sendable>(
        old: [T],
        new: [T]
    ) -> TextReconciliation {
        let matches = longestCommonSubsequence(old: old, new: new)
        let matchedOld = Set(matches.map(\.oldIndex))
        let matchedNew = Set(matches.map(\.newIndex))
        let insertions = new.indices.filter { !matchedNew.contains($0) }
        let removals = old.indices.filter { !matchedOld.contains($0) }
        let maximumCount = max(old.count, new.count)
        let ratio: Double

        if maximumCount == 0 {
            ratio = 0
        } else {
            ratio =
                Double(max(insertions.count, removals.count))
                / Double(maximumCount)
        }

        return TextReconciliation(
            matches: matches,
            insertionIndices: insertions,
            removalIndices: removals,
            changeRatio: min(max(ratio, 0), 1)
        )
    }

    static func longestCommonSubsequence<T: Equatable>(
        old: [T],
        new: [T]
    ) -> [TextMatch] {
        guard !old.isEmpty, !new.isEmpty else { return [] }

        let (cellCount, overflow) = old.count.multipliedReportingOverflow(
            by: new.count
        )
        if !overflow, cellCount <= maximumMatrixCells {
            return matrixLCS(old: old, new: new)
        }

        var result: [TextMatch] = []
        result.reserveCapacity(min(old.count, new.count))
        hirschberg(
            old: old,
            oldRange: old.indices,
            new: new,
            newRange: new.indices,
            into: &result
        )
        return result
    }

    private struct Score {
        var count: Int
        var displacement: Int

        static let zero = Score(count: 0, displacement: 0)

        func addingMatch(oldIndex: Int, newIndex: Int) -> Score {
            Score(
                count: count + 1,
                displacement: displacement + abs(oldIndex - newIndex)
            )
        }

        func isBetter(than other: Score) -> Bool {
            count > other.count
                || (count == other.count && displacement < other.displacement)
        }
    }

    private enum Direction: UInt8 {
        case end = 0
        case match = 1
        case skipOld = 2
        case skipNew = 3
    }

    private static func matrixLCS<T: Equatable>(
        old: [T],
        new: [T]
    ) -> [TextMatch] {
        let columnCount = new.count
        var directions = ContiguousArray(
            repeating: Direction.end.rawValue,
            count: old.count * columnCount
        )
        var next = ContiguousArray(
            repeating: Score.zero,
            count: columnCount + 1
        )
        var current = next

        for oldIndex in old.indices.reversed() {
            current[columnCount] = .zero

            for newIndex in new.indices.reversed() {
                var best = next[newIndex]
                var direction: Direction = .skipOld
                let skippingNew = current[newIndex + 1]

                if skippingNew.isBetter(than: best)
                    || (!best.isBetter(than: skippingNew)
                        && oldIndex < newIndex)
                {
                    best = skippingNew
                    direction = .skipNew
                }

                if old[oldIndex] == new[newIndex] {
                    let matching = next[newIndex + 1].addingMatch(
                        oldIndex: oldIndex,
                        newIndex: newIndex
                    )
                    if matching.isBetter(than: best)
                        || !best.isBetter(than: matching)
                    {
                        best = matching
                        direction = .match
                    }
                }

                current[newIndex] = best
                directions[oldIndex * columnCount + newIndex] = direction.rawValue
            }

            swap(&current, &next)
        }

        var result: [TextMatch] = []
        result.reserveCapacity(next[0].count)
        var oldIndex = 0
        var newIndex = 0

        while oldIndex < old.count, newIndex < new.count {
            guard
                let direction = Direction(
                    rawValue: directions[oldIndex * columnCount + newIndex]
                )
            else {
                break
            }

            switch direction {
            case .match:
                result.append(
                    TextMatch(oldIndex: oldIndex, newIndex: newIndex)
                )
                oldIndex += 1
                newIndex += 1
            case .skipOld:
                oldIndex += 1
            case .skipNew:
                newIndex += 1
            case .end:
                return result
            }
        }

        return result
    }

    private static func hirschberg<T: Equatable>(
        old: [T],
        oldRange: Range<Int>,
        new: [T],
        newRange: Range<Int>,
        into result: inout [TextMatch]
    ) {
        guard !oldRange.isEmpty, !newRange.isEmpty else { return }

        if oldRange.count == 1 {
            let oldIndex = oldRange.lowerBound
            var bestNewIndex: Int?
            var bestDistance = Int.max

            for newIndex in newRange where old[oldIndex] == new[newIndex] {
                let distance = abs(oldIndex - newIndex)
                if distance < bestDistance {
                    bestDistance = distance
                    bestNewIndex = newIndex
                }
            }

            if let bestNewIndex {
                result.append(
                    TextMatch(oldIndex: oldIndex, newIndex: bestNewIndex)
                )
            }
            return
        }

        let oldMiddle = oldRange.lowerBound + oldRange.count / 2
        let leftScores = prefixLengths(
            old: old,
            oldRange: oldRange.lowerBound..<oldMiddle,
            new: new,
            newRange: newRange
        )
        let rightScores = suffixLengths(
            old: old,
            oldRange: oldMiddle..<oldRange.upperBound,
            new: new,
            newRange: newRange
        )

        var splitOffset = 0
        var bestCount = -1
        var bestAlignment = Int.max

        for offset in 0...newRange.count {
            let count = leftScores[offset] + rightScores[offset]
            let alignment = abs(oldMiddle - (newRange.lowerBound + offset))
            if count > bestCount
                || (count == bestCount && alignment < bestAlignment)
            {
                bestCount = count
                bestAlignment = alignment
                splitOffset = offset
            }
        }

        let newMiddle = newRange.lowerBound + splitOffset
        hirschberg(
            old: old,
            oldRange: oldRange.lowerBound..<oldMiddle,
            new: new,
            newRange: newRange.lowerBound..<newMiddle,
            into: &result
        )
        hirschberg(
            old: old,
            oldRange: oldMiddle..<oldRange.upperBound,
            new: new,
            newRange: newMiddle..<newRange.upperBound,
            into: &result
        )
    }

    private static func prefixLengths<T: Equatable>(
        old: [T],
        oldRange: Range<Int>,
        new: [T],
        newRange: Range<Int>
    ) -> [Int] {
        var row = Array(repeating: 0, count: newRange.count + 1)

        for oldIndex in oldRange {
            var diagonal = 0
            for offset in 0..<newRange.count {
                let previous = row[offset + 1]
                if old[oldIndex] == new[newRange.lowerBound + offset] {
                    row[offset + 1] = diagonal + 1
                } else {
                    row[offset + 1] = max(row[offset + 1], row[offset])
                }
                diagonal = previous
            }
        }

        return row
    }

    private static func suffixLengths<T: Equatable>(
        old: [T],
        oldRange: Range<Int>,
        new: [T],
        newRange: Range<Int>
    ) -> [Int] {
        var next = Array(repeating: 0, count: newRange.count + 1)
        var current = next

        for oldIndex in oldRange.reversed() {
            current[newRange.count] = 0
            for offset in (0..<newRange.count).reversed() {
                if old[oldIndex] == new[newRange.lowerBound + offset] {
                    current[offset] = next[offset + 1] + 1
                } else {
                    current[offset] = max(next[offset], current[offset + 1])
                }
            }
            swap(&current, &next)
        }

        return next
    }
}
