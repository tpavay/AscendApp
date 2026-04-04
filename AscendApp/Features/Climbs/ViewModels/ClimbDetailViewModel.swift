import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ClimbDetailViewModel {
    var climb: Climb
    var activeSummary: ActiveClimbSummary?
    var historySummary: ClimbHistorySummary
    var collectionOrder: Int?
    var projectedCollectionOrder: Int?
    var loadErrorMessage: String?

    private let climbService: ClimbService

    init(climb: Climb, climbService: ClimbService = .shared) {
        self.climb = climb
        self.historySummary = .empty(for: climb)
        self.climbService = climbService
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

    var actionTitle: String {
        if isCurrentActiveClimb {
            return "Continue Climb"
        }

        if hasCompletionHistory {
            return "Completed"
        }

        return "Start Climb"
    }

    var isActionEnabled: Bool {
        isCurrentActiveClimb || !hasCompletionHistory
    }

    var progressSummary: ActiveClimbSummary? {
        guard isCurrentActiveClimb else { return nil }
        return activeSummary
    }

    var estimatedTimeText: String {
        ClimbEstimatedTimeFormatter.estimatedTimeText(
            for: climb.referenceStepCount,
            spm: SettingsManager.shared.effectiveBaseLevelSPM
        )
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
