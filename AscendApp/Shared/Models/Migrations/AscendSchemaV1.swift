//
//  AscendSchemaV1.swift
//  AscendApp
//

import Foundation
import SwiftData

/// The store shape Ascend shipped before `Workout.source` became a raw-value column.
///
/// It exists only so the migration can *read* what is already on disk. Nothing outside
/// `AscendMigrationPlan` should touch these types, and they must never be edited to track the
/// live models - the whole point is that they stay frozen at the shape older installs wrote.
///
/// Only the three entities that participate in `Workout`'s relationship graph need frozen copies;
/// every other model is byte-identical across the two versions and is listed by its live type.
enum AscendSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

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

extension AscendSchemaV1 {
    /// `Workout` as it was persisted before ASCEND-IOS-1K, with `source` still stored as a Codable
    /// enum. That storage is exactly why it could not appear in a `#Predicate`, and exactly why a
    /// plain `@Attribute(originalName:)` rename onto a `String` column cannot be trusted to carry
    /// the value across.
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
        var source: WorkoutSource = WorkoutSource.manual
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
            source: WorkoutSource = .manual,
            healthKitUUID: String? = nil
        ) {
            self.id = id
            self.name = name
            self.date = date
            self.duration = duration
            self.steps = steps
            self.floors = floors
            self.createdAt = date
            self.lastModifiedAt = date
            self.source = source
            self.integrityLevel = source.isVerified ? .verified : .unverified
            self.healthKitUUID = healthKitUUID
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
