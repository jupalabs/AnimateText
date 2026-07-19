import Foundation

struct TextSegment: Equatable, Hashable, Sendable {
    let value: String
    let range: NSRange
}

enum TextSegmenter {
    static func segments(
        in text: String,
        granularity: TextMorphGranularity
    ) -> [TextSegment] {
        guard !text.isEmpty else { return [] }

        switch granularity {
        case .automatic:
            return text.contains(where: \.isWhitespace)
                ? wordSegments(in: text)
                : graphemeSegments(in: text)
        case .grapheme:
            return graphemeSegments(in: text)
        case .word:
            return wordSegments(in: text)
        }
    }

    static func graphemeSegments(in text: String) -> [TextSegment] {
        graphemeSegments(in: text.startIndex..<text.endIndex, of: text)
    }

    private static func graphemeSegments(
        in range: Range<String.Index>,
        of text: String
    ) -> [TextSegment] {
        var result: [TextSegment] = []
        var index = range.lowerBound

        while index < range.upperBound {
            let next = text.index(after: index)
            let characterRange = index..<next
            result.append(
                TextSegment(
                    value: String(text[characterRange]),
                    range: NSRange(characterRange, in: text)
                )
            )
            index = next
        }

        return result
    }

    private static func wordSegments(in text: String) -> [TextSegment] {
        var wordRanges: [Range<String.Index>] = []
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.byWords, .substringNotRequired]
        ) { _, range, _, _ in
            wordRanges.append(range)
        }

        guard !wordRanges.isEmpty else {
            return graphemeSegments(in: text)
        }

        var result: [TextSegment] = []
        var cursor = text.startIndex

        for wordRange in wordRanges {
            if cursor < wordRange.lowerBound {
                result.append(
                    contentsOf: graphemeSegments(
                        in: cursor..<wordRange.lowerBound,
                        of: text
                    )
                )
            }

            result.append(
                TextSegment(
                    value: String(text[wordRange]),
                    range: NSRange(wordRange, in: text)
                )
            )
            cursor = wordRange.upperBound
        }

        if cursor < text.endIndex {
            result.append(
                contentsOf: graphemeSegments(
                    in: cursor..<text.endIndex,
                    of: text
                )
            )
        }

        return result
    }
}
