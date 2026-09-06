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
    /// How long `fetchSummary` stalls before answering, standing in for a read that
    /// hangs rather than fails.
    var summaryFetchDelaySeconds: Double?
    /// What `refreshIfNeeded` hands back, so a test can prove the race rows land even
    /// when the count beside them does not.
    var window: LiveReplayLeaderboardWindow?
    /// The board `fetchCompletionLeaderboard` answers with. `nil` refuses, the way an
    /// unreachable board does; a surface that renders the board rather than racing it
    /// supplies one so it settles instead of showing "Leaderboard unavailable".
    var completionLeaderboard: LiveReplayCompletionLeaderboard?
    private(set) var summaryFetchCount = 0
    /// The frozen standing the server holds for a workout, and how many times it was asked for -
    /// the count is what proves a stored snapshot is served without a request.
    var completionRankSnapshot: LiveReplayCompletionRankSnapshot?
    private(set) var completionRankSnapshotFetchCount = 0

    init(
        summary: LiveReplayLeaderboardSummary = .empty,
        summaryFetchFailureCount: Int = 0,
        summaryFetchDelaySeconds: Double? = nil,
        window: LiveReplayLeaderboardWindow? = nil,
        completionLeaderboard: LiveReplayCompletionLeaderboard? = nil
    ) {
        self.summary = summary
        self.summaryFetchFailureCount = summaryFetchFailureCount
        self.summaryFetchDelaySeconds = summaryFetchDelaySeconds
        self.window = window
        self.completionLeaderboard = completionLeaderboard
    }

    func beginLiveSession() {}

    func fetchSummary(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayLeaderboardSummary {
        summaryFetchCount += 1

        if let summaryFetchDelaySeconds {
            try? await Task.sleep(for: .seconds(summaryFetchDelaySeconds))
        }

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
        completionRankSnapshotFetchCount += 1
        guard let completionRankSnapshot,
              completionRankSnapshot.workoutId == workoutId else {
            return nil
        }

        return completionRankSnapshot
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
        guard let completionLeaderboard else { throw CancellationError() }

        return completionLeaderboard
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
