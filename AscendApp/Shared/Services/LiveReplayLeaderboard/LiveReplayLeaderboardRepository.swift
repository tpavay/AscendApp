import Foundation

protocol LiveReplayLeaderboardRepository: Sendable {
    func fetchSummary(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayLeaderboardSummary

    func fetchCompletionRank(
        context: LiveReplayLeaderboardContext,
        completionDurationSeconds: TimeInterval
    ) async throws -> LiveReplayCompletionRank

    func fetchCompletionLeaderboard(
        context: LiveReplayLeaderboardContext,
        limit: Int
    ) async throws -> LiveReplayCompletionLeaderboard

    func fetchWindow(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int,
        currentSteps: Int,
        rowsAhead: Int,
        rowsBehind: Int
    ) async throws -> LiveReplayLeaderboardWindow
}
