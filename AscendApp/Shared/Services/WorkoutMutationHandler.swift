import FirebaseAuth
import Foundation
import SwiftData

/// Centralized handler for post-workout-mutation side effects.
///
/// Every code path that creates, edits, deletes, or imports workouts should call
/// `workoutsDidChange(modelContext:mutation:newWorkouts:changedWorkouts:)`
/// after the mutation is persisted.
@MainActor
final class WorkoutMutationHandler {
    static let shared = WorkoutMutationHandler()

    private let leaderboardService = LeaderboardService.shared

    private init() {}

    func workoutsDidChange(
        modelContext: ModelContext,
        mutation: WorkoutMutation = .rebuildAll,
        newWorkouts: [Workout] = [],
        changedWorkouts: [Workout] = []
    ) throws {
        let currentUser = Auth.auth().currentUser
        let currentUserId = currentUser?.uid

        if let currentUserId {
            markChangedWorkoutsForRemoteSync(changedWorkouts, userId: currentUserId)
        }

        if let currentUser {
            let userId = currentUser.uid
            leaderboardService.configure(modelContext: modelContext)
            let impact = LeaderboardMutationImpact.classify(mutation)
            let didUpdateLeaderboard = try leaderboardService.applyMutationImpact(impact, for: userId)

            try modelContext.save()
            rebuildBestEffortCacheAfterMutation(modelContext: modelContext)

            if !changedWorkouts.isEmpty {
                Task { @MainActor in
                    await WorkoutSyncCoordinator.shared.processPendingWorkouts(
                        modelContext: modelContext,
                        currentUserId: userId
                    )
                }
            }

            guard didUpdateLeaderboard else { return }

            let cachedDisplayName = UserDataRepository.shared.getCachedDisplayName()?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = cachedDisplayName?.isEmpty == false ? cachedDisplayName! : (currentUser.displayName ?? "You")
            let cachedPhotoURL = UserDataRepository.shared.getCachedProfilePictureURL().flatMap(URL.init(string:))
            let photoURL = cachedPhotoURL ?? currentUser.photoURL

            Task {
                await LeaderboardSessionCache.shared.invalidateAll()
                await LeaderboardSyncCoordinator.shared.enqueueSync(
                    userId: userId,
                    displayName: displayName,
                    photoURL: photoURL
                )
            }

            return
        }

        try modelContext.save()
        rebuildBestEffortCacheAfterMutation(modelContext: modelContext)
    }

    func markChangedWorkoutsForRemoteSync(
        _ changedWorkouts: [Workout],
        userId: String,
        modifiedAt: Date = Date()
    ) {
        for workout in changedWorkouts {
            workout.markPendingRemoteUpsert(ownerUserId: userId, modifiedAt: modifiedAt)
        }
    }

    private func rebuildBestEffortCacheAfterMutation(modelContext: ModelContext) {
        do {
            try BestEffortCacheStore.rebuild(modelContext: modelContext)
        } catch {
            print("Failed to rebuild Best Effort cache after workout mutation: \(error)")
        }
    }
}
