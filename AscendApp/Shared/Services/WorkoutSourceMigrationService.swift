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

    static func runIfNeeded(modelContext: ModelContext) throws {
        guard !UserDefaults.standard.bool(forKey: backfillVersionKey) else { return }

        let descriptor = FetchDescriptor<Workout>()
        let workouts = try modelContext.fetch(descriptor)

        for workout in workouts {
            try ensureLegacySourceLinksExist(for: workout, modelContext: modelContext)
        }

        try modelContext.save()
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
