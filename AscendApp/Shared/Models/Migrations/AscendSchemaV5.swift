//
//  AscendSchemaV5.swift
//  AscendApp
//

import Foundation
import SwiftData

/// The store shape a build before `AscendSchemaV6` wrote: `ActiveHeadphoneWorkoutDraft` carries the
/// device diagnostics of its last checkpoint (`checkpointDiagnosticsData`), so the launch that
/// finds a draft can say why the process that wrote it died.
///
/// The stage into it was lightweight because the one added column is optional: a draft written by a
/// build before this one simply has no diagnostics, and the recovery surfaces read that as
/// "unknown" rather than as a reading. Nothing is computed per record.
///
/// Frozen. `Workout`, `WorkoutSourceLink` and `WorkoutParticipation` carry their own copies below
/// because `AscendSchemaV6` gave `Workout` a `leaderboardStatusRawValue` column, and a version that
/// named the live type would describe a column it never shipped. The three travel together because
/// `Workout` owns cascade relationships to the other two. V2, V3 and V4 name these same copies -
/// `Workout` did not change between them - and `AscendSchemaV1` keeps its own, older one. Every
/// other model is byte-identical between V5 and V6 and is listed by its live type.
enum AscendSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            AscendSchemaV5.Workout.self,
            AscendSchemaV5.WorkoutSourceLink.self,
            AscendSchemaV5.WorkoutParticipation.self,
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

extension AscendSchemaV5 {
    /// `Workout` as every version from V2 through V5 shipped it: `source` stored as
    /// `sourceRawValue`, and no `leaderboardStatusRawValue`.
    @Model
    final class Workout {
        var id: UUID = UUID()
        var name: String = ""
        var date: Date = Date()
        var duration: TimeInterval = 0
        var steps: Int = 0
        var floors: Int = 0
        var stepsPerFloor: Int = 16
        var notes: String = ""
        var createdAt: Date = Date()
        var ownerUserId: String?
        var lastModifiedAt: Date = Date()
        var lastRemoteSyncAt: Date?
        var lastRemoteHeartRateSeriesStoragePath: String?
        var lastRemoteHeartRateSeriesReferenceData: Data?
        var heartRateRestoreStatusRawValue: String = WorkoutHeartRateRestoreStatus.notNeeded.rawValue
        var heartRateRestoreErrorCode: String?
        var remoteSyncStatusRawValue: String = WorkoutRemoteSyncStatus.pendingUpsert.rawValue
        var lastRemoteSyncError: String?
        var avgHeartRate: Int?
        var maxHeartRate: Int?
        var caloriesBurned: Int?
        var effortRating: Double?
        var heartRateData: Data?
        var averageMETs: Double?
        var sourceRawValue: String = WorkoutSource.manual.rawValue
        var integrityLevel: DataIntegrityLevel = DataIntegrityLevel.unverified
        var deviceModel: String?
        var sourceMetadata: String?
        var healthKitUUID: String?
        var hevyWorkoutId: String?
        var photos: [Photo] = []
        var highlightedPhotoId: UUID?
        @Relationship(deleteRule: .cascade, inverse: \WorkoutSourceLink.workout)
        var sourceLinks: [WorkoutSourceLink] = []
        @Relationship(deleteRule: .cascade, inverse: \WorkoutParticipation.workout)
        var participations: [WorkoutParticipation] = []
        var weightConfigurationData: Data?
        var percentileScoresData: Data?
        var effortScoreValue: Double?
        var equivalentLevelValue: Int?

        init(
            id: UUID = UUID(),
            name: String = "Workout",
            date: Date = Date(),
            duration: TimeInterval = 0,
            steps: Int = 0,
            floors: Int = 0,
            source: WorkoutSource = .manual
        ) {
            self.id = id
            self.name = name
            self.date = date
            self.duration = duration
            self.steps = steps
            self.floors = floors
            self.createdAt = date
            self.lastModifiedAt = date
            self.sourceRawValue = source.rawValue
            self.integrityLevel = source.isVerified ? .verified : .unverified
        }
    }

    @Model
    final class WorkoutSourceLink {
        var id: UUID = UUID()
        private var providerRawValue: String = WorkoutProvider.appleHealth.rawValue
        var externalRecordID: String = ""
        var providerWindowStart: Date = Date()
        var providerWindowEnd: Date = Date()
        private var timingPrecisionRawValue: String = TimingPrecision.exact.rawValue
        var linkedAt: Date = Date()
        var importedAt: Date = Date()
        var sourceName: String?
        var sourceBundleIdentifier: String?
        var deviceModel: String?
        var metadataJSON: String?
        var workout: Workout?

        init(
            provider: WorkoutProvider,
            externalRecordID: String,
            providerWindowStart: Date,
            providerWindowEnd: Date,
            workout: Workout?
        ) {
            self.id = UUID()
            self.providerRawValue = provider.rawValue
            self.externalRecordID = externalRecordID
            self.providerWindowStart = providerWindowStart
            self.providerWindowEnd = providerWindowEnd
            self.workout = workout
        }
    }

    @Model
    final class WorkoutParticipation {
        var id: UUID = UUID()
        var workoutId: UUID = UUID()
        var userId: String?
        var contextTypeRawValue: String = WorkoutParticipationContextType.routine.rawValue
        var contextId: String = ""
        var contextVersion: Int = 1
        var rulesVersion: Int = 1
        var roleRawValue: String = WorkoutParticipationRole.primary.rawValue
        var leaderboardEligible: Bool = false
        var verificationTierRawValue: String = WorkoutParticipationVerificationTier.unverified.rawValue
        var metricsSnapshotData: Data?
        var createdAt: Date = Date()
        var workout: Workout?

        init(workout: Workout?, contextId: String) {
            self.id = UUID()
            self.workoutId = workout?.id ?? UUID()
            self.contextId = contextId
            self.workout = workout
        }
    }
}
