//
//  WorkoutSourceMigrationService.swift
//  AscendApp
//
//  Created by Codex on 3/11/26.
//

import Foundation
import SwiftData

enum WorkoutSourceMigrationService {
    private static let backfillVersionKey = "workoutSourceLinkMigration.v1"

    /// Small enough that one batch cannot own the main thread for a perceptible time, large
    /// enough that a store with years of history does not spend the sweep in per-batch overhead.
    static let batchSize = 50

    static var hasCompletedBackfill: Bool {
        UserDefaults.standard.bool(forKey: backfillVersionKey)
    }

    /// Backfills the `WorkoutSourceLink` rows that legacy Apple Health workouts predate.
    ///
    /// Runs a batch at a time and yields between batches. The previous version fetched and
    /// mutated the whole store in one main-thread step - the same unbounded shape that hung Home
    /// for 182 seconds (ASCEND-IOS-1K); a one-time cost is still a hang the first time it is
    /// paid. Cancellation leaves the store consistent: each batch is saved before the next one
    /// starts, and the completion flag is only set once the sweep finishes, so an interrupted run
    /// resumes where it left off.
    ///
    /// Only workouts carrying a `healthKitUUID` can need a link, so the sweep is bounded by the
    /// Apple Health history rather than by the whole store.
    static func runIfNeeded(modelContext: ModelContext) async throws {
        guard !hasCompletedBackfill else { return }

        var offset = 0

        while true {
            try Task.checkCancellation()

            var descriptor = FetchDescriptor<Workout>(
                predicate: #Predicate<Workout> { workout in
                    workout.healthKitUUID != nil
                },
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize

            let batch = try modelContext.fetch(descriptor)
            guard !batch.isEmpty else { break }

            for workout in batch {
                try ensureLegacySourceLinksExist(for: workout, modelContext: modelContext)
            }
            try modelContext.save()

            offset += batch.count
            await Task.yield()
        }

        UserDefaults.standard.set(true, forKey: backfillVersionKey)
    }

    static func ensureLegacySourceLinksExist(
        for workout: Workout,
        modelContext: ModelContext
    ) throws {
        if let healthKitUUID = workout.healthKitUUID,
           workout.sourceLink(for: .appleHealth) == nil {
            let link = WorkoutSourceLink(
                provider: .appleHealth,
                externalRecordID: healthKitUUID,
                providerWindowStart: workout.date,
                providerWindowEnd: workout.date.addingTimeInterval(workout.duration),
                timingPrecision: .exact,
                sourceName: workout.deviceModel ?? workout.sourceDisplayName,
                sourceBundleIdentifier: nil,
                deviceModel: workout.deviceModel,
                metadataJSON: workout.sourceMetadata,
                workout: workout
            )
            modelContext.insert(link)
        }
    }
}
