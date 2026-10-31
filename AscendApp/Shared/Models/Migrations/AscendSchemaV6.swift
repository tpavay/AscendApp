//
//  AscendSchemaV6.swift
//  AscendApp
//

import Foundation
import SwiftData

/// The store shape Ascend writes today: `Workout` carries `leaderboardStatusRawValue`, whether the
/// climb counts toward leaderboards, so a climber can log a climb by hand and the plausibility
/// check can keep an implausible one off the boards without hiding it from their history.
///
/// The stage is lightweight, and every existing row defaults to `eligible`. A store may still hold
/// pre-#443 `manual`, `apple_health` or `hevy` rows that `ClimbPacePolicy` would exclude, and they
/// default to `eligible` too: nothing is computed per record. The server never reads this column: it re-derives
/// eligibility from `source`, `steps` and `durationSeconds`, so what this stores is the device's
/// record of that verdict, for the surfaces that explain it.
///
/// Unlike V1 through V5 this is not frozen - it is the live model set, and it moves with the
/// models. The next persisted-shape change becomes `AscendSchemaV7` and a new stage.
enum AscendSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }

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
