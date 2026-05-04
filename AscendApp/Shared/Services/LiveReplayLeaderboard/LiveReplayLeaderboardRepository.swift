import Foundation

protocol LiveReplayLeaderboardRepository: Sendable {
    func fetchSummary(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayLeaderboardSummary

    func fetchWindow(
        context: LiveReplayLeaderboardContext,
        bucketIndex: Int,
        currentSteps: Int,
        rowsAhead: Int,
        rowsBehind: Int
    ) async throws -> LiveReplayLeaderboardWindow
}
