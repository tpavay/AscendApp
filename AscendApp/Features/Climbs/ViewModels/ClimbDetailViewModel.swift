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
    var currentUserBestCompletion: LiveReplayCurrentUserCompletion?
    var personalCurrentCompletionRank: LiveReplayCompletionRank?
    var personalFinisherStatus: LiveReplayFinisherStatus?
    var publicResultSyncWorkout: Workout?
    var isLeaderboardLoading = false
    var isLoadingMoreCompletionRows = false
    var hasLoadedCompletionLeaderboard = false
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
            remoteCompletedCount,
            personalCurrentCompletionRank?.completedCount ?? 0
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
        max(
            remoteCompletedCount,
            personalCurrentCompletionRank?.completedCount ?? 0
        )
    }

    var shouldShowPersonalRankSummary: Bool {
        guard personalCurrentCompletionRank != nil else { return false }
        return communityCompletedCount > 0
    }

    var personalBestCompletionDurationSeconds: TimeInterval? {
        currentUserBestCompletion?.completionDurationSeconds ??
            personalFinisherStatus?.bestCompletionDurationSeconds ??
            historySummary.bestCompletionDurationSeconds.map(TimeInterval.init)
    }

    var personalFinisherOrder: Int? {
        personalFinisherStatus?.globalCompletionOrder ??
            historySummary.globalCompletionOrder
    }

    private var remoteCompletedCount: Int {
        if hasLoadedCompletionLeaderboard {
            return completionLeaderboard.completedCount
        }

        return max(
            leaderboardSummary.completedCount,
            completionLeaderboard.completedCount
        )
    }

    var stripOrderText: String? {
        guard communityCompletedCount > 0 else { return nil }

        if let order = personalFinisherOrder,
           order <= communityCompletedCount {
            return "#\(order.formatted())/\(communityCompletedCount.formatted())"
        }

        return "--/\(communityCompletedCount.formatted())"
    }

    func refresh(modelContext: ModelContext) {
        do {
            if let refreshedClimb = try climbService.climb(for: climb.id) {
                climb = refreshedClimb
            }
            historySummary = climbService.historySummary(for: climb, modelContext: modelContext)
            publicResultSyncWorkout = latestCompletedWorkout(for: climb, modelContext: modelContext)
            loadErrorMessage = nil
        } catch {
            historySummary = .empty(for: climb)
            publicResultSyncWorkout = nil
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
        async let fetchedCurrentUserBestCompletion = leaderboardService.fetchCurrentUserBestCompletion(
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
            hasLoadedCompletionLeaderboard = true
            leaderboardSummary = LiveReplayLeaderboardSummary(
                totalClimbers: max(leaderboardSummary.totalClimbers, leaderboard.completedCount),
                completedCount: leaderboard.completedCount,
                personalBestDurationSeconds: leaderboardSummary.personalBestDurationSeconds,
                firstAscent: leaderboardSummary.firstAscent,
                updatedAt: leaderboardSummary.updatedAt ?? leaderboard.updatedAt
            )
        } catch {
            completionLeaderboard = .empty
            hasLoadedCompletionLeaderboard = false
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
            } else {
                personalFinisherStatus = nil
            }
        } catch {
            personalFinisherStatus = nil
        }

        do {
            currentUserBestCompletion = try await fetchedCurrentUserBestCompletion
        } catch {
            currentUserBestCompletion = nil
        }

        if let currentUserBestCompletion {
            personalCurrentCompletionRank = LiveReplayCompletionRank(
                rank: currentUserBestCompletion.rank,
                completedCount: currentUserBestCompletion.completedCount,
                updatedAt: currentUserBestCompletion.updatedAt,
                isTied: currentUserBestCompletion.isTied
            )
        } else {
            personalCurrentCompletionRank = nil
        }

        isLeaderboardLoading = false
    }

    func loadMoreCompletionLeaderboardIfNeeded(currentRowID: String) {
        guard shouldLoadMoreCompletionLeaderboard(afterAppearingRowID: currentRowID),
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
            hasLoadedCompletionLeaderboard = true
            leaderboardSummary = LiveReplayLeaderboardSummary(
                totalClimbers: max(leaderboardSummary.totalClimbers, completionLeaderboard.completedCount),
                completedCount: completionLeaderboard.completedCount,
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
        afterAppearingRowID rowID: String
    ) -> Bool {
        guard !isLeaderboardLoading,
              !isLoadingMoreCompletionRows,
              hasMoreCompletionLeaderboardRows,
              let rowIndex = completionLeaderboardRows.firstIndex(where: { $0.id == rowID }) else {
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

    private func latestCompletedWorkout(
        for climb: Climb,
        modelContext: ModelContext
    ) -> Workout? {
        let completedStatus = ClimbAttemptStatus.completed.rawValue
        let attemptsDescriptor = FetchDescriptor<ClimbAttempt>(
            predicate: #Predicate<ClimbAttempt> { attempt in
                attempt.climbId == climb.id && attempt.statusRawValue == completedStatus
            },
            sortBy: [SortDescriptor(\ClimbAttempt.completedAt, order: .reverse)]
        )

        guard let attempts = try? modelContext.fetch(attemptsDescriptor),
              !attempts.isEmpty,
              let workouts = try? modelContext.fetch(FetchDescriptor<Workout>()) else {
            return nil
        }

        let workoutsById = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id.uuidString, $0) })

        for attempt in attempts {
            for workoutId in attempt.appliedWorkoutIds.reversed() {
                if let workout = workoutsById[workoutId] {
                    return workout
                }
            }
        }

        return nil
    }
}
