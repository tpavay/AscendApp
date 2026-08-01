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
    /// through `WorkoutSourceMigrationStash`, keyed by the workout's own `id` - the one identifier
    /// that survives the migration, since `PersistentIdentifier` does not.
    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: AscendSchemaV1.self,
        toVersion: AscendSchemaV2.self,
        willMigrate: { context in
            try stashLegacySources(from: context)
        },
        didMigrate: { context in
            try applyStashedSources(to: context)
        }
    )

    /// Reads every pre-migration `source` and hands it to the stash.
    ///
    /// `propertiesToFetch` is what keeps this affordable rather than the number of rows: a
    /// `Workout` carries its heart-rate series inline, so a store of a few hundred sessions is
    /// tens of megabytes, and faulting all of it in to copy one string per row is how a one-time
    /// cost becomes a launch-time crash. Only `id` and `source` are ever read here.
    ///
    /// Fetched in one pass rather than paged. `fetchOffset` pagination over an *unsorted* fetch
    /// has no ordering guarantee, so successive pages are not guaranteed to partition the rows -
    /// a shifted page silently skips workouts, and a skipped workout keeps the `.manual` default.
    /// That is exactly the loss this stage exists to prevent, so the fetch does not page at all.
    static func stashLegacySources(
        from context: ModelContext,
        stash: WorkoutSourceMigrationStash = .shared
    ) throws {
        var descriptor = FetchDescriptor<AscendSchemaV1.Workout>()
        descriptor.propertiesToFetch = [\.id, \.source]

        let sourcesByWorkoutID = try context.fetch(descriptor)
            .reduce(into: [UUID: String]()) { partialResult, workout in
                partialResult[workout.id] = workout.source.rawValue
            }

        try stash.store(sourcesByWorkoutID)
    }

    /// Writes the stashed values onto the migrated store, all-or-nothing.
    ///
    /// One `save()` at the end, and the stash is only cleared once that save has returned. A
    /// per-batch save would make a failure partway through permanent: the schema version has
    /// already advanced by the time this runs, so SwiftData will never re-enter the stage, and
    /// the stash held the only remaining copy of the old values. With this shape an interrupted
    /// run leaves the stash intact, which is the signal `recoverInterruptedMigrationIfNeeded`
    /// reads on the next launch.
    ///
    /// Idempotent by construction - a workout whose column already matches is skipped - so
    /// re-running it after a partially-committed attempt costs nothing and changes nothing.
    @discardableResult
    static func applyStashedSources(
        to context: ModelContext,
        stash: WorkoutSourceMigrationStash = .shared
    ) throws -> Int {
        let sourcesByWorkoutID = try stash.load()
        guard !sourcesByWorkoutID.isEmpty else { return 0 }

        var descriptor = FetchDescriptor<Workout>()
        descriptor.propertiesToFetch = [\.id, \.sourceRawValue]

        var repairedCount = 0
        for workout in try context.fetch(descriptor) {
            guard let rawValue = sourcesByWorkoutID[workout.id],
                  workout.sourceRawValue != rawValue else { continue }

            workout.sourceRawValue = rawValue
            repairedCount += 1
        }

        try context.save()
        try stash.clear()

        return repairedCount
    }

    /// Finishes a migration whose `didMigrate` never completed.
    ///
    /// SwiftData records the store as V2 as soon as the schema step commits, so a `didMigrate`
    /// that throws - or a process killed mid-write - leaves a store that will never re-enter the
    /// stage and whose next launch would otherwise succeed quietly over `.manual` defaults. A
    /// non-empty stash is the marker that the write never landed; this runs the same write again
    /// against the already-migrated store.
    @discardableResult
    static func recoverInterruptedMigrationIfNeeded(
        in context: ModelContext,
        stash: WorkoutSourceMigrationStash = .shared
    ) throws -> Int {
        try applyStashedSources(to: context, stash: stash)
    }
}

/// Carries the pre-migration `source` values from `willMigrate` to `didMigrate`, and outlives the
/// process so an interrupted migration can be finished later.
///
/// SwiftData hands each migration phase its own `ModelContext` and nothing else, so this is the
/// only channel between them. It is on disk rather than in memory because the interesting failure
/// is the one where the app never reaches `didMigrate`: at that point the old column is already
/// gone from the store, and this file is the only surviving copy of what it held.
final class WorkoutSourceMigrationStash: @unchecked Sendable {
    static let shared = WorkoutSourceMigrationStash()

    private let lock = NSLock()
    private let fileURL: URL

    init(fileURL: URL = WorkoutSourceMigrationStash.defaultFileURL) {
        self.fileURL = fileURL
    }

    static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "workout-source-migration-stash.json")
    }

    func store(_ sourcesByWorkoutID: [UUID: String]) throws {
        lock.lock()
        defer { lock.unlock() }

        let encodable = sourcesByWorkoutID.reduce(into: [String: String]()) { partialResult, entry in
            partialResult[entry.key.uuidString] = entry.value
        }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(encodable).write(to: fileURL, options: .atomic)
    }

    func load() throws -> [UUID: String] {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return [:]
        }

        let decoded = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: fileURL))
        return decoded.reduce(into: [UUID: String]()) { partialResult, entry in
            guard let id = UUID(uuidString: entry.key) else { return }
            partialResult[id] = entry.value
        }
    }

    func clear() throws {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return
        }

        try FileManager.default.removeItem(at: fileURL)
    }
}
