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
/// It names the live model types except for `ActiveHeadphoneWorkoutDraft`, whose pre-V5 shape is
/// the frozen `AscendSchemaV4.ActiveHeadphoneWorkoutDraft`; `AscendSchemaV4` added a model and
/// changed none, so nothing else here needs a copy of its own.
/// `AscendLocalStore.currentSchema` is the one declaration of which version is live.
enum AscendSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            AscendSchemaV4.ActiveHeadphoneWorkoutDraft.self,
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
