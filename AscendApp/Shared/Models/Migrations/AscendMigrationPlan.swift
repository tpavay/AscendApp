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

    /// How many workouts a single page reads, and - in the write pass - commits.
    ///
    /// A `Workout` carries its heart-rate series inline, so a store of a few hundred sessions is
    /// tens of megabytes on disk, and the recovery pass runs inside `AscendApp.init()` on the main
    /// thread, which is the exact shape ASCEND-IOS-1K was. This bounds how many rows each
    /// iteration constructs and how many pending changes a transaction carries. It does not bound
    /// how many models the `ModelContext` keeps registered afterwards - SwiftData decides that,
    /// and nothing here evicts them.
    static let readPageSize = 100

    /// What a sweep did, so a caller can log it and a test can assert the read stayed bounded.
    struct SweepReport: Equatable {
        var workoutCount = 0
        var pageCount = 0
        var largestPageSize = 0
        var repairedCount = 0
        var failedAttemptCount = 0
        var abandonedAfterRepeatedFailures = false
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

    /// Writes the stashed values onto the migrated store, a page at a time.
    ///
    /// Each page commits before the next one is read, so the pending-change set stays bounded
    /// instead of growing to the repaired-row count. That is safe only because the stash is the
    /// unit of completion, not the transaction: it survives every partial run and is cleared
    /// exactly once, after the last page. A run interrupted with some pages committed therefore
    /// re-enters on the next launch and finishes the rest, and re-applying a page that already
    /// landed costs nothing because a workout whose column already matches is skipped.
    ///
    /// Clearing the stash is best-effort and deliberately last. The pages are the transaction
    /// boundaries, so a scratch file that will not unlink must not turn a launch whose sources
    /// were written correctly into `localDataUnavailable`; a stash that outlives its write just
    /// makes the next launch re-run a sweep that changes nothing.
    ///
    /// Repeated failure stops rather than looping. Each failed sweep increments a counter in the
    /// stash; once it reaches `WorkoutSourceMigrationStash.maximumAttempts` the sweep is abandoned
    /// and reported once, so a permanently unresolvable store surfaces as one loud diagnostic
    /// instead of a repair that silently retries on every launch forever. The stash file is left
    /// on disk for inspection rather than deleted.
    @discardableResult
    static func applyStashedSources(
        to context: ModelContext,
        stash: WorkoutSourceMigrationStash = .shared
    ) throws -> SweepReport {
        let stashed = try stash.load()
        guard !stashed.sourcesByWorkoutID.isEmpty, !stashed.isExhausted else { return SweepReport() }

        do {
            var repairedCount = 0
            var report = try forEachPage(of: Workout.self, in: context) { page in
                for workout in page {
                    guard let rawValue = stashed.sourcesByWorkoutID[workout.id],
                          workout.sourceRawValue != rawValue else { continue }

                    workout.sourceRawValue = rawValue
                    repairedCount += 1
                }

                try context.save()
            }
            report.repairedCount = repairedCount

            try? stash.clear()

            return report
        } catch {
            let failedAttemptCount = (try? stash.recordFailedAttempt())
                ?? (stashed.failedAttemptCount + 1)

            guard failedAttemptCount >= WorkoutSourceMigrationStash.maximumAttempts else {
                throw error
            }

            var report = SweepReport()
            report.failedAttemptCount = failedAttemptCount
            report.abandonedAfterRepeatedFailures = true
            return report
        }
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

    /// Walks a model type `readPageSize` rows at a time.
    ///
    /// Pages are cut over `fetchIdentifiers` rather than `fetchOffset`. Identifiers are one row
    /// each and partition by construction; `fetchOffset` would need a genuinely total sort order
    /// to do the same, and `Workout` has none - `date` ties, and `id` is a `UUID`, which is not
    /// `Comparable`. Under a non-total order two OFFSET pages can overlap or leave a gap, and a
    /// workout in the gap silently keeps the `.manual` default.
    ///
    /// A page that does not resolve every identifier it asked for throws instead of carrying on
    /// with what it got. This same silent-default failure has now been built three times inside
    /// the fix for it - the original whole-store scan, then offset pages that could skip rows,
    /// then a `compactMap` that dropped unresolved ones - and each time it was invisible because
    /// a lost workout reads back exactly like a healthy one. The counts are in the error, and
    /// `workoutCount` is what actually resolved rather than what was requested, so a gap cannot be
    /// mistaken for a complete sweep.
    private static func forEachPage<Model: PersistentModel>(
        of model: Model.Type,
        in context: ModelContext,
        body: ([Model]) throws -> Void
    ) throws -> SweepReport {
        let identifiers = try context.fetchIdentifiers(FetchDescriptor<Model>())
        var report = SweepReport()

        var pageStart = identifiers.startIndex
        while pageStart < identifiers.endIndex {
            let pageEnd = identifiers.index(
                pageStart,
                offsetBy: readPageSize,
                limitedBy: identifiers.endIndex
            ) ?? identifiers.endIndex

            let requested = identifiers[pageStart..<pageEnd]
            var page: [Model] = []
            page.reserveCapacity(requested.count)

            for identifier in requested {
                guard let resolved = context.model(for: identifier) as? Model else { continue }
                page.append(resolved)
            }

            guard page.count == requested.count else {
                throw WorkoutSourceMigrationError.pageDidNotFullyResolve(
                    requested: requested.count,
                    resolved: page.count
                )
            }

            try body(page)

            report.workoutCount += page.count
            report.pageCount += 1
            report.largestPageSize = max(report.largestPageSize, page.count)
            pageStart = pageEnd
        }

        return report
    }
}

enum WorkoutSourceMigrationError: Error, CustomStringConvertible {
    case pageDidNotFullyResolve(requested: Int, resolved: Int)

    var description: String {
        switch self {
        case let .pageDidNotFullyResolve(requested, resolved):
            return """
            workout source migration resolved \(resolved) of \(requested) workouts in a page; \
            refusing to continue with the rest defaulted to manual
            """
        }
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

    /// How many times the write may fail before the repair is given up on.
    ///
    /// Retrying is right for a transient failure and wrong for a permanent one: an identifier that
    /// will never resolve would otherwise re-throw on every launch for the life of the install.
    static let maximumAttempts = 3

    struct Contents: Equatable {
        var sourcesByWorkoutID: [UUID: String] = [:]
        var failedAttemptCount = 0

        var isExhausted: Bool {
            failedAttemptCount >= WorkoutSourceMigrationStash.maximumAttempts
        }
    }

    private struct StoredContents: Codable {
        var sourcesByWorkoutID: [String: String]
        var failedAttemptCount: Int
    }

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

        try write(
            StoredContents(
                sourcesByWorkoutID: sourcesByWorkoutID.reduce(into: [String: String]()) { partialResult, entry in
                    partialResult[entry.key.uuidString] = entry.value
                },
                failedAttemptCount: 0
            )
        )
    }

    func load() throws -> Contents {
        lock.lock()
        defer { lock.unlock() }

        guard let stored = try read() else { return Contents() }

        return Contents(
            sourcesByWorkoutID: stored.sourcesByWorkoutID.reduce(into: [UUID: String]()) { partialResult, entry in
                guard let id = UUID(uuidString: entry.key) else { return }
                partialResult[id] = entry.value
            },
            failedAttemptCount: stored.failedAttemptCount
        )
    }

    /// Records that a sweep failed, and reports how many have now failed.
    @discardableResult
    func recordFailedAttempt() throws -> Int {
        lock.lock()
        defer { lock.unlock() }

        guard var stored = try read() else { return 0 }

        stored.failedAttemptCount += 1
        try write(stored)

        return stored.failedAttemptCount
    }

    private func read() throws -> StoredContents? {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return nil
        }

        return try JSONDecoder().decode(StoredContents.self, from: Data(contentsOf: fileURL))
    }

    private func write(_ contents: StoredContents) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(contents).write(to: fileURL, options: .atomic)
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
