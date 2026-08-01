//
//  AscendMigrationPlan.swift
//  AscendApp
//

import Foundation
import SwiftData

/// Carries every store shape Ascend has ever written forward to the current one.
///
/// "Pre-launch" makes *production* data free, not the dev, staging and TestFlight stores that
/// already exist. Without this plan, moving `Workout.source` to a raw-value column would have
/// been a silent lightweight migration: the old column drops, the new one takes its `.manual`
/// default, and every recorded `.headphoneMotion` session quietly stops being an in-app sensor
/// workout - no enrichment, no Live Climb attempt, while `integrityLevel` still claims verified.
enum AscendMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AscendSchemaV1.self, AscendSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    /// Copies the Codable `source` column into `sourceRawValue`.
    ///
    /// It has to be two-phase. `willMigrate` runs against the old store, where `source` still
    /// exists and `sourceRawValue` does not; `didMigrate` runs against the new one, where the
    /// reverse is true. Neither context can see both columns, so the values travel between them
    /// in memory, keyed by the workout's own `id` - the one identifier that survives the
    /// migration, since `PersistentIdentifier` does not.
    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: AscendSchemaV1.self,
        toVersion: AscendSchemaV2.self,
        willMigrate: { context in
            var sourcesByWorkoutID: [UUID: String] = [:]

            try forEachBatch(of: AscendSchemaV1.Workout.self, in: context) { batch in
                for workout in batch {
                    sourcesByWorkoutID[workout.id] = workout.source.rawValue
                }
            }

            WorkoutSourceMigrationStash.shared.store(sourcesByWorkoutID)
        },
        didMigrate: { context in
            let sourcesByWorkoutID = WorkoutSourceMigrationStash.shared.take()
            guard !sourcesByWorkoutID.isEmpty else { return }

            try forEachBatch(of: Workout.self, in: context) { batch in
                for workout in batch {
                    guard let rawValue = sourcesByWorkoutID[workout.id] else { continue }
                    workout.sourceRawValue = rawValue
                }
                try context.save()
            }
        }
    )

    /// Walks a model type a page at a time.
    ///
    /// A migration is the one moment the whole store legitimately has to be read, but `Workout`
    /// carries its heart-rate series inline - a few hundred sessions is tens of megabytes - so
    /// reading it all into one array is how a one-time cost becomes a launch-time crash.
    private static func forEachBatch<Model: PersistentModel>(
        of model: Model.Type,
        in context: ModelContext,
        batchSize: Int = 50,
        body: ([Model]) throws -> Void
    ) throws {
        var offset = 0

        while true {
            var descriptor = FetchDescriptor<Model>()
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize

            let batch = try context.fetch(descriptor)
            guard !batch.isEmpty else { return }

            try body(batch)

            offset += batch.count
        }
    }
}

/// Hands the pre-migration `source` values from `willMigrate` to `didMigrate`.
///
/// SwiftData hands each phase its own `ModelContext` and nothing else, so this is the only channel
/// between them. It is deliberately write-once/read-once: `take()` empties it, so a second
/// container creation in the same process cannot replay stale values over a store that has
/// already migrated.
final class WorkoutSourceMigrationStash: @unchecked Sendable {
    static let shared = WorkoutSourceMigrationStash()

    private let lock = NSLock()
    private var sourcesByWorkoutID: [UUID: String] = [:]

    func store(_ sourcesByWorkoutID: [UUID: String]) {
        lock.lock()
        defer { lock.unlock() }

        self.sourcesByWorkoutID = sourcesByWorkoutID
    }

    func take() -> [UUID: String] {
        lock.lock()
        defer { lock.unlock() }

        let sourcesByWorkoutID = self.sourcesByWorkoutID
        self.sourcesByWorkoutID = [:]
        return sourcesByWorkoutID
    }
}
