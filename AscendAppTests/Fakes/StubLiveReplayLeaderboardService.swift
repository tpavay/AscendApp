import Foundation
@testable import AscendApp

/// A replay leaderboard that answers from memory, keeping a recorded session off
/// Firestore. Every read a live session does not need refuses, the way an
/// unreachable board does.
///
/// `summaryFetchFailureCount` is the interesting knob: a session fetches its summary
/// once at start and the field-size line states that count or nothing, so a test can
/// put a blip on the opening fetch and prove the count still arrives on a later tick.
final class StubLiveReplayLeaderboardService: LiveReplayLeaderboardServicing, @unchecked Sendable {
    var summary: LiveReplayLeaderboardSummary
    var summaryFetchFailureCount: Int
    /// What `refreshIfNeeded` hands back, so a test can prove the race rows land even
    /// when the count beside them does not.
    var window: LiveReplayLeaderboardWindow?
    private(set) var summaryFetchCount = 0

    init(
        summary: LiveReplayLeaderboardSummary = .empty,
        summaryFetchFailureCount: Int = 0,
        window: LiveReplayLeaderboardWindow? = nil
    ) {
        self.summary = summary
        self.summaryFetchFailureCount = summaryFetchFailureCount
        self.window = window
    }

    func fetchSummary(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayLeaderboardSummary {
        summaryFetchCount += 1

        if summaryFetchCount <= summaryFetchFailureCount {
            throw CancellationError()
        }

        return summary
    }

    func fetchCompletionRank(
        context: LiveReplayLeaderboardContext,
        completionDurationSeconds: TimeInterval,
        finalSteps: Int
    ) async throws -> LiveReplayCompletionRank {
        throw CancellationError()
    }

    func fetchCompletionRankSnapshot(
        context: LiveReplayLeaderboardContext,
        workoutId: String
    ) async throws -> LiveReplayCompletionRankSnapshot? {
        nil
    }

    func fetchPublishStatus(workoutId: String) async throws -> LiveReplayPublishStatus? {
        nil
    }

    func fetchCurrentUserBestCompletion(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayCurrentUserCompletion? {
        nil
    }

    func fetchCurrentUserFinisherStatus(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayFinisherStatus? {
        nil
    }

    func fetchCompletionLeaderboard(
        context: LiveReplayLeaderboardContext,
        limit: Int,
        cursor: LiveReplayCompletionLeaderboardCursor?,
        forceRefresh: Bool
    ) async throws -> LiveReplayCompletionLeaderboard {
        throw CancellationError()
    }

    func refreshIfNeeded(
        context: LiveReplayLeaderboardContext,
        elapsedSeconds: Int,
        currentSteps: Int,
        force: Bool
    ) async throws -> LiveReplayLeaderboardWindow? {
        window
    }
}
