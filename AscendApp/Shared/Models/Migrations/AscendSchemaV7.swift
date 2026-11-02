//
//  AscendSchemaV7.swift
//  AscendApp
//

import Foundation
import SwiftData

/// The store shape Ascend writes today: V6's fourteen models plus `HealthWorkoutRecord`, the
/// ledger behind Apple Health import - one row per Health stair workout Ascend has met, keyed by
/// its HealthKit UUID, holding whether it is waiting, imported, skipped or covered by a live climb.
///
/// A new model and nothing else, so the stage is lightweight and no existing row is touched or
/// interpreted. No model V6 names changed shape, which is why V6 still names the live types and
/// needs no frozen copies, the way V4 added `WorkoutSyncOutboxEntry`. The ledger starts empty on
/// every device: workouts a climber already imported before the ledger existed cannot exist,
/// because the import that wrote them is this one.
///
/// Unlike V1 through V6 this is not frozen - it is the live model set, and it moves with the
/// models. The next persisted-shape change becomes `AscendSchemaV8` and a new stage.
enum AscendSchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(7, 0, 0) }

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
            BestEffortCacheMetadata.self,
            HealthWorkoutRecord.self
        ]
    }
}
