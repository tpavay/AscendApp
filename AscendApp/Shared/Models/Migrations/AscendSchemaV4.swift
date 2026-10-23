//
//  AscendSchemaV4.swift
//  AscendApp
//

import Foundation
import SwiftData

/// The store shape a build before `AscendSchemaV5` wrote: workouts that are not yet in the cloud
/// carry a persisted retry schedule in `WorkoutSyncOutboxEntry`.
///
/// The stage is lightweight because this adds a model and changes none. `WorkoutSyncOutboxEntry` is
/// brand new, so it has no existing rows to default, and nothing has to be computed per record. The
/// schedule was deliberately kept off `Workout` for exactly this reason: adding columns there would
/// have changed a shape two shipped versions describe, forcing frozen copies of `Workout`,
/// `WorkoutSourceLink` and `WorkoutParticipation` and turning an additive change into a migration
/// that could strand real devices.
///
/// Frozen. `ActiveHeadphoneWorkoutDraft` carries its own copy below because `AscendSchemaV5`
/// added `checkpointDiagnosticsData` to it, and a version that named the live type would describe
/// a shape it never shipped. V1, V2 and V3 name this same frozen copy: the draft did not change
/// between them. Every other model is byte-identical between V4 and V5 and is listed by its live
/// type.
enum AscendSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            WorkoutSyncOutboxEntry.self,
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

extension AscendSchemaV4 {
    /// `ActiveHeadphoneWorkoutDraft` as every version before V5 shipped it: the shape V1 through V4
    /// all described, before `checkpointDiagnosticsData` was added. Frozen here once and named by
    /// all four, because a version that listed the live type would silently start describing the
    /// newer shape - the aliasing failure `AscendSchemaV1` warns about - and a real V1 store would
    /// no longer match any version in the plan.
    @Model
    final class ActiveHeadphoneWorkoutDraft {
        var id: UUID = UUID()
        var sessionID: String = ""
        var kindRawValue: String = ActiveHeadphoneWorkoutDraftKind.justClimb.rawValue
        var statusRawValue: String = ActiveHeadphoneWorkoutDraftStatus.recording.rawValue
        var createdAt: Date = Date()
        var startedAt: Date = Date()
        var lastCheckpointAt: Date = Date()
        var title: String = ""
        var subtitle: String = ""
        var workoutName: String = ""
        var steps: Int = 0
        var durationSeconds: TimeInterval = 0
        var sampleCount: Int = 0
        var targetStepCount: Int?
        var targetDurationSeconds: TimeInterval?
        var climbId: String?
        var justClimbGoalKindRawValue: String?
        var justClimbDurationMinutes: Int?
        var justClimbStepCount: Int?
        var routineId: UUID?
        var routineSourceRawValue: String?
        var routineTemplateId: String?
        var routineDifficulty: Int?
        var routineIntervalCount: Int?
        var routineSkippedIntervalCount: Int?
        var routineWeightConfigurationData: Data?
        var splitCurveData: Data?
        var trackingIntegrityData: Data?
        var stepCorrectionsData: Data?
        var heartRateData: Data?
        var heartRateSampleCount: Int?

        init(id: UUID = UUID(), sessionID: String = "") {
            self.id = id
            self.sessionID = sessionID
        }
    }
}
