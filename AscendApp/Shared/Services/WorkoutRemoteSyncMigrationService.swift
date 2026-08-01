import Foundation
import SwiftData

enum WorkoutRemoteSyncMigrationService {
    private static let migrationVersion = 1

    static func runIfNeeded(
        modelContext: ModelContext,
        currentUserId: String,
        userDefaults: UserDefaults = .standard,
        featureFlags: RemoteFeatureFlagStore = .shared
    ) throws {
        let versionKey = migrationVersionKey(for: currentUserId)
        guard userDefaults.bool(forKey: versionKey) == false else { return }

        // Killed before the version key is stamped, so the backfill is deferred rather than
        // skipped: it runs on the next bootstrap after the flag returns.
        guard RemoteFeatureGate.allows(
            .localDataMigrations,
            path: "WorkoutRemoteSyncMigrationService.runIfNeeded",
            store: featureFlags
        ) else {
            return
        }

        let workouts = try modelContext.fetch(FetchDescriptor<Workout>())
        var didChangeAnyWorkout = false

        for workout in workouts {
            didChangeAnyWorkout = repairLocalSyncMetadata(
                for: workout,
                currentUserId: currentUserId
            ) || didChangeAnyWorkout
        }

        if didChangeAnyWorkout {
            try modelContext.save()
        }

        userDefaults.set(true, forKey: versionKey)
    }

    static func repairLocalSyncMetadata(
        for workout: Workout,
        currentUserId: String
    ) -> Bool {
        guard workout.ownerUserId == nil else { return false }

        workout.markPendingRemoteUpsert(
            ownerUserId: currentUserId,
            modifiedAt: max(workout.createdAt, workout.date)
        )
        return true
    }

    static func migrationVersionKey(for userId: String) -> String {
        "workoutRemoteSyncMigration.v\(migrationVersion).\(userId)"
    }
}
