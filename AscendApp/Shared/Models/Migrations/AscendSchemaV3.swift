//
//  AscendSchemaV3.swift
//  AscendApp
//

import Foundation
import SwiftData

/// The store shape Ascend writes today: user-authored routines and folders carry cloud-backup
/// state, and `PendingRoutineDeletion` records the tombstones a local delete leaves behind.
///
/// Every column this adds is either optional or has a blanket default that is honest for the rows
/// that already exist - `remoteSyncStatusRawValue` defaults to `pendingUpsert` because every
/// routine written before this build genuinely does still owe its first upload, which is the whole
/// point of the change. `PendingRoutineDeletion` is a brand-new model with no rows to default. So
/// the stage is lightweight; nothing has to be computed per record.
///
/// Unlike `AscendSchemaV1` and `AscendSchemaV2` this is not frozen - it is the live model set, and
/// it moves with the models. The next persisted-shape change becomes `AscendSchemaV4` and a new
/// stage.
enum AscendSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
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
