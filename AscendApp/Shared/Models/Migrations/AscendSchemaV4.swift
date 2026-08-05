//
//  AscendSchemaV4.swift
//  AscendApp
//

import Foundation
import SwiftData

/// The store shape Ascend writes today: workouts that are not yet in the cloud carry a persisted
/// retry schedule in `WorkoutSyncOutboxEntry`.
///
/// The stage is lightweight because this adds a model and changes none. `WorkoutSyncOutboxEntry` is
/// brand new, so it has no existing rows to default, and nothing has to be computed per record. The
/// schedule was deliberately kept off `Workout` for exactly this reason: adding columns there would
/// have changed a shape two shipped versions describe, forcing frozen copies of `Workout`,
/// `WorkoutSourceLink` and `WorkoutParticipation` and turning an additive change into a migration
/// that could strand real devices.
///
/// Unlike V1, V2 and V3 this is not frozen - it is the live model set, and it moves with the
/// models. The next persisted-shape change becomes `AscendSchemaV5` and a new stage.
enum AscendSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            WorkoutSyncOutboxEntry.self,
            ActiveHeadphoneWorkoutDraft.self,
            LeaderboardStats.self,
            Routine.self,
            RoutineFolder.self,
            ClimbAttempt.self,
            PendingMediaUpload.self,
            PendingWorkoutDeletion.self,
            PendingRoutineDeletion.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self
        ]
    }
}
