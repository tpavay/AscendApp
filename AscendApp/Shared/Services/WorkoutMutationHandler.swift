import FirebaseAuth
import Foundation
import SwiftData

/// Centralized handler for post-workout-mutation side effects.
///
/// Every code path that creates, edits, deletes, or imports workouts should call
/// `workoutsDidChange(modelContext:mutation:newWorkouts:)` after the mutation is persisted.
@MainActor
final class WorkoutMutationHandler {
    static let shared = WorkoutMutationHandler()

    private let settingsManager = SettingsManager.shared
    private let leaderboardService = LeaderboardService.shared

    private init() {}

    func workoutsDidChange(
        modelContext: ModelContext,
        mutation: WorkoutMutation = .rebuildAll,
        newWorkouts: [Workout] = []
    ) throws {
        try PersonalRecordService.recalculateAllPersonalRecords(
            modelContext: modelContext,
            measurementSystem: settingsManager.measurementSystem,
            stepHeight: settingsManager.stepHeight
        )

        try ClimbService.shared.apply(workouts: newWorkouts, modelContext: modelContext)

        guard let user = Auth.auth().currentUser else { return }
        let userId = user.uid

        leaderboardService.configure(modelContext: modelContext)
        let impact = LeaderboardMutationImpact.classify(mutation)
        let didUpdateLeaderboard = try leaderboardService.applyMutationImpact(impact, for: userId)
        guard didUpdateLeaderboard else { return }

        let cachedDisplayName = UserDataRepository.shared.getCachedDisplayName()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = cachedDisplayName?.isEmpty == false ? cachedDisplayName! : (user.displayName ?? "You")
        let cachedPhotoURL = UserDataRepository.shared.getCachedProfilePictureURL().flatMap(URL.init(string:))
        let photoURL = cachedPhotoURL ?? user.photoURL

        Task {
            await LeaderboardSessionCache.shared.invalidateAll()
            await LeaderboardSyncCoordinator.shared.enqueueSync(
                userId: userId,
                displayName: displayName,
                photoURL: photoURL
            )
        }
    }
}
