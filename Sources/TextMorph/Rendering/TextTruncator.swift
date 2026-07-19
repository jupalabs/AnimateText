import AppKit

enum TextTruncator {
    private static let ellipsis = "…"

    static func truncate(
        _ text: String,
        toWidth maximumWidth: CGFloat,
        font: NSFont,
        mode: TextMorphTruncationMode
    ) -> String {
        guard mode != .none else { return text }
        guard maximumWidth > 0 else { return "" }
        guard maximumWidth.isFinite else { return text }
        guard width(of: text, font: font) > maximumWidth else { return text }
        guard width(of: ellipsis, font: font) <= maximumWidth else { return "" }

        let characters = Array(text)
        guard !characters.isEmpty else { return text }

        return switch mode {
        case .none:
            text
        case .head:
            headTruncated(
                characters,
                maximumWidth: maximumWidth,
                font: font
            )
        case .middle:
            middleTruncated(
                characters,
                maximumWidth: maximumWidth,
                font: font
            )
        case .tail:
            tailTruncated(
                characters,
                maximumWidth: maximumWidth,
                font: font
            )
        }
    }

    private static func headTruncated(
        _ characters: [Character],
        maximumWidth: CGFloat,
        font: NSFont
    ) -> String {
        let count = maximumFittingCount(
            upTo: characters.count,
            maximumWidth: maximumWidth,
            font: font
        ) { count in
            ellipsis + String(characters.suffix(count))
        }
        return ellipsis + String(characters.suffix(count))
    }

    private static func middleTruncated(
        _ characters: [Character],
        maximumWidth: CGFloat,
        font: NSFont
    ) -> String {
        let count = maximumFittingCount(
            upTo: characters.count,
            maximumWidth: maximumWidth,
            font: font
        ) { count in
            middleCandidate(characters, retaining: count)
        }
        return middleCandidate(characters, retaining: count)
    }

    private static func tailTruncated(
        _ characters: [Character],
        maximumWidth: CGFloat,
        font: NSFont
    ) -> String {
        let count = maximumFittingCount(
            upTo: characters.count,
            maximumWidth: maximumWidth,
            font: font
        ) { count in
            String(characters.prefix(count)) + ellipsis
        }
        return String(characters.prefix(count)) + ellipsis
    }

    private static func maximumFittingCount(
        upTo upperBound: Int,
        maximumWidth: CGFloat,
        font: NSFont,
        candidate: (Int) -> String
    ) -> Int {
        var lower = 0
        var upper = upperBound

        while lower < upper {
            let midpoint = lower + (upper - lower + 1) / 2
            if width(of: candidate(midpoint), font: font) <= maximumWidth {
                lower = midpoint
            } else {
                upper = midpoint - 1
            }
        }

        return lower
    }

    private static func middleCandidate(
        _ characters: [Character],
        retaining count: Int
    ) -> String {
        let prefixCount = (count + 1) / 2
        let suffixCount = count / 2
        return String(characters.prefix(prefixCount))
            + ellipsis
            + String(characters.suffix(suffixCount))
    }

    private static func width(of text: String, font: NSFont) -> CGFloat {
        TextLineMetrics.measure(text: text, font: font).size.width
    }
}
