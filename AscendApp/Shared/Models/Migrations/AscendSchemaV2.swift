//
//  AscendSchemaV2.swift
//  AscendApp
//

import Foundation
import SwiftData

/// The store shape Ascend writes today: `Workout.source` persisted as `sourceRawValue`, so it can
/// be filtered in a `#Predicate` instead of by scanning the store (ASCEND-IOS-1K).
///
/// Unlike `AscendSchemaV1` this is not frozen - it is the live model set, and it moves with the
/// models. The next persisted-shape change becomes `AscendSchemaV3` and a new stage.
enum AscendSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

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
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self
        ]
    }
}
