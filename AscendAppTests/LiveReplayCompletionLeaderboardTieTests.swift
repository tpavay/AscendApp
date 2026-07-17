import Foundation
import Testing
@testable import AscendApp

/// The per-climb completion leaderboard ranks every completed attempt by duration.
/// These lock the tie behaviour the Cloud Function already uses when it stamps
/// `tiePolicy: "competition_rank_equal_durations_share_rank"` onto a completion.
struct LiveReplayCompletionLeaderboardTieTests {
    @Test
    func rowsSharingARankAreFlaggedAsTied() {
        let leaderboard = LiveReplayCompletionLeaderboard(
            rows: [
                makeRow(id: "a", rank: 1, durationSeconds: 600),
                makeRow(id: "b", rank: 2, durationSeconds: 700),
                makeRow(id: "c", rank: 2, durationSeconds: 700),
                makeRow(id: "d", rank: 4, durationSeconds: 800)
            ],
            completedCount: 4,
            updatedAt: nil
        )

        #expect(leaderboard.rows.map(\.isTied) == [false, true, true, false])
    }

    @Test
    func untiedRowsAreNotFlagged() {
        let leaderboard = LiveReplayCompletionLeaderboard(
            rows: [
                makeRow(id: "a", rank: 1, durationSeconds: 600),
                makeRow(id: "b", rank: 2, durationSeconds: 700)
            ],
            completedCount: 2,
            updatedAt: nil
        )

        #expect(leaderboard.rows.allSatisfy { $0.isTied == false })
    }

    @Test
    func tieGroupSplitAcrossPagesCorrectsItselfOnceMerged() {
        // The tie is invisible while only the first page is loaded — the partner row
        // hasn't arrived yet — and must resolve as soon as the next page merges in.
        let firstPage = LiveReplayCompletionLeaderboard(
            rows: [
                makeRow(id: "a", rank: 1, durationSeconds: 600),
                makeRow(id: "b", rank: 2, durationSeconds: 700)
            ],
            completedCount: 3,
            updatedAt: nil
        )
        #expect(firstPage.rows.map(\.isTied) == [false, false])

        let secondPage = LiveReplayCompletionLeaderboard(
            rows: [makeRow(id: "c", rank: 2, durationSeconds: 700)],
            completedCount: 3,
            updatedAt: nil
        )

        let merged = firstPage.appending(secondPage)

        #expect(merged.rows.map(\.id) == ["a", "b", "c"])
        #expect(merged.rows.map(\.isTied) == [false, true, true])
    }

    @Test
    func mergingDoesNotDuplicateRowsOrDisturbTieFlags() {
        let page = LiveReplayCompletionLeaderboard(
            rows: [
                makeRow(id: "a", rank: 1, durationSeconds: 700),
                makeRow(id: "b", rank: 1, durationSeconds: 700)
            ],
            completedCount: 2,
            updatedAt: nil
        )

        let merged = page.appending(page)

        #expect(merged.rows.map(\.id) == ["a", "b"])
        #expect(merged.rows.map(\.isTied) == [true, true])
    }

    @Test
    func rowsWithoutARankAreNeverFlaggedAsTied() {
        let leaderboard = LiveReplayCompletionLeaderboard(
            rows: [
                makeRow(id: "a", rank: nil, durationSeconds: 700),
                makeRow(id: "b", rank: nil, durationSeconds: 700)
            ],
            completedCount: 2,
            updatedAt: nil
        )

        #expect(leaderboard.rows.allSatisfy { $0.isTied == false })
    }

    // MARK: - Pinned row vs list row

    /// The reported bug: the list numbered rows by position (a tied user read "#3")
    /// while the pinned row counted strictly-faster attempts (the same user read "#2").
    ///
    /// `strictlyFasterCount + 1` is what the pinned row and the Cloud Function both
    /// compute, expressed here independently of `CompetitionRanking`. Every list rank
    /// must equal it, on any distribution of durations.
    @Test(arguments: [
        [600.0, 700.0, 800.0],
        [600.0, 700.0, 700.0, 800.0],
        [700.0, 700.0, 800.0],
        [600.0, 700.0, 700.0, 700.0],
        [700.0, 700.0, 700.0],
        [600.0]
    ])
    func listRankAlwaysEqualsStrictlyFasterCountPlusOne(durations: [TimeInterval]) {
        let listRanks = CompetitionRanking.ranks(for: durations) { $0 }
        let pinnedRanks = durations.map { duration in
            durations.filter { $0 < duration }.count + 1
        }

        #expect(listRanks == pinnedRanks)
    }

    private func makeRow(
        id: String,
        rank: Int?,
        durationSeconds: TimeInterval
    ) -> LiveReplayLeaderboardRow {
        LiveReplayLeaderboardRow(
            id: id,
            rank: rank,
            displayName: "Climber \(id)",
            avatarToken: id.uppercased(),
            photoURL: nil,
            stepsAtBucket: 3_000,
            finalSteps: 3_000,
            deltaFromUser: 0,
            isCurrentUser: false,
            isPersonalBest: false,
            completionDurationSeconds: durationSeconds,
            userId: "user-\(id)"
        )
    }
}
