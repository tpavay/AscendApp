import Foundation
import Observation

@MainActor
@Observable
final class RoutineLeaderboardViewModel {
    private let leaderboardService: LiveReplayLeaderboardServicing
    private(set) var context: LiveReplayLeaderboardContext
    private(set) var summary: LiveReplayLeaderboardSummary = .empty
    private(set) var completionLeaderboard: LiveReplayCompletionLeaderboard = .empty
    private(set) var isLoading = false
    private(set) var fetchFailed = false
    private var hasLoaded = false

    init(
        routine: Routine,
        leaderboardService: LiveReplayLeaderboardServicing = LiveReplayLeaderboardService.shared
    ) {
        self.context = RoutineReplayLeaderboardContextBuilder.context(for: routine)
        self.leaderboardService = leaderboardService
    }

    var rows: [LiveReplayLeaderboardRow] {
        completionLeaderboard.rows
    }

    var completedCount: Int {
        max(summary.completedCount, completionLeaderboard.completedCount)
    }

    func updateRoutine(_ routine: Routine) {
        let nextContext = RoutineReplayLeaderboardContextBuilder.context(for: routine)
        guard nextContext != context else { return }

        context = nextContext
        summary = .empty
        completionLeaderboard = .empty
        fetchFailed = false
        hasLoaded = false
    }

    func refresh(force: Bool = false) async {
        guard !isLoading else { return }
        guard force || !hasLoaded else { return }

        isLoading = true
        fetchFailed = false

        let currentContext = context
        async let fetchedSummary = leaderboardService.fetchSummary(context: currentContext)
        async let fetchedLeaderboard = leaderboardService.fetchCompletionLeaderboard(
            context: currentContext,
            limit: 25
        )

        do {
            summary = try await fetchedSummary
        } catch {
            summary = .empty
            fetchFailed = true
        }

        do {
            completionLeaderboard = try await fetchedLeaderboard
        } catch {
            completionLeaderboard = .empty
            fetchFailed = true
        }

        hasLoaded = true
        isLoading = false
    }
}
