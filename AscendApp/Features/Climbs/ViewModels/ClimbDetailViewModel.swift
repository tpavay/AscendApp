import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ClimbDetailViewModel {
    var climb: Climb
    var activeSummary: ActiveClimbSummary?
    var historySummary: ClimbHistorySummary
    var leaderboardSummary: LiveReplayLeaderboardSummary = .empty
    var leaderboardPreviewRows: [LiveReplayLeaderboardRow] = []
    var collectionOrder: Int?
    var projectedCollectionOrder: Int?
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

    var isCurrentActiveClimb: Bool {
        activeSummary?.climb.id == climb.id
    }

    var conflictingActiveSummary: ActiveClimbSummary? {
        guard let activeSummary, activeSummary.climb.id != climb.id else { return nil }
        return activeSummary
    }

    var hasCompletionHistory: Bool {
        historySummary.completionsCount > 0
    }

    var hasAttemptHistory: Bool {
        historySummary.attemptsCount > 0
    }

    var hasIncompleteAttemptHistory: Bool {
        historySummary.failedAttemptsCount > 0 || (isCurrentActiveClimb && !hasCompletionHistory)
    }

    var actionTitle: String {
        if isCurrentActiveClimb {
            guard let activeSummary,
                  activeSummary.climb.multiSession,
                  activeSummary.sessionsCount > 0 else {
                return "Start Live Climb"
            }

            return "Continue Live Climb"
        }

        return "Start Live Climb"
    }

    var isActionEnabled: Bool {
        true
    }

    var progressSummary: ActiveClimbSummary? {
        guard showsPersistentProgressControls else { return nil }
        return activeSummary
    }

    var showsPersistentProgressControls: Bool {
        isCurrentActiveClimb && climb.multiSession
    }

    var estimatedTimeText: String {
        ClimbEstimatedTimeFormatter.estimatedTimeText(
            for: climb.referenceStepCount,
            spm: SettingsManager.shared.effectiveBaseLevelSPM
        )
    }

    var communityCompletedCount: Int {
        max(leaderboardSummary.completedCount, hasCompletionHistory ? 1 : 0)
    }

    var communityTotalClimbers: Int {
        max(
            leaderboardSummary.totalClimbers,
            communityCompletedCount,
            hasAttemptHistory || isCurrentActiveClimb ? 1 : 0
        )
    }

    var showsCommunityStats: Bool {
        true
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
            activeSummary = try climbService.activeSummary(modelContext: modelContext)
            historySummary = climbService.historySummary(for: climb, modelContext: modelContext)
            collectionOrder = climbService.collectionOrder(for: climb, modelContext: modelContext)
            projectedCollectionOrder = climbService.projectedCollectionOrder(for: climb, modelContext: modelContext)
            loadErrorMessage = nil
        } catch {
            activeSummary = nil
            historySummary = .empty(for: climb)
            collectionOrder = nil
            projectedCollectionOrder = nil
            loadErrorMessage = error.localizedDescription
        }
    }

    func refreshLeaderboardSummary() async {
        let context = LiveReplayLeaderboardContext.liveClimb(
            climbId: climb.id,
            targetSteps: climb.referenceStepCount
        )
        async let fetchedSummary = leaderboardService.fetchSummary(context: context)
        async let fetchedPreviewWindow = leaderboardService.refreshIfNeeded(
            context: context,
            elapsedSeconds: 0,
            currentSteps: 0,
            force: true
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
    }

    func startClimb(modelContext: ModelContext) throws {
        _ = try climbService.startClimb(climb, modelContext: modelContext)
        refresh(modelContext: modelContext)
    }

    func replaceActiveClimb(modelContext: ModelContext) throws {
        _ = try climbService.replaceActiveClimb(with: climb, modelContext: modelContext)
        refresh(modelContext: modelContext)
    }

    func abandonActiveClimb(modelContext: ModelContext) throws {
        _ = try climbService.abandonActiveClimb(modelContext: modelContext)
        refresh(modelContext: modelContext)
    }
}
