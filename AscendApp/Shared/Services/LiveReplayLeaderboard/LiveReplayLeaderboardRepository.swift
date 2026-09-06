import Foundation

protocol LiveReplayLeaderboardRepository: Sendable {
    /// Marks the start of a live session, ahead of its first `fetchWindow`.
    ///
    /// What a repository remembers about the signed-in climber's own rows is
    /// true for the length of one session and no longer - the attempt that just
    /// ended publishes a new one - so a session on the same board must not
    /// inherit the last one's answers.
    func beginLiveSession() async

    func fetchSummary(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayLeaderboardSummary

    func fetchCompletionRank(
        context: LiveReplayLeaderboardContext,
        completionDurationSeconds: TimeInterval,
        finalSteps: Int
    ) async throws -> LiveReplayCompletionRank

    func fetchCompletionRankSnapshot(
        context: LiveReplayLeaderboardContext,
        workoutId: String
    ) async throws -> LiveReplayCompletionRankSnapshot?

    func fetchPublishStatus(
        workoutId: String
    ) async throws -> LiveReplayPublishStatus?

    func fetchCurrentUserBestCompletion(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayCurrentUserCompletion?

    func fetchCurrentUserFinisherStatus(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayFinisherStatus?

    func fetchCompletionLeaderboard(
        context: LiveReplayLeaderboardContext,
        limit: Int,
        cursor: LiveReplayCompletionLeaderboardCursor?,
        forceRefresh: Bool
    ) async throws -> LiveReplayCompletionLeaderboard

    func fetchWindow(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int,
        currentSteps: Int,
        rowsAhead: Int,
        rowsBehind: Int
    ) async throws -> LiveReplayLeaderboardWindow
}

extension LiveReplayLeaderboardRepository {
    func fetchCompletionLeaderboard(
        context: LiveReplayLeaderboardContext,
        limit: Int
    ) async throws -> LiveReplayCompletionLeaderboard {
        try await fetchCompletionLeaderboard(
            context: context,
            limit: limit,
            cursor: nil,
            forceRefresh: false
        )
    }

    func fetchCompletionLeaderboard(
        context: LiveReplayLeaderboardContext,
        limit: Int,
        cursor: LiveReplayCompletionLeaderboardCursor?
    ) async throws -> LiveReplayCompletionLeaderboard {
        try await fetchCompletionLeaderboard(
            context: context,
            limit: limit,
            cursor: cursor,
            forceRefresh: false
        )
    }
}
