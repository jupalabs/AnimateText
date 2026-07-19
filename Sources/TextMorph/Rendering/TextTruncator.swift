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
        guard maximumWidth.isFinite, maximumWidth > 0 else { return "" }
        guard width(of: text, font: font) > maximumWidth else { return text }
        guard width(of: ellipsis, font: font) <= maximumWidth else { return "" }

        let characters = Array(text)
        guard !characters.isEmpty else { return text }

        switch mode {
        case .none:
            return text
        case .head:
            let count = maximumFittingCount(upTo: characters.count) { count in
                ellipsis + String(characters.suffix(count))
            }
            return ellipsis + String(characters.suffix(count))
        case .middle:
            let count = maximumFittingCount(upTo: characters.count) { count in
                middleCandidate(characters, retaining: count)
            }
            return middleCandidate(characters, retaining: count)
        case .tail:
            let count = maximumFittingCount(upTo: characters.count) { count in
                String(characters.prefix(count)) + ellipsis
            }
            return String(characters.prefix(count)) + ellipsis
        }

        func maximumFittingCount(
            upTo upperBound: Int,
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
