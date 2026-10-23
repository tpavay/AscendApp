//
//  AscendSchemaV5.swift
//  AscendApp
//

import Foundation
import SwiftData

/// The store shape Ascend writes today: `ActiveHeadphoneWorkoutDraft` carries the device
/// diagnostics of its last checkpoint (`checkpointDiagnosticsData`), so the launch that finds a
/// draft can say why the process that wrote it died.
///
/// The stage is lightweight because the one added column is optional: a draft written by a build
/// before this one simply has no diagnostics, and the recovery surfaces read that as "unknown"
/// rather than as a reading. Nothing is computed per record.
///
/// Unlike V1, V2 and V3 this is not frozen - it is the live model set, and it moves with the
/// models. The next persisted-shape change becomes `AscendSchemaV6` and a new stage.
enum AscendSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

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
