//
//  AscendSchemaV2.swift
//  AscendApp
//

import Foundation
import SwiftData

/// The store shape Ascend writes today: `Workout.source` persisted as `sourceRawValue`, so it can
/// be filtered in a `#Predicate` instead of by scanning the store (ASCEND-IOS-1K).
///
/// Frozen. `Routine` and `RoutineFolder` carry their own copies here for the same reason
/// `AscendSchemaV1` does: they gained cloud-backup columns in V3, and naming them by their live
/// type would make this version describe a shape it never shipped. Every other model is
/// byte-identical between V2 and V3 and is listed by its live type.
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

extension AscendSchemaV2 {
    /// `Routine` as V2 shipped it - the same shape as V1, since the workout
    /// source migration did not touch routines.
    @Model
    final class Routine {
        var id: UUID = UUID()
        var name: String = ""
        var routineDescription: String = ""
        var sourceRawValue: String = RoutineSource.userCreated.rawValue
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var folderId: UUID?
        var isArchived: Bool = false
        var intervalsData: Data?
        var defaultWeightConfigurationData: Data?
        var templateId: String?
        var templateVersion: Int?
        var difficulty: Int?
        var estimatedCalories: Int?
        var isFeaturedTemplate: Bool = false
        var templateDisplayOrder: Int = 0
        var templateFeaturedOrder: Int?
        var browseSectionRawValuesData: Data?
        var completionCount: Int = 0
        var lastCompletedAt: Date?
        var order: Int = 0

        init(id: UUID = UUID(), name: String = "") {
            self.id = id
            self.name = name
        }
    }

    /// `RoutineFolder` as V2 shipped it.
    @Model
    final class RoutineFolder {
        var id: UUID = UUID()
        var name: String = ""
        var colorHex: String?
        var order: Int = 0
        var createdAt: Date = Date()

        init(id: UUID = UUID(), name: String = "") {
            self.id = id
            self.name = name
        }
    }
}
