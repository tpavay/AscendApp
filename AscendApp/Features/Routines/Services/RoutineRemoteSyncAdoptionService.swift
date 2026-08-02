import Foundation
import SwiftData

/// Claims routines and folders that predate the cloud backup for the signed-in
/// climber, so their first upload actually happens.
///
/// Everything the coordinator uploads is keyed on `ownerUserId`, and a routine
/// built before this build shipped - or before the climber signed in - has
/// none. Without this pass those routines sit at `pendingUpsert` forever and
/// are never backed up, which is the original bug wearing a new hat.
///
/// The one-shot key is per user and stamped only after the sweep finishes, so a
/// killed or interrupted run defers the work rather than marking it done.
/// Templates are skipped: they are server-owned content, not the climber's.
enum RoutineRemoteSyncAdoptionService {
    private static let adoptionVersion = 1

    static func runIfNeeded(
        modelContext: ModelContext,
        currentUserId: String,
        userDefaults: UserDefaults = .standard,
        featureFlags: RemoteFeatureFlagStore = .shared
    ) throws {
        let versionKey = adoptionVersionKey(for: currentUserId)
        guard userDefaults.bool(forKey: versionKey) == false else { return }

        // Killed before the version key is stamped, so the sweep is deferred
        // rather than skipped: it runs on the next bootstrap after the flag
        // returns.
        guard RemoteFeatureGate.allows(
            .localDataMigrations,
            path: "RoutineRemoteSyncAdoptionService.runIfNeeded",
            store: featureFlags
        ) else {
            return
        }

        var didChange = false

        for routine in try modelContext.fetch(FetchDescriptor<Routine>()) {
            didChange = adopt(routine, currentUserId: currentUserId) || didChange
        }

        for folder in try modelContext.fetch(FetchDescriptor<RoutineFolder>()) {
            didChange = adopt(folder, currentUserId: currentUserId) || didChange
        }

        if didChange {
            try modelContext.save()
        }

        userDefaults.set(true, forKey: versionKey)
    }

    @discardableResult
    static func adopt(_ routine: Routine, currentUserId: String) -> Bool {
        guard routine.ownerUserId == nil, routine.isUserAuthored else { return false }

        // The existing `updatedAt` is kept rather than refreshed: it is what the
        // conflict rule compares against, and moving it forward would let a
        // stale local copy outrank a newer backup on a second device.
        routine.markPendingRemoteUpsert(
            ownerUserId: currentUserId,
            modifiedAt: routine.updatedAt
        )
        return true
    }

    @discardableResult
    static func adopt(_ folder: RoutineFolder, currentUserId: String) -> Bool {
        guard folder.ownerUserId == nil else { return false }

        folder.markPendingRemoteUpsert(
            ownerUserId: currentUserId,
            modifiedAt: folder.effectiveUpdatedAt
        )
        return true
    }

    static func adoptionVersionKey(for userId: String) -> String {
        "routineRemoteSyncAdoption.v\(adoptionVersion).\(userId)"
    }
}
