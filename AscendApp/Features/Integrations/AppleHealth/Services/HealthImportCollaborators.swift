import Foundation
import SwiftData
@preconcurrency import UserNotifications

// MARK: - Notification

/// Tells the climber an import landed. A protocol so the import rules are tested without a
/// notification center.
@MainActor
protocol HealthImportNotifying: AnyObject {
    func climbImported(workoutID: UUID, steps: Int?) async
}

/// The "Climb imported" local notification.
///
/// It rides on the iOS notification authorization the climber already gave the app - Ascend asks
/// for it once, at the climb-drop opt-in - and never asks on its own. Without it, nothing is
/// sent: the green strip on Home is the fallback and the only signal. It does not read the
/// climb-drop preference, because that is a promise about climb releases and this is a receipt for
/// something the climber's own watch did.
@MainActor
final class LocalHealthImportNotifier: HealthImportNotifying {
    static let notificationType = "climb_imported"
    static let workoutIDKey = "workoutId"

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func climbImported(workoutID: UUID, steps: Int?) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus.allowsRemoteUserVisibleNotifications else { return }

        let copy = AppleHealthImportPolicy.notificationContent(steps: steps)
        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        content.sound = .default
        content.userInfo = [
            "type": Self.notificationType,
            Self.workoutIDKey: workoutID.uuidString
        ]

        // One request per workout: a retried import replaces its own notification, never stacks.
        let request = UNNotificationRequest(
            identifier: "health-import-\(workoutID.uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}

// MARK: - Removal

/// Deletes imported climbs the way every deletion in Ascend goes: media cancelled, cloud deletion
/// queued before the local row goes, then the derived surfaces told.
@MainActor
protocol HealthImportClimbRemoving: AnyObject {
    /// Deletes the climbs and saves. The caller has already moved the ledger rows to the state the
    /// deletion should leave them in, so one save commits both.
    func remove(_ climbs: [Workout], modelContext: ModelContext, fallbackUserID: String?) async throws
}

@MainActor
final class LiveHealthImportClimbRemover: HealthImportClimbRemoving {
    func remove(_ climbs: [Workout], modelContext: ModelContext, fallbackUserID: String?) async throws {
        guard !climbs.isEmpty else { return }

        for climb in climbs {
            await MediaUploadManager.shared.cancelUploads(for: climb.id, modelContext: modelContext)
        }

        // An imported climb only has photos once the climber added them from the quick edit. They
        // are cleaned up best effort: the climb is already the climber's to remove, and a photo
        // that cannot be deleted right now must not keep it on the screen.
        let photos = climbs.flatMap(\.photos)
        if !photos.isEmpty {
            try? await PhotoService().deletePhotos(photos)
        }

        let didQueueRemoteDeletion = try WorkoutSyncCoordinator.shared.enqueuePendingDeletions(
            for: climbs,
            fallbackUserId: fallbackUserID,
            modelContext: modelContext
        )
        let remoteSyncUserID = climbs.first?.ownerUserId ?? fallbackUserID
        let snapshots = climbs.map(LeaderboardWorkoutSnapshot.init(workout:))

        for climb in climbs {
            modelContext.delete(climb)
        }
        try modelContext.save()
        try WorkoutMutationHandler.shared.workoutsDidChange(
            modelContext: modelContext,
            mutation: .deleted(snapshots)
        )

        if didQueueRemoteDeletion, let remoteSyncUserID {
            Task { @MainActor in
                await WorkoutSyncCoordinator.shared.processPendingWorkouts(
                    modelContext: modelContext,
                    currentUserId: remoteSyncUserID
                )
            }
        }
    }
}
