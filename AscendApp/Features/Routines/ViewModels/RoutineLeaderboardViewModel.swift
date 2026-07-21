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
    private(set) var isLoadingMore = false
    private(set) var fetchFailed = false
    private var hasLoaded = false
    private let pageSize = 25
    private let prefetchDistance = 5

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

    /// The board leads with the number it ranked on, which the context's metric decides.
    var rowEmphasis: LiveReplayRowEmphasis {
        context.type.rankingMetric.rowEmphasis
    }

    var hasMoreRows: Bool {
        completionLeaderboard.hasMoreRows
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
        isLoadingMore = false
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
            limit: pageSize,
            cursor: nil,
            forceRefresh: force
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

    func loadMoreIfNeeded(currentRow: LiveReplayLeaderboardRow) {
        guard shouldLoadMore(afterAppearing: currentRow),
              let cursor = completionLeaderboard.nextCursor else {
            return
        }

        isLoadingMore = true
        let currentContext = context

        Task {
            await loadMore(
                context: currentContext,
                cursor: cursor
            )
        }
    }

    private func loadMore(
        context: LiveReplayLeaderboardContext,
        cursor: LiveReplayCompletionLeaderboardCursor
    ) async {
        do {
            let nextPage = try await leaderboardService.fetchCompletionLeaderboard(
                context: context,
                limit: pageSize,
                cursor: cursor,
                forceRefresh: false
            )
            completionLeaderboard = completionLeaderboard.appending(nextPage)
            summary = LiveReplayLeaderboardSummary(
                totalClimbers: max(summary.totalClimbers, completionLeaderboard.completedCount),
                completedCount: max(summary.completedCount, completionLeaderboard.completedCount),
                personalBestDurationSeconds: summary.personalBestDurationSeconds,
                firstAscent: summary.firstAscent,
                updatedAt: summary.updatedAt ?? completionLeaderboard.updatedAt
            )
        } catch {
            fetchFailed = true
        }

        isLoadingMore = false
    }

    private func shouldLoadMore(afterAppearing row: LiveReplayLeaderboardRow) -> Bool {
        guard !isLoading,
              !isLoadingMore,
              hasMoreRows,
              let rowIndex = rows.firstIndex(where: { $0.id == row.id }) else {
            return false
        }

        let thresholdIndex = max(rows.count - prefetchDistance, 0)
        return rowIndex >= thresholdIndex
    }
}
