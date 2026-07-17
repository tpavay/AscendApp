import Foundation
import Testing
@testable import AscendApp

struct CompetitionRankingTests {
    @Test
    func distinctValuesRankSequentially() {
        let ranks = CompetitionRanking.ranks(for: [30, 20, 10]) { $0 }

        #expect(ranks == [1, 2, 3])
    }

    @Test
    func tiedValuesShareARankAndSkipTheNext() {
        // The canonical "1, 2, 2, 4" from CLAUDE.md: two tied for 2nd, nobody 3rd.
        let ranks = CompetitionRanking.ranks(for: [30, 20, 20, 10]) { $0 }

        #expect(ranks == [1, 2, 2, 4])
    }

    @Test
    func tieAtTheTopLeavesSecondPlaceUnawarded() {
        let ranks = CompetitionRanking.ranks(for: [30, 30, 10]) { $0 }

        #expect(ranks == [1, 1, 3])
    }

    @Test
    func everyoneTiedSharesFirst() {
        let ranks = CompetitionRanking.ranks(for: [30, 30, 30]) { $0 }

        #expect(ranks == [1, 1, 1])
    }

    @Test
    func trailingTieRunSharesTheEarliestRank() {
        let ranks = CompetitionRanking.ranks(for: [30, 20, 20, 20]) { $0 }

        #expect(ranks == [1, 2, 2, 2])
    }

    @Test
    func emptyInputProducesNoRanks() {
        let ranks = CompetitionRanking.ranks(for: [Int]()) { $0 }

        #expect(ranks.isEmpty)
    }

    @Test
    func rankIsIndependentOfTheOrderingTiebreak() {
        // Sorting breaks ties by uid so the list is stable, but rank must not see it —
        // this is exactly the bug where a tied user's displayed rank disagreed with the
        // rank the server used to award their achievement.
        let sorted = [("aaa", 30), ("mmm", 20), ("zzz", 20)]
        let ranks = CompetitionRanking.ranks(for: sorted) { $0.1 }

        #expect(ranks == [1, 2, 2])
    }

    // MARK: - Pagination

    @Test
    func continuationKeepsOneRankForATieGroupSplitAcrossPages() {
        let firstPage = [30, 20]
        let firstRanks = CompetitionRanking.ranks(for: firstPage) { $0 }
        let continuation = CompetitionRanking.Continuation(
            lastKey: firstPage[1],
            lastRank: firstRanks[1],
            rankedCount: firstPage.count
        )

        // The next page opens with the same value the previous page ended on.
        let secondRanks = CompetitionRanking.ranks(
            for: [20, 10],
            continuing: continuation,
            key: { $0 }
        )

        #expect(firstRanks == [1, 2])
        #expect(secondRanks == [2, 4])
    }

    @Test
    func continuationStartsANewValueAtItsAbsolutePosition() {
        let continuation = CompetitionRanking.Continuation(
            lastKey: 20,
            lastRank: 2,
            rankedCount: 3
        )

        let ranks = CompetitionRanking.ranks(for: [10, 5], continuing: continuation) { $0 }

        #expect(ranks == [4, 5])
    }

    // MARK: - Single-row lookups

    @Test
    func rankAtIndexReportsTheSharedRankForEveryTiedRow() {
        let values = [30, 20, 20, 10]

        #expect(CompetitionRanking.rank(at: 0, in: values, key: { $0 }) == 1)
        #expect(CompetitionRanking.rank(at: 1, in: values, key: { $0 }) == 2)
        #expect(CompetitionRanking.rank(at: 2, in: values, key: { $0 }) == 2)
        #expect(CompetitionRanking.rank(at: 3, in: values, key: { $0 }) == 4)
    }

    @Test
    func rankAtIndexMatchesFullListRanking() {
        let values = [50, 50, 50, 20, 20, 10]
        let ranks = CompetitionRanking.ranks(for: values) { $0 }
        let individual = values.indices.map { index in
            CompetitionRanking.rank(at: index, in: values, key: { value in value })
        }

        #expect(individual == ranks.map(Optional.init))
    }

    @Test
    func rankAtOutOfBoundsIndexIsNil() {
        #expect(CompetitionRanking.rank(at: 3, in: [30, 20], key: { $0 }) == nil)
        #expect(CompetitionRanking.rank(at: -1, in: [30, 20], key: { $0 }) == nil)
    }

    // MARK: - Tie flags

    @Test
    func tieFlagsMarkOnlySharedRanks() {
        #expect(CompetitionRanking.tieFlags(for: [1, 2, 2, 4]) == [false, true, true, false])
    }

    @Test
    func tieFlagsMarkEveryRowWhenAllShareARank() {
        #expect(CompetitionRanking.tieFlags(for: [1, 1, 1]) == [true, true, true])
    }

    @Test
    func tieFlagsAreEmptyForNoRanks() {
        #expect(CompetitionRanking.tieFlags(for: []).isEmpty)
    }

    // MARK: - Display

    @Test(arguments: [
        (3, false, "", "3"),
        (3, true, "", "T3"),
        (3, false, "#", "#3"),
        (3, true, "#", "T3"),
        (1, true, "#", "T1"),
        (12, true, "", "T12")
    ])
    func rankLabelPrefixesTiesWithT(
        rank: Int,
        isTied: Bool,
        untiedPrefix: String,
        expected: String
    ) {
        #expect(
            CompetitionRanking.rankLabel(rank, isTied: isTied, untiedPrefix: untiedPrefix) == expected
        )
    }

    @Test
    func rankAccessibilityLabelSaysTiedOutLoud() {
        #expect(CompetitionRanking.rankAccessibilityLabel(2, isTied: false) == "Rank 2")
        #expect(CompetitionRanking.rankAccessibilityLabel(2, isTied: true) == "Tied for rank 2")
    }
}
