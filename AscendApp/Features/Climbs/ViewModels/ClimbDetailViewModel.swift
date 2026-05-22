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
    var personalCompletionRank: LiveReplayCompletionRank?
    var isLeaderboardLoading = false
    var leaderboardErrorMessage: String?
    var collectionOrder: Int?
    var loadErrorMessage: String?

    private let climbService: ClimbService
    private let leaderboardService: LiveReplayLeaderboardServicing

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
        "Start Live Climb"
    }

    var isActionEnabled: Bool {
        true
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

    var completionLeaderboardRows: [LiveReplayLeaderboardRow] {
        completionLeaderboard.rows
    }

    var completionLeaderboardCompletedCount: Int {
        max(completionLeaderboard.completedCount, leaderboardSummary.completedCount)
    }

    var shouldShowPersonalRankSummary: Bool {
        guard let personalCompletionRank else { return false }
        return !completionLeaderboard.rows.contains(where: \.isCurrentUser) &&
            personalCompletionRank.completedCount > 0
    }

    var stripOrderText: String? {
        let order = collectionOrder
        guard let order else { return nil }
        return "#\(order)"
    }

    func refresh(modelContext: ModelContext) {
        do {
            if let refreshedClimb = try climbService.climb(for: climb.id) {
                climb = refreshedClimb
            }
            historySummary = climbService.historySummary(for: climb, modelContext: modelContext)
            collectionOrder = climbService.collectionOrder(for: climb, modelContext: modelContext)
            loadErrorMessage = nil
        } catch {
            historySummary = .empty(for: climb)
            collectionOrder = nil
            loadErrorMessage = error.localizedDescription
        }
    }

    func refreshLeaderboardSummary() async {
        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: climb.id,
            targetSteps: climb.referenceStepCount
        )
        isLeaderboardLoading = true
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
            limit: 25
        )
        async let fetchedPersonalRank = fetchPersonalCompletionRank(context: context)

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
            personalCompletionRank = try await fetchedPersonalRank
        } catch {
            personalCompletionRank = nil
        }

        isLeaderboardLoading = false
    }

    private func fetchPersonalCompletionRank(
        context: LiveReplayLeaderboardContext
    ) async throws -> LiveReplayCompletionRank? {
        guard let bestCompletionDurationSeconds = historySummary.bestCompletionDurationSeconds else {
            return nil
        }

        return try await leaderboardService.fetchCompletionRank(
            context: context,
            completionDurationSeconds: TimeInterval(bestCompletionDurationSeconds)
        )
    }

}
