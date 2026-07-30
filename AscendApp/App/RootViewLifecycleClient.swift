import Foundation
import SwiftData

@MainActor
struct RootViewLifecycleClient {
    let processPendingUploads: @MainActor (ModelContext) async -> Void
    let bootstrapAuthenticatedLocalState: @MainActor (
        ModelContext,
        AuthenticatedUser?
    ) async -> AccountDataOwnershipConflict?
    let synchronizePushNotifications: @MainActor () async -> Void
    let loadUserData: @MainActor (String) async -> UserDisplayNameData?

    static let live = RootViewLifecycleClient(
        processPendingUploads: { modelContext in
            await MediaUploadManager.shared.processPendingUploads(modelContext: modelContext)
        },
        bootstrapAuthenticatedLocalState: { modelContext, user in
            await Self.bootstrapAuthenticatedLocalState(
                modelContext: modelContext,
                user: user
            )
        },
        synchronizePushNotifications: {
            await PushNotificationService.shared.synchronizeAuthenticatedDeviceIfNeeded()
        },
        loadUserData: { userID in
            try? await UserDataRepository.shared.getUserFromFirestore(userId: userID)
        }
    )

    static let noOp = RootViewLifecycleClient(
        processPendingUploads: { _ in },
        bootstrapAuthenticatedLocalState: { _, _ in nil },
        synchronizePushNotifications: {},
        loadUserData: { _ in nil }
    )

    private static func bootstrapAuthenticatedLocalState(
        modelContext: ModelContext,
        user: AuthenticatedUser?
    ) async -> AccountDataOwnershipConflict? {
        guard let user else {
            return nil
        }
        let currentUserId = user.uid

        do {
            switch try AccountDataOwnershipService.evaluateAccess(
                modelContext: modelContext,
                signedInUserId: currentUserId
            ) {
            case .allowed:
                break
            case .blocked(let conflict):
                return conflict
            }

            try WorkoutRemoteSyncMigrationService.runIfNeeded(
                modelContext: modelContext,
                currentUserId: currentUserId
            )
            AccountDataOwnershipService.recordAuthorizedOwner(signedInUserId: currentUserId)

            do {
                _ = try await WorkoutHydrationService.hydrateIfNeeded(
                    modelContext: modelContext,
                    currentUserId: currentUserId
                )
            } catch {
                debugLog("Workout hydration failed: \(error)")
            }

            await ClimbCompletionRepository.shared.refresh(
                userId: currentUserId,
                modelContext: modelContext
            )

            await WorkoutSyncCoordinator.shared.processPendingWorkouts(
                modelContext: modelContext,
                currentUserId: currentUserId
            )

            let leaderboardService = LeaderboardService.shared
            leaderboardService.configure(modelContext: modelContext)

            let workouts = try modelContext.fetch(
                FetchDescriptor<Workout>(
                    predicate: #Predicate<Workout> { workout in
                        workout.ownerUserId == currentUserId
                    },
                    sortBy: [SortDescriptor(\.date, order: .forward)]
                )
            )
            let didRebuild = try leaderboardService.rebuildCurrentStatsIfNeeded(
                for: currentUserId,
                workouts: workouts
            )

            if didRebuild {
                try await leaderboardService.deleteLegacyRemoteStats(userId: currentUserId)
                await LeaderboardSessionCache.shared.invalidateAll()
            }

            await LeaderboardSyncCoordinator.shared.enqueueSync(
                userId: currentUserId
            )

            await ProfilePublicationService.publishCurrentUserProfile(
                modelContext: modelContext,
                userId: currentUserId,
                joinedAt: user.creationDate
            )
        } catch {
            debugLog("Authenticated bootstrap failed: \(error)")
        }

        return nil
    }
}
