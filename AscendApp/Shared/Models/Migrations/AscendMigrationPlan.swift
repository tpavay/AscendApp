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

    /// How many workouts either pass may hold materialised at once.
    ///
    /// A `Workout` carries its heart-rate series inline, so a store of a few hundred sessions is
    /// tens of megabytes on disk. Reading it a page at a time is what keeps a one-time cost from
    /// becoming a launch-time crash - the recovery pass runs inside `AscendApp.init()`, on the
    /// main thread, which is the exact shape ASCEND-IOS-1K was.
    static let readPageSize = 100

    /// What a sweep did, so a caller can log it and a test can assert the read stayed bounded.
    struct SweepReport: Equatable {
        var workoutCount = 0
        var pageCount = 0
        var largestPageSize = 0
        var repairedCount = 0
    }

    /// Reads every pre-migration `source` and hands it to the stash.
    @discardableResult
    static func stashLegacySources(
        from context: ModelContext,
        stash: WorkoutSourceMigrationStash = .shared
    ) throws -> SweepReport {
        var sourcesByWorkoutID: [UUID: String] = [:]

        let report = try forEachPage(of: AscendSchemaV1.Workout.self, in: context) { page in
            for workout in page {
                sourcesByWorkoutID[workout.id] = workout.source.rawValue
            }
        }

        try stash.store(sourcesByWorkoutID)

        return report
    }

    /// Writes the stashed values onto the migrated store, all-or-nothing.
    ///
    /// The read is paged but the write is not: one `save()` at the end, after every page has been
    /// walked. A per-page save would make a failure partway through permanent, because the schema
    /// version has already advanced by the time this runs, so SwiftData will never re-enter the
    /// stage and the stash held the only remaining copy of the old values. Paging the read and
    /// batching the write are independent - bounding what is *materialised* never required
    /// splitting the transaction.
    ///
    /// Clearing the stash is best-effort and deliberately last. The save is the transaction
    /// boundary, so a scratch file that will not unlink must not turn a launch whose sources were
    /// written correctly into `localDataUnavailable`; a stash that outlives its write just makes
    /// the next launch re-run a sweep that changes nothing.
    ///
    /// Idempotent by construction - a workout whose column already matches is skipped.
    @discardableResult
    static func applyStashedSources(
        to context: ModelContext,
        stash: WorkoutSourceMigrationStash = .shared
    ) throws -> SweepReport {
        let sourcesByWorkoutID = try stash.load()
        guard !sourcesByWorkoutID.isEmpty else { return SweepReport() }

        var repairedCount = 0
        var report = try forEachPage(of: Workout.self, in: context) { page in
            for workout in page {
                guard let rawValue = sourcesByWorkoutID[workout.id],
                      workout.sourceRawValue != rawValue else { continue }

                workout.sourceRawValue = rawValue
                repairedCount += 1
            }
        }
        report.repairedCount = repairedCount

        try context.save()
        try? stash.clear()

        return report
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
    ) throws -> SweepReport {
        try applyStashedSources(to: context, stash: stash)
    }

    /// Walks a model type a page at a time, holding at most `readPageSize` rows materialised.
    ///
    /// Pages are cut over `fetchIdentifiers` rather than `fetchOffset`. Identifiers are one row
    /// each and partition by construction; `fetchOffset` would need a genuinely total sort order
    /// to do the same, and `Workout` has none - `date` ties, and `id` is a `UUID`, which is not
    /// `Comparable`. Under a non-total order two OFFSET pages can overlap or leave a gap, and a
    /// workout in the gap silently keeps the `.manual` default. That is precisely the loss this
    /// stage exists to prevent, so the paging is not allowed to be approximately right.
    private static func forEachPage<Model: PersistentModel>(
        of model: Model.Type,
        in context: ModelContext,
        body: ([Model]) throws -> Void
    ) throws -> SweepReport {
        let identifiers = try context.fetchIdentifiers(FetchDescriptor<Model>())
        var report = SweepReport()
        report.workoutCount = identifiers.count

        var pageStart = identifiers.startIndex
        while pageStart < identifiers.endIndex {
            let pageEnd = identifiers.index(
                pageStart,
                offsetBy: readPageSize,
                limitedBy: identifiers.endIndex
            ) ?? identifiers.endIndex

            let page = identifiers[pageStart..<pageEnd].compactMap { context.model(for: $0) as? Model }
            try body(page)

            report.pageCount += 1
            report.largestPageSize = max(report.largestPageSize, page.count)
            pageStart = pageEnd
        }

        return report
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
    /// Settable because `MigrationStage` builds its phases statically - there is no parameter to
    /// thread an instance through - so this is the only seam a test has for pointing the real
    /// plan at a scratch file instead of the app's.
    nonisolated(unsafe) static var shared = WorkoutSourceMigrationStash()

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
