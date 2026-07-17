import Foundation

/// Standard competition ranking ("1, 2, 2, 4"): rows sharing a ranking value share a
/// rank, and the next distinct value skips ahead by the size of the tie group.
///
/// This is the single client-side definition of rank. It mirrors the Cloud Functions
/// ranking in `functions/src/leaderboardAchievements.ts` and
/// `functions/src/liveReplayLeaderboard.ts` so a client-displayed rank never contradicts
/// the rank the server used to award an achievement.
enum CompetitionRanking {
    /// Carries the tail of a ranked page across a page boundary so a tie group split
    /// by pagination keeps one rank.
    struct Continuation<Key: Equatable>: Equatable, Sendable where Key: Sendable {
        /// Ranking value of the last row ranked so far.
        let lastKey: Key
        /// Rank assigned to that row.
        let lastRank: Int
        /// How many rows have been ranked so far, across all previous pages.
        let rankedCount: Int

        init(lastKey: Key, lastRank: Int, rankedCount: Int) {
            self.lastKey = lastKey
            self.lastRank = max(lastRank, 1)
            self.rankedCount = max(rankedCount, 0)
        }
    }

    /// Assigns competition ranks to `items`, which must already be sorted best-first by
    /// the same key this ranks on.
    ///
    /// - Parameters:
    ///   - items: The pre-sorted rows to rank.
    ///   - continuation: Tail of the previous page, when ranking a paginated list.
    ///     Pass `nil` for the first page.
    ///   - key: The ranking value. Rows with equal keys are tied.
    /// - Returns: One rank per item, in the same order as `items`.
    static func ranks<Item, Key: Equatable>(
        for items: [Item],
        continuing continuation: Continuation<Key>? = nil,
        key: (Item) -> Key
    ) -> [Int] {
        var ranks: [Int] = []
        ranks.reserveCapacity(items.count)

        let rankedCountBefore = continuation?.rankedCount ?? 0
        var previousKey: Key? = continuation?.lastKey
        var previousRank = continuation?.lastRank ?? 0

        for (offset, item) in items.enumerated() {
            let itemKey = key(item)
            if itemKey != previousKey {
                previousRank = rankedCountBefore + offset + 1
                previousKey = itemKey
            }
            ranks.append(previousRank)
        }

        return ranks
    }

    /// Display token for a rank. A tie takes a "T" prefix — the sports-leaderboard
    /// convention — so a shared rank is obvious at a glance rather than reading as an
    /// ordinary ordering. Tied and untied labels stay the same width.
    ///
    /// - Parameter untiedPrefix: Prefix for the untied label, matching whatever the
    ///   calling surface already uses ("#" on the per-climb board, "" on the global
    ///   board). The "T" replaces it when tied, so "T" always means tied.
    static func rankLabel(_ rank: Int, isTied: Bool, untiedPrefix: String = "") -> String {
        isTied ? "T\(rank.formatted())" : "\(untiedPrefix)\(rank.formatted())"
    }

    /// Spoken equivalent of `rankLabel`, for accessibility labels.
    static func rankAccessibilityLabel(_ rank: Int, isTied: Bool) -> String {
        isTied ? "Tied for rank \(rank)" : "Rank \(rank)"
    }

    /// Marks which of `ranks` are shared with at least one other row, so tied rows can
    /// be called out in the UI.
    ///
    /// `ranks` must be a contiguous run of a single ranked ordering. A tie group split
    /// across a pagination boundary reads as untied until the neighbouring page loads
    /// and the flags are recomputed over the merged rows.
    static func tieFlags(for ranks: [Int]) -> [Bool] {
        var countsByRank: [Int: Int] = [:]
        for rank in ranks {
            countsByRank[rank, default: 0] += 1
        }

        return ranks.map { (countsByRank[$0] ?? 0) > 1 }
    }

    /// The competition rank of the row at `index` in a pre-sorted list — equivalently,
    /// one more than the number of strictly better rows.
    static func rank<Item, Key: Equatable>(
        at index: Int,
        in items: [Item],
        key: (Item) -> Key
    ) -> Int? {
        guard items.indices.contains(index) else { return nil }

        let target = key(items[index])
        var rank = index + 1
        var cursor = index
        while cursor > 0, key(items[cursor - 1]) == target {
            cursor -= 1
            rank -= 1
        }

        return rank
    }
}
