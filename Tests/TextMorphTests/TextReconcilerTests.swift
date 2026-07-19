import XCTest
@testable import TextMorph

final class TextReconcilerTests: XCTestCase {
    func testContinueToConfirmPreservesTheExpectedSharedLetters() {
        let old = Array("Continue").map(String.init)
        let new = Array("Confirm").map(String.init)
        let result = TextReconciler.reconcile(old: old, new: new)

        XCTAssertEqual(
            result.matches,
            [
                TextMatch(oldIndex: 0, newIndex: 0),
                TextMatch(oldIndex: 1, newIndex: 1),
                TextMatch(oldIndex: 2, newIndex: 2),
                TextMatch(oldIndex: 4, newIndex: 4),
            ]
        )
        XCTAssertEqual(result.insertionIndices, [3, 5, 6])
        XCTAssertEqual(result.removalIndices, [3, 5, 6, 7])
        XCTAssertEqual(result.changeRatio, 0.5, accuracy: 1e-12)
    }

    func testDuplicateMatchesPreferMinimumMovement() {
        let result = TextReconciler.reconcile(
            old: ["a", "a", "a"],
            new: ["a", "a"]
        )
        XCTAssertEqual(
            result.matches,
            [
                TextMatch(oldIndex: 0, newIndex: 0),
                TextMatch(oldIndex: 1, newIndex: 1),
            ]
        )
    }

    func testCanonicalUnicodeEquivalenceMatches() {
        let result = TextReconciler.reconcile(
            old: ["é"],
            new: ["e\u{301}"]
        )
        XCTAssertEqual(result.matches, [TextMatch(oldIndex: 0, newIndex: 0)])
        XCTAssertEqual(result.changeRatio, 0)
    }

    func testChangeRatioIsAlwaysBounded() {
        let replacement = TextReconciler.reconcile(
            old: ["a", "b", "c"],
            new: ["x", "y", "z"]
        )
        XCTAssertEqual(replacement.changeRatio, 1)

        let insertion = TextReconciler.reconcile(
            old: ["a"],
            new: ["a", "b", "c"]
        )
        XCTAssertEqual(insertion.changeRatio, 2.0 / 3.0, accuracy: 1e-12)

        let empty = TextReconciler.reconcile(old: [String](), new: [])
        XCTAssertEqual(empty.changeRatio, 0)
    }

    func testMatchesAreMonotonicAndOptimalForExhaustiveSmallInputs() {
        let alphabet = ["a", "b"]
        let values = allSequences(alphabet: alphabet, maximumLength: 5)

        for old in values {
            for new in values {
                let matches = TextReconciler.longestCommonSubsequence(
                    old: old,
                    new: new
                )
                XCTAssertEqual(
                    matches.count,
                    referenceLCSLength(old, new),
                    "\(old) -> \(new)"
                )

                for match in matches {
                    XCTAssertEqual(old[match.oldIndex], new[match.newIndex])
                }
                for (lhs, rhs) in zip(matches, matches.dropFirst()) {
                    XCTAssertLessThan(lhs.oldIndex, rhs.oldIndex)
                    XCTAssertLessThan(lhs.newIndex, rhs.newIndex)
                }
            }
        }
    }

    func testLinearMemoryFallbackStillFindsAnOptimalMatch() {
        let old = Array(repeating: "a", count: 2_001) + ["b"]
        let new = ["b"] + Array(repeating: "a", count: 2_001)
        let matches = TextReconciler.longestCommonSubsequence(old: old, new: new)

        XCTAssertEqual(matches.count, 2_001)
        XCTAssertTrue(matches.allSatisfy { old[$0.oldIndex] == new[$0.newIndex] })
    }

    private func allSequences(
        alphabet: [String],
        maximumLength: Int
    ) -> [[String]] {
        var result: [[String]] = [[]]
        guard maximumLength > 0 else { return result }

        var level: [[String]] = [[]]
        for _ in 1...maximumLength {
            level = level.flatMap { sequence in
                alphabet.map { sequence + [$0] }
            }
            result.append(contentsOf: level)
        }
        return result
    }

    private func referenceLCSLength<T: Equatable>(_ lhs: [T], _ rhs: [T]) -> Int {
        var row = Array(repeating: 0, count: rhs.count + 1)
        for lhsValue in lhs {
            var diagonal = 0
            for rhsIndex in rhs.indices {
                let previous = row[rhsIndex + 1]
                if lhsValue == rhs[rhsIndex] {
                    row[rhsIndex + 1] = diagonal + 1
                } else {
                    row[rhsIndex + 1] = max(row[rhsIndex + 1], row[rhsIndex])
                }
                diagonal = previous
            }
        }
        return row[rhs.count]
    }
}
