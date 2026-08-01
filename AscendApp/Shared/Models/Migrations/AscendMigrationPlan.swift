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
            applyStashedSourcesReportingFailure(to: context)
        }
    )

    /// Where the failure this migration is not allowed to be fatal about gets reported.
    ///
    /// Settable for the same reason `WorkoutSourceMigrationStash.shared` is: `MigrationStage`
    /// builds its phases statically, so there is no parameter to thread a recorder through. The
    /// seam exists so a test can assert what these paths *ask for* - the request to mirror
    /// remotely is checkable from inside the process even though its delivery is not, and the
    /// unverifiable half is the one that has quietly gone missing before.
    nonisolated(unsafe) static var diagnostics: any AppDiagnosticsRecording = AppDiagnosticsRecorder.shared

    /// Runs the write pass and swallows whatever it throws.
    ///
    /// The schema step has already committed by the time `didMigrate` runs, so throwing would
    /// cost a launch and buy nothing: the stash still holds every value and
    /// `recoverInterruptedMigrationIfNeeded` re-runs the same write next launch, bounded by the
    /// same attempt counter. Refusing to open the app is the loudest failure available and also
    /// the worst.
    static func applyStashedSourcesReportingFailure(
        to context: ModelContext,
        stash: WorkoutSourceMigrationStash = .shared
    ) {
        do {
            try applyStashedSources(to: context, stash: stash)
        } catch let failure as WorkoutSourceMigrationSweepFailure {
            report(
                "workout_source_migration_write_failed",
                error: failure.underlying,
                sweep: failure.sweep
            )
        } catch {
            report("workout_source_migration_write_failed", error: error, sweep: SweepReport())
        }
    }

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
        var unresolvedCount = 0
        var pageCount = 0
        var largestPageSize = 0
        var repairedCount = 0
        var failedAttemptCount = 0
        var abandonedAfterRepeatedFailures = false

        var requestedCount: Int { workoutCount + unresolvedCount }
    }

    /// Reads every pre-migration `source` and hands it to the stash.
    ///
    /// This is the one pass that may throw all the way out of `ModelContainer` construction, and
    /// only for a bounded number of launches. Throwing here leaves the store on V1 with the old
    /// `source` column intact, which is the *only* thing that preserves a retry - once the schema
    /// advances the column is gone. So a failure is worth one or two dead launches, and then it is
    /// not: at `WorkoutSourceMigrationStash.maximumAttempts` this stops throwing, keeps whatever
    /// resolved, and reports the shortfall. A user with some sources unrepaired plus a signal we
    /// can see beats a user whose app never opens again.
    @discardableResult
    static func stashLegacySources(
        from context: ModelContext,
        stash: WorkoutSourceMigrationStash = .shared
    ) throws -> SweepReport {
        var sourcesByWorkoutID: [UUID: String] = [:]
        var sweep = SweepReport()

        do {
            try forEachPage(of: AscendSchemaV1.Workout.self, in: context, report: &sweep) { page in
                for workout in page {
                    sourcesByWorkoutID[workout.id] = workout.source.rawValue
                }
            }

            guard sweep.unresolvedCount == 0 else {
                throw WorkoutSourceMigrationError.pageDidNotFullyResolve(
                    requested: sweep.requestedCount,
                    resolved: sweep.workoutCount
                )
            }

            try stash.store(sourcesByWorkoutID)

            return sweep
        } catch {
            let failedAttemptCount = countFailedAttempt(on: stash)
            sweep.failedAttemptCount = failedAttemptCount
            report("workout_source_migration_read_failed", error: error, sweep: sweep)

            guard failedAttemptCount >= WorkoutSourceMigrationStash.maximumAttempts else {
                throw error
            }

            try? stash.store(sourcesByWorkoutID)
            sweep.abandonedAfterRepeatedFailures = true

            return sweep
        }
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
    /// instead of a repair that silently walks the whole store on every launch forever. Every exit
    /// converges on a terminal state - empty stash or exhausted counter - because this runs inside
    /// `AscendApp.init()` on the main thread, and an unbounded walk there is ASCEND-IOS-1K again.
    @discardableResult
    static func applyStashedSources(
        to context: ModelContext,
        stash: WorkoutSourceMigrationStash = .shared
    ) throws -> SweepReport {
        let stashed = stash.load()

        // A stash that exists but will not decode is not the same thing as a finished migration,
        // and treating them alike is how every source value goes to `.manual` with nothing
        // recorded anywhere - the silent default this whole stage exists to prevent. It stays
        // non-fatal, but it says so, and it converges so the report happens once.
        if stashed.isUnreadable {
            report(
                "workout_source_migration_stash_unreadable",
                error: WorkoutSourceMigrationError.stashCouldNotBeDecoded,
                sweep: SweepReport()
            )
            stash.clearBestEffort()
            return SweepReport()
        }

        guard !stashed.sourcesByWorkoutID.isEmpty, !stashed.isExhausted else { return SweepReport() }

        var sweep = SweepReport()
        var repairedCount = 0

        do {
            try forEachPage(of: Workout.self, in: context, report: &sweep) { page in
                for workout in page {
                    guard let rawValue = stashed.sourcesByWorkoutID[workout.id],
                          workout.sourceRawValue != rawValue else { continue }

                    workout.sourceRawValue = rawValue
                    repairedCount += 1
                }

                try context.save()
            }
            sweep.repairedCount = repairedCount

            guard sweep.unresolvedCount == 0 else {
                throw WorkoutSourceMigrationError.pageDidNotFullyResolve(
                    requested: sweep.requestedCount,
                    resolved: sweep.workoutCount
                )
            }

            stash.clearBestEffort()

            return sweep
        } catch {
            // Carry the partial sweep out with the error. A failure on the second attempt that
            // had already repaired 800 of 900 rows is a different incident from one that never
            // started, and reporting zeroes for both hides which one happened.
            sweep.repairedCount = repairedCount
            sweep.failedAttemptCount = countFailedAttempt(on: stash)

            guard sweep.failedAttemptCount >= WorkoutSourceMigrationStash.maximumAttempts else {
                throw WorkoutSourceMigrationSweepFailure(sweep: sweep, underlying: error)
            }

            sweep.abandonedAfterRepeatedFailures = true
            report("workout_source_migration_abandoned", error: error, sweep: sweep)

            return sweep
        }
    }

    /// Records a failed sweep and reports how many have now failed.
    ///
    /// A counter that cannot be persisted counts as exhausted rather than as an unrecorded
    /// increment: otherwise the on-disk count never advances, `isExhausted` never becomes true,
    /// and the store gets walked again on every launch for the life of the install. The stash is
    /// emptied in that case so the next launch's early return fires.
    private static func countFailedAttempt(on stash: WorkoutSourceMigrationStash) -> Int {
        guard let failedAttemptCount = try? stash.recordFailedAttempt() else {
            stash.clearBestEffort()
            return WorkoutSourceMigrationStash.maximumAttempts
        }

        return failedAttemptCount
    }

    /// Puts the counts somewhere a release build can actually surface them.
    ///
    /// `debugLog` is compiled out of anything but DEBUG, so a shortfall logged only there is
    /// invisible on exactly the builds where it matters. Choosing observable-over-fatal is only
    /// worth anything if the observation reaches us.
    private static func report(_ name: String, error: any Error, sweep: SweepReport) {
        diagnostics.record(
            name,
            level: .error,
            details: [
                "error_type": String(describing: type(of: error)),
                "error_description": String(describing: error),
                "resolved_count": String(sweep.workoutCount),
                "unresolved_count": String(sweep.unresolvedCount),
                "repaired_count": String(sweep.repairedCount),
                "failed_attempt_count": String(sweep.failedAttemptCount)
            ],
            mirrorToCrashlytics: true
        )
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
    /// An identifier that does not resolve is counted, never dropped. This same silent-default
    /// failure has now been built three times inside the fix for it - the original whole-store
    /// scan, then offset pages that could skip rows, then a `compactMap` that swallowed unresolved
    /// ones - and each time it was invisible because a lost workout reads back exactly like a
    /// healthy one. `workoutCount` is what actually resolved rather than what was requested, so a
    /// gap cannot be mistaken for a complete sweep.
    ///
    /// The walk keeps going rather than stopping at the first gap, so the rows after it are still
    /// carried across. What to do about a non-zero `unresolvedCount` is the caller's decision,
    /// because the two passes answer it differently.
    ///
    /// `report` is `inout` rather than returned so a caller that fails partway still has the
    /// counts for the pages that did land.
    private static func forEachPage<Model: PersistentModel>(
        of model: Model.Type,
        in context: ModelContext,
        report: inout SweepReport,
        body: ([Model]) throws -> Void
    ) throws {
        let identifiers = try context.fetchIdentifiers(FetchDescriptor<Model>())

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

            try body(page)

            report.workoutCount += page.count
            report.unresolvedCount += requested.count - page.count
            report.pageCount += 1
            report.largestPageSize = max(report.largestPageSize, page.count)
            pageStart = pageEnd
        }
    }
}

/// A sweep failure that still knows how far it got.
struct WorkoutSourceMigrationSweepFailure: Error {
    let sweep: AscendMigrationPlan.SweepReport
    let underlying: any Error
}

enum WorkoutSourceMigrationError: Error, CustomStringConvertible {
    case pageDidNotFullyResolve(requested: Int, resolved: Int)
    case stashCouldNotBeDecoded

    var description: String {
        switch self {
        case let .pageDidNotFullyResolve(requested, resolved):
            return """
            workout source migration resolved \(resolved) of \(requested) workouts in a page; \
            refusing to continue with the rest defaulted to manual
            """
        case .stashCouldNotBeDecoded:
            return """
            workout source migration stash exists but will not decode; every workout it held \
            keeps the manual default
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

        /// The file is there and holds values, but nothing can be read out of it. Distinct from
        /// absent, which means the migration finished.
        var isUnreadable = false

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

    /// A stash that cannot be read is treated as absent rather than as an error.
    ///
    /// The alternative is a corrupt file that throws on every launch and never converges, which
    /// costs a diagnostic each time and repairs nothing. Reading it as empty makes the caller's
    /// early return fire; the file stays on disk for inspection.
    func load() -> Contents {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return Contents()
        }

        guard let stored = try? read() else { return Contents(isUnreadable: true) }

        return Contents(
            sourcesByWorkoutID: stored.sourcesByWorkoutID.reduce(into: [UUID: String]()) { partialResult, entry in
                guard let id = UUID(uuidString: entry.key) else { return }
                partialResult[id] = entry.value
            },
            failedAttemptCount: stored.failedAttemptCount
        )
    }

    /// Records that a sweep failed, and reports how many have now failed.
    ///
    /// Creates the file if it is not there yet: the read pass can fail before anything has been
    /// stashed, and a counter that only exists once there is something to count would leave that
    /// pass unbounded.
    @discardableResult
    func recordFailedAttempt() throws -> Int {
        lock.lock()
        defer { lock.unlock() }

        var stored = (try? read()) ?? StoredContents(sourcesByWorkoutID: [:], failedAttemptCount: 0)
        stored.failedAttemptCount += 1
        try write(stored)

        return stored.failedAttemptCount
    }

    /// Drives the stash to its terminal empty state, however it can.
    ///
    /// Unlinking is preferred, but a file that will not unlink must not leave values behind that
    /// make the next launch walk the whole store again, so an empty payload is the fallback.
    func clearBestEffort() {
        if (try? clear()) != nil { return }

        try? store([:])
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
