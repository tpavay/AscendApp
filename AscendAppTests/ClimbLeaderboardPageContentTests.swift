import Testing
@testable import AscendApp

/// The Leaderboard tab's board region resolves to exactly one piece of content. These pin the
/// frames where a climber's rank and the board rows disagree, because they arrive from two
/// separate server reads (`fetchCurrentUserBestCompletion` and `fetchCompletionLeaderboard`).
struct ClimbLeaderboardPageContentTests {
    @Test("A finisher whose board rows have not landed yet sees the board loading, not nothing")
    func personalStandingWithoutRowsResolvesToLoading() {
        let content = ClimbLeaderboardPageContent.resolve(
            hasCompletionRows: false,
            isLeaderboardLoading: false,
            hasPersonalCompletionStanding: true,
            hasLeaderboardError: false,
            publicResultSyncPhase: nil
        )

        #expect(content == .loading)
    }

    @Test("A finisher whose board rows have not landed is never told nobody has finished")
    func personalStandingNeverResolvesToTheEmptyState() {
        for phase in Self.allSyncPhases {
            for hasError in [true, false] {
                let content = ClimbLeaderboardPageContent.resolve(
                    hasCompletionRows: false,
                    isLeaderboardLoading: false,
                    hasPersonalCompletionStanding: true,
                    hasLeaderboardError: hasError,
                    publicResultSyncPhase: phase
                )

                #expect(content != .empty, "phase \(String(describing: phase)), error \(hasError)")
            }
        }
    }

    @Test("A finisher whose board fetch threw sees the unavailable line instead of a spinner")
    func personalStandingWithAFailedFetchResolvesToUnavailable() {
        let content = ClimbLeaderboardPageContent.resolve(
            hasCompletionRows: false,
            isLeaderboardLoading: false,
            hasPersonalCompletionStanding: true,
            hasLeaderboardError: true,
            publicResultSyncPhase: nil
        )

        #expect(content == .unavailable)
    }

    @Test("Rows outrank every other state once they arrive")
    func presentRowsResolveToRows() {
        for hasStanding in [true, false] {
            for isLoading in [true, false] {
                for hasError in [true, false] {
                    let content = ClimbLeaderboardPageContent.resolve(
                        hasCompletionRows: true,
                        isLeaderboardLoading: isLoading,
                        hasPersonalCompletionStanding: hasStanding,
                        hasLeaderboardError: hasError,
                        publicResultSyncPhase: .published
                    )

                    #expect(content == .rows)
                }
            }
        }
    }

    @Test("A climber with no standing and no rows still sees the First Ascent invitation")
    func noStandingAndNoRowsResolvesToEmpty() {
        let content = ClimbLeaderboardPageContent.resolve(
            hasCompletionRows: false,
            isLeaderboardLoading: false,
            hasPersonalCompletionStanding: false,
            hasLeaderboardError: false,
            publicResultSyncPhase: nil
        )

        #expect(content == .empty)
    }

    @Test("A failed board fetch still leaves the empty state up for a climber with no standing")
    func noStandingWithAFailedFetchStillResolvesToEmpty() {
        let content = ClimbLeaderboardPageContent.resolve(
            hasCompletionRows: false,
            isLeaderboardLoading: false,
            hasPersonalCompletionStanding: false,
            hasLeaderboardError: true,
            publicResultSyncPhase: nil
        )

        #expect(content == .empty)
    }

    @Test(
        "A climber whose own result is still reaching the board sees loading, not the empty state",
        arguments: [LiveClimbPublicResultPhase.pending, .syncingRanking]
    )
    func inFlightPublicResultResolvesToLoading(phase: LiveClimbPublicResultPhase) {
        let content = ClimbLeaderboardPageContent.resolve(
            hasCompletionRows: false,
            isLeaderboardLoading: false,
            hasPersonalCompletionStanding: false,
            hasLeaderboardError: false,
            publicResultSyncPhase: phase
        )

        #expect(content == .loading)
    }

    @Test(
        "A settled public result leaves the empty state up",
        arguments: [
            LiveClimbPublicResultPhase.savedOnDevice,
            .syncFailedRetry,
            .published
        ]
    )
    func settledPublicResultResolvesToEmpty(phase: LiveClimbPublicResultPhase) {
        let content = ClimbLeaderboardPageContent.resolve(
            hasCompletionRows: false,
            isLeaderboardLoading: false,
            hasPersonalCompletionStanding: false,
            hasLeaderboardError: false,
            publicResultSyncPhase: phase
        )

        #expect(content == .empty)
    }

    @Test("An in-flight board fetch reports itself")
    func inFlightLeaderboardFetchResolvesToLoading() {
        let content = ClimbLeaderboardPageContent.resolve(
            hasCompletionRows: false,
            isLeaderboardLoading: true,
            hasPersonalCompletionStanding: false,
            hasLeaderboardError: false,
            publicResultSyncPhase: nil
        )

        #expect(content == .loading)
    }

    private static let allSyncPhases: [LiveClimbPublicResultPhase?] = [
        nil,
        .pending,
        .savedOnDevice,
        .syncingRanking,
        .syncFailedRetry,
        .published
    ]
}
