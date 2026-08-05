//
//  AscendSchemaV3.swift
//  AscendApp
//

import Foundation
import SwiftData

/// The store shape a build before `AscendSchemaV4` wrote: user-authored routines and folders carry
/// cloud-backup state, and `PendingRoutineDeletion` records the tombstones a local delete leaves
/// behind.
///
/// Every column this adds is either optional or has a blanket default that is honest for the rows
/// that already exist - `remoteSyncStatusRawValue` defaults to `pendingUpsert` because every
/// routine written before this build genuinely does still owe its first upload, which is the whole
/// point of the change. `PendingRoutineDeletion` is a brand-new model with no rows to default. So
/// the stage is lightweight; nothing has to be computed per record.
///
/// This still names the live model types rather than frozen copies of its own, because
/// `AscendSchemaV4` added a model and changed none. The day an existing model's shape moves, this
/// version needs frozen copies of what it described, exactly as V1 and V2 carry.
/// `AscendLocalStore.currentSchema` is the one declaration of which version is live.
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
