import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ClimbDetailViewModel {
    var climb: Climb
    var historySummary: ClimbHistorySummary
    var leaderboardSummary: LiveReplayLeaderboardSummary = .empty
    var leaderboardPreviewRows: [LiveReplayLeaderboardRow] = []
    var completionLeaderboard: LiveReplayCompletionLeaderboard = .empty
    var personalFinisherStatus: LiveReplayFinisherStatus?
    var isLeaderboardLoading = false
    var isLoadingMoreCompletionRows = false
    var leaderboardErrorMessage: String?
    var loadErrorMessage: String?

    private let climbService: ClimbService
    private let leaderboardService: LiveReplayLeaderboardServicing
    private let completionLeaderboardPageSize = 25
    private let completionLeaderboardPrefetchDistance = 5

    init(
        climb: Climb,
        climbService: ClimbService = .shared,
        leaderboardService: LiveReplayLeaderboardServicing = LiveReplayLeaderboardService.shared
    ) {
        self.climb = climb
        self.historySummary = .empty(for: climb)
        self.climbService = climbService
        self.leaderboardService = leaderboardService
    }

    var title: String {
        climb.name
    }

    var subtitle: String {
        climb.displayLocation
    }

    var hasCompletionHistory: Bool {
        historySummary.completionsCount > 0
    }

    var hasAttemptHistory: Bool {
        historySummary.attemptsCount > 0
    }

    var actionTitle: String {
        climb.isAvailable ? "Start Live Climb" : "Coming Soon"
    }

    var isActionEnabled: Bool {
        climb.isAvailable
    }

    var estimatedTimeText: String {
        ClimbEstimatedTimeFormatter.estimatedTimeText(
            for: climb.referenceStepCount,
            spm: SettingsManager.shared.effectiveBaseLevelSPM
        )
    }

    var communityCompletedCount: Int {
        max(
            leaderboardSummary.completedCount,
            completionLeaderboard.completedCount,
            personalFinisherOrder ?? 0,
            hasCompletionHistory ? 1 : 0
        )
    }

    var communityTotalClimbers: Int {
        max(
            leaderboardSummary.totalClimbers,
            communityCompletedCount
        )
    }

    var showsCommunityStats: Bool {
        true
    }

    var hasCompletionLeaderboardRows: Bool {
        !completionLeaderboard.rows.isEmpty
    }

    var hasMoreCompletionLeaderboardRows: Bool {
        completionLeaderboard.hasMoreRows
    }

    var completionLeaderboardRows: [LiveReplayLeaderboardRow] {
        completionLeaderboard.rows
    }

    var completionLeaderboardCompletedCount: Int {
        max(completionLeaderboard.completedCount, leaderboardSummary.completedCount, personalFinisherOrder ?? 0)
    }

    var shouldShowPersonalRankSummary: Bool {
        guard personalFinisherOrder != nil else { return false }
        return communityCompletedCount > 0
    }

    var personalFinisherOrder: Int? {
        personalFinisherStatus?.globalCompletionOrder ??
            historySummary.globalCompletionOrder ??
            estimatedPendingPersonalFinisherOrder
    }

    private var estimatedPendingPersonalFinisherOrder: Int? {
        guard historySummary.completionsCount > 0 else { return nil }

        let knownCompletedCount = max(
            leaderboardSummary.completedCount,
            completionLeaderboard.completedCount
        )

        return knownCompletedCount + 1
    }

    var stripOrderText: String? {
        let order = personalFinisherOrder
        guard let order else { return nil }
        return "#\(order)"
    }

    func refresh(modelContext: ModelContext) {
        do {
            if let refreshedClimb = try climbService.climb(for: climb.id) {
                climb = refreshedClimb
            }
            historySummary = climbService.historySummary(for: climb, modelContext: modelContext)
            loadErrorMessage = nil
        } catch {
            historySummary = .empty(for: climb)
            loadErrorMessage = error.localizedDescription
        }
    }

    func refreshLeaderboardSummary(modelContext: ModelContext) async {
        let context = leaderboardContext
        isLeaderboardLoading = true
        isLoadingMoreCompletionRows = false
        leaderboardErrorMessage = nil

        async let fetchedSummary = leaderboardService.fetchSummary(context: context)
        async let fetchedPreviewWindow = leaderboardService.refreshIfNeeded(
            context: context,
            elapsedSeconds: 0,
            currentSteps: 0,
            force: true
        )
        async let fetchedCompletionLeaderboard = leaderboardService.fetchCompletionLeaderboard(
            context: context,
            limit: completionLeaderboardPageSize,
            cursor: nil,
            forceRefresh: true
        )
        async let fetchedFinisherStatus = leaderboardService.fetchCurrentUserFinisherStatus(
            context: context
        )

        do {
            leaderboardSummary = try await fetchedSummary
        } catch {
            leaderboardSummary = .empty
        }

        do {
            let previewWindow = try await fetchedPreviewWindow
            leaderboardPreviewRows = previewWindow?.rows ?? []
        } catch {
            leaderboardPreviewRows = []
        }

        do {
            let leaderboard = try await fetchedCompletionLeaderboard
            completionLeaderboard = leaderboard
            leaderboardSummary = LiveReplayLeaderboardSummary(
                totalClimbers: max(leaderboardSummary.totalClimbers, leaderboard.completedCount),
                completedCount: max(leaderboardSummary.completedCount, leaderboard.completedCount),
                personalBestDurationSeconds: leaderboardSummary.personalBestDurationSeconds,
                firstAscent: leaderboardSummary.firstAscent,
                updatedAt: leaderboardSummary.updatedAt ?? leaderboard.updatedAt
            )
        } catch {
            completionLeaderboard = .empty
            leaderboardErrorMessage = error.localizedDescription
        }

        do {
            if let finisherStatus = try await fetchedFinisherStatus {
                personalFinisherStatus = finisherStatus
                try? climbService.mirrorFinisherStatus(
                    finisherStatus,
                    for: climb,
                    modelContext: modelContext
                )
                historySummary = climbService.historySummary(
                    for: climb,
                    modelContext: modelContext
                )
            }
        } catch {
            personalFinisherStatus = nil
        }

        isLeaderboardLoading = false
    }

    func loadMoreCompletionLeaderboardIfNeeded(currentRow: LiveReplayLeaderboardRow) {
        guard shouldLoadMoreCompletionLeaderboard(afterAppearing: currentRow),
              let cursor = completionLeaderboard.nextCursor else {
            return
        }

        isLoadingMoreCompletionRows = true
        let context = leaderboardContext

        Task {
            await loadMoreCompletionLeaderboard(
                context: context,
                cursor: cursor
            )
        }
    }

    private func loadMoreCompletionLeaderboard(
        context: LiveReplayLeaderboardContext,
        cursor: LiveReplayCompletionLeaderboardCursor
    ) async {
        do {
            let nextPage = try await leaderboardService.fetchCompletionLeaderboard(
                context: context,
                limit: completionLeaderboardPageSize,
                cursor: cursor,
                forceRefresh: false
            )
            completionLeaderboard = completionLeaderboard.appending(nextPage)
            leaderboardSummary = LiveReplayLeaderboardSummary(
                totalClimbers: max(leaderboardSummary.totalClimbers, completionLeaderboard.completedCount),
                completedCount: max(leaderboardSummary.completedCount, completionLeaderboard.completedCount),
                personalBestDurationSeconds: leaderboardSummary.personalBestDurationSeconds,
                firstAscent: leaderboardSummary.firstAscent,
                updatedAt: leaderboardSummary.updatedAt ?? completionLeaderboard.updatedAt
            )
        } catch {
            leaderboardErrorMessage = error.localizedDescription
        }

        isLoadingMoreCompletionRows = false
    }

    private func shouldLoadMoreCompletionLeaderboard(
        afterAppearing row: LiveReplayLeaderboardRow
    ) -> Bool {
        guard !isLeaderboardLoading,
              !isLoadingMoreCompletionRows,
              hasMoreCompletionLeaderboardRows,
              let rowIndex = completionLeaderboardRows.firstIndex(where: { $0.id == row.id }) else {
            return false
        }

        let thresholdIndex = max(
            completionLeaderboardRows.count - completionLeaderboardPrefetchDistance,
            0
        )
        return rowIndex >= thresholdIndex
    }

    private var leaderboardContext: LiveReplayLeaderboardContext {
        LiveReplayLeaderboardContext.liveClimb(
            climbId: climb.id,
            targetSteps: climb.referenceStepCount
        )
    }
}
