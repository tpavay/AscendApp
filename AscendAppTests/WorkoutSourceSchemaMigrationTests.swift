import Foundation
import SwiftData
import Testing

@testable import AscendApp

/// Proves the `source` -> `sourceRawValue` move carries existing stores forward instead of
/// resetting them.
///
/// Every test here seeds a real on-disk store under the *old* schema first. An empty store would
/// prove nothing: the failure this guards against is silent, and looks exactly like a healthy
/// fresh install - every row reads back `.manual`, `isInAppSensorWorkout` goes false, and
/// `integrityLevel` keeps claiming the workout is verified.
@MainActor
@Suite(.serialized)
struct WorkoutSourceSchemaMigrationTests {
    private static let sessionStart = Date(timeIntervalSince1970: 1_760_000_000)

    @Test
    func migrationCarriesEveryRecordedSourceForward() throws {
        let storeURL = Self.makeStoreURL()
        defer { Self.removeStore(at: storeURL) }
        let stashScope = Self.IsolatedStash()
        defer { stashScope.tearDown() }

        let headphoneID = UUID()
        let appleHealthID = UUID()
        let manualID = UUID()

        try Self.seedLegacyStore(at: storeURL) { context in
            context.insert(
                AscendSchemaV1.Workout(
                    id: headphoneID,
                    name: "Live Climb",
                    date: Self.sessionStart,
                    duration: 1800,
                    steps: 3000,
                    floors: 187,
                    source: .headphoneMotion
                )
            )
            context.insert(
                AscendSchemaV1.Workout(
                    id: appleHealthID,
                    name: "Stair Stepper",
                    date: Self.sessionStart.addingTimeInterval(86_400),
                    duration: 1200,
                    steps: 2000,
                    floors: 125,
                    source: .appleHealth,
                    healthKitUUID: "hk-1"
                )
            )
            context.insert(
                AscendSchemaV1.Workout(
                    id: manualID,
                    name: "Logged By Hand",
                    date: Self.sessionStart.addingTimeInterval(172_800),
                    duration: 900,
                    steps: 1500,
                    floors: 93,
                    source: .manual
                )
            )
        }

        let context = try Self.openMigratedStore(at: storeURL)
        let migrated = try context.fetch(FetchDescriptor<Workout>())
        let sourcesByID = Dictionary(uniqueKeysWithValues: migrated.map { ($0.id, $0.source) })

        #expect(migrated.count == 3)
        #expect(sourcesByID[headphoneID] == .headphoneMotion)
        #expect(sourcesByID[appleHealthID] == .appleHealth)
        #expect(sourcesByID[manualID] == .manual)
    }

    @Test
    func migratedInAppSensorWorkoutsStayEnrichable() throws {
        let storeURL = Self.makeStoreURL()
        defer { Self.removeStore(at: storeURL) }
        let stashScope = Self.IsolatedStash()
        defer { stashScope.tearDown() }

        let headphoneID = UUID()

        try Self.seedLegacyStore(at: storeURL) { context in
            context.insert(
                AscendSchemaV1.Workout(
                    id: headphoneID,
                    name: "Live Climb",
                    date: Self.sessionStart,
                    duration: 1800,
                    steps: 3000,
                    floors: 187,
                    source: .headphoneMotion
                )
            )
            context.insert(
                AscendSchemaV1.Workout(
                    id: UUID(),
                    name: "Stair Stepper",
                    date: Self.sessionStart.addingTimeInterval(86_400),
                    duration: 1200,
                    steps: 2000,
                    floors: 125,
                    source: .appleHealth,
                    healthKitUUID: "hk-1"
                )
            )
        }

        let context = try Self.openMigratedStore(at: storeURL)

        let migratedHeadphone = try #require(
            try context.fetch(FetchDescriptor<Workout>()).first { $0.id == headphoneID }
        )
        #expect(migratedHeadphone.isInAppSensorWorkout)

        // The predicate reads the stored column directly, so this fails if the migration only
        // fixed up the computed accessor and left `sourceRawValue` on its `.manual` default.
        let inAppSensorWorkouts = try InAppSensorWorkoutQuery.allInAppSensorWorkouts(in: context)
        #expect(inAppSensorWorkouts.map(\.id) == [headphoneID])
    }

    @Test
    func migrationLeavesTheRestOfTheWorkoutIntact() throws {
        let storeURL = Self.makeStoreURL()
        defer { Self.removeStore(at: storeURL) }
        let stashScope = Self.IsolatedStash()
        defer { stashScope.tearDown() }

        let workoutID = UUID()

        try Self.seedLegacyStore(at: storeURL) { context in
            context.insert(
                AscendSchemaV1.Workout(
                    id: workoutID,
                    name: "Stair Stepper",
                    date: Self.sessionStart,
                    duration: 1500,
                    steps: 2400,
                    floors: 150,
                    source: .appleHealth,
                    healthKitUUID: "hk-legacy"
                )
            )
        }

        let context = try Self.openMigratedStore(at: storeURL)
        let migrated = try #require(try context.fetch(FetchDescriptor<Workout>()).first)

        #expect(migrated.id == workoutID)
        #expect(migrated.name == "Stair Stepper")
        #expect(migrated.date == Self.sessionStart)
        #expect(migrated.duration == 1500)
        #expect(migrated.steps == 2400)
        #expect(migrated.floors == 150)
        #expect(migrated.healthKitUUID == "hk-legacy")
        #expect(migrated.source == .appleHealth)
        #expect(migrated.integrityLevel == .verified)
    }

    @Test
    func aFreshStoreOpensStraightOntoTheCurrentSchema() throws {
        let storeURL = Self.makeStoreURL()
        defer { Self.removeStore(at: storeURL) }
        let stashScope = Self.IsolatedStash()
        defer { stashScope.tearDown() }

        let context = try Self.openMigratedStore(at: storeURL)
        let workout = Workout(
            name: "Live Climb",
            date: Self.sessionStart,
            duration: 1800,
            steps: 3000,
            floors: 187,
            source: .headphoneMotion
        )
        context.insert(workout)
        try context.save()

        #expect(try InAppSensorWorkoutQuery.allInAppSensorWorkouts(in: context).count == 1)
    }

    /// The failure path, which is the one that matters.
    ///
    /// A `didMigrate` that throws leaves the store recorded as V2 with the old `source` column
    /// already gone, and SwiftData will not re-enter the stage to try again. If the next launch
    /// simply succeeded, every workout would read `.manual` for good - the exact silent loss this
    /// migration exists to prevent, only now indistinguishable from a healthy install.
    @Test
    func aMigrationThatFailsPartwayIsFinishedOnTheNextLaunch() throws {
        let storeURL = Self.makeStoreURL()
        defer { Self.removeStore(at: storeURL) }
        let stashScope = Self.IsolatedStash()
        defer { stashScope.tearDown() }

        let headphoneID = UUID()
        let appleHealthID = UUID()

        try Self.seedLegacyStore(at: storeURL) { context in
            context.insert(
                AscendSchemaV1.Workout(
                    id: headphoneID,
                    name: "Live Climb",
                    date: Self.sessionStart,
                    duration: 1800,
                    steps: 3000,
                    floors: 187,
                    source: .headphoneMotion
                )
            )
            context.insert(
                AscendSchemaV1.Workout(
                    id: appleHealthID,
                    name: "Stair Stepper",
                    date: Self.sessionStart.addingTimeInterval(86_400),
                    duration: 1200,
                    steps: 2000,
                    floors: 125,
                    source: .appleHealth,
                    healthKitUUID: "hk-1"
                )
            )
        }

        #expect(throws: (any Error).self) {
            _ = try Self.openStore(at: storeURL, migrationPlan: FailingWorkoutSourceMigrationPlan.self)
        }

        let interrupted = try Self.readSources(at: storeURL, finishInterruptedMigration: false)
        #expect(
            interrupted[headphoneID] == .manual,
            """
            the failed migration was expected to leave the store unwritten; it read back \
            \(String(describing: interrupted[headphoneID])), so this test is not exercising the \
            recovery path it claims to
            """
        )

        let recovered = try Self.readSources(at: storeURL, finishInterruptedMigration: true)
        #expect(recovered[headphoneID] == .headphoneMotion)
        #expect(recovered[appleHealthID] == .appleHealth)

        #expect(
            stashScope.stash.load().sourcesByWorkoutID.isEmpty,
            "a completed recovery has to clear the stash so later launches stop repairing"
        )

        let afterRecovery = try Self.readSources(at: storeURL, finishInterruptedMigration: true)
        #expect(afterRecovery[headphoneID] == .headphoneMotion)
    }

    /// The paged-save failure path: some pages committed, then the sweep died.
    ///
    /// The write commits a page at a time so its pending-change set stays bounded, which means a
    /// failure can now leave the store *half* repaired rather than untouched. That is only safe
    /// because the stash - not the transaction - is the unit of completion: it survives every
    /// partial run and is cleared once, after the last page. This asserts the half-repaired store
    /// converges, and that re-applying the pages that already landed is free.
    @Test
    func aSweepInterruptedBetweenPagesIsFinishedOnTheNextLaunch() throws {
        let directory = Self.freshStoreDirectory(named: "partial-commit")
        let storeURL = directory.appending(path: "\(UUID().uuidString).store")
        let stashScope = Self.IsolatedStash()
        defer { stashScope.tearDown() }

        // Only verified sources, so an unwritten row is unambiguously `.manual`.
        let sourceRotation: [WorkoutSource] = [.headphoneMotion, .appleHealth]
        let workoutCount = AscendMigrationPlan.readPageSize * 2 + 50
        var orderedIDs: [UUID] = []
        var expectedSources: [UUID: WorkoutSource] = [:]

        try Self.seedLegacyStore(at: storeURL) { context in
            for index in 0..<workoutCount {
                let source = sourceRotation[index % sourceRotation.count]
                let workout = AscendSchemaV1.Workout(
                    id: UUID(),
                    name: "Seeded \(index)",
                    date: Self.sessionStart.addingTimeInterval(TimeInterval(index) * -86_400),
                    duration: 1800,
                    steps: 3000,
                    floors: 187,
                    source: source
                )
                context.insert(workout)
                orderedIDs.append(workout.id)
                expectedSources[workout.id] = source
            }
        }

        #expect(throws: (any Error).self) {
            _ = try Self.openStore(at: storeURL, migrationPlan: FailingWorkoutSourceMigrationPlan.self)
        }

        // Stand in for a sweep that committed its first page and then died: exactly the store
        // state paged saves can leave behind, which all-or-nothing never could.
        let committedIDs = Set(orderedIDs.prefix(AscendMigrationPlan.readPageSize))
        try Self.commitSources(at: storeURL, expectedSources.filter { committedIDs.contains($0.key) })

        let interrupted = try Self.readSources(at: storeURL, finishInterruptedMigration: false)
        #expect(interrupted.filter { $0.value == .manual }.count == workoutCount - committedIDs.count)

        let report = try Self.recoverSources(at: storeURL)
        #expect(
            report.repairedCount == workoutCount - committedIDs.count,
            """
            recovery rewrote \(report.repairedCount) workouts when only \
            \(workoutCount - committedIDs.count) were still unwritten; the already-committed pages \
            are supposed to be skipped, not redone
            """
        )
        #expect(report.pageCount > 1)

        let recovered = try Self.readSources(at: storeURL, finishInterruptedMigration: false)
        #expect(recovered == expectedSources)
        #expect(stashScope.stash.load().sourcesByWorkoutID.isEmpty)
    }

    /// A repair that can never succeed has to stop, not retry on every launch forever.
    ///
    /// Failing loudly is right for a transient failure - the stash survives and the next launch
    /// finishes the job. It is wrong for a permanent one, where the same error would be thrown at
    /// every startup for the life of the install. After `maximumAttempts` the sweep stops running
    /// at all; the stash file is deliberately left on disk rather than deleted, so the values are
    /// still there to inspect.
    @Test
    func aRepairThatKeepsFailingIsGivenUpOnRatherThanRetriedForever() throws {
        let storeURL = Self.makeStoreURL()
        defer { Self.removeStore(at: storeURL) }
        let stashScope = Self.IsolatedStash()
        defer { stashScope.tearDown() }

        let headphoneID = UUID()
        try Self.seedLegacyStore(at: storeURL) { context in
            context.insert(
                AscendSchemaV1.Workout(
                    id: headphoneID,
                    name: "Live Climb",
                    date: Self.sessionStart,
                    duration: 1800,
                    steps: 3000,
                    floors: 187,
                    source: .headphoneMotion
                )
            )
        }

        #expect(throws: (any Error).self) {
            _ = try Self.openStore(at: storeURL, migrationPlan: FailingWorkoutSourceMigrationPlan.self)
        }

        // A store that refuses writes fails the sweep for real, at `context.save()`, so the
        // counter is driven by actual failures rather than primed by hand - the give-up branch
        // is only worth anything if a genuine failure reaches it.
        for attempt in 1..<WorkoutSourceMigrationStash.maximumAttempts {
            #expect(throws: (any Error).self) {
                _ = try Self.recoverSources(at: storeURL, allowsSave: false)
            }
            #expect(stashScope.stash.load().failedAttemptCount == attempt)
        }

        let abandoning = try Self.recoverSources(at: storeURL, allowsSave: false)
        #expect(
            abandoning.abandonedAfterRepeatedFailures,
            """
            the last attempt still threw instead of giving up; a permanently failing repair has to \
            stop and report itself, not retry on every launch forever
            """
        )
        #expect(abandoning.failedAttemptCount == WorkoutSourceMigrationStash.maximumAttempts)

        // And once given up on, it stops walking the store entirely.
        let afterAbandonment = try Self.recoverSources(at: storeURL)
        #expect(afterAbandonment.pageCount == 0, "an exhausted repair must not walk the store again")
        #expect(afterAbandonment.repairedCount == 0)
        #expect(afterAbandonment.abandonedAfterRepeatedFailures == false)

        #expect(
            stashScope.stash.load().sourcesByWorkoutID.isEmpty == false,
            "the stashed values stay on disk after the repair is abandoned, for inspection"
        )
    }

    /// A migration that cannot stash anything must still let the app open.
    ///
    /// The read pass is the one that runs before the schema step commits, so a throw from it
    /// leaves the store on V1 and the next launch runs the identical code and fails identically -
    /// an app that never opens again, which is worse than the hang this branch exists to fix.
    /// After `maximumAttempts` it stops throwing and proceeds with whatever it has. Loud has to
    /// mean observable, not fatal.
    @Test
    func aReadPassThatCannotStashStopsRefusingToOpenTheStore() throws {
        let storeURL = Self.makeStoreURL()
        defer { Self.removeStore(at: storeURL) }
        let stashScope = Self.IsolatedStash(unwritable: true)
        defer { stashScope.tearDown() }

        try Self.seedLegacyStore(at: storeURL) { context in
            context.insert(
                AscendSchemaV1.Workout(
                    id: UUID(),
                    name: "Live Climb",
                    date: Self.sessionStart,
                    duration: 1800,
                    steps: 3000,
                    floors: 187,
                    source: .headphoneMotion
                )
            )
        }

        // The whole point: the container is constructible. The sources are lost - the stash is
        // the only place they could have survived - but the user still has an app.
        let migrated = try Self.readSources(at: storeURL, finishInterruptedMigration: false)
        #expect(migrated.count == 1)
    }

    /// Every way this migration can lose a source has to ask to be reported *off the device*.
    ///
    /// This is the half of observable-over-fatal that cannot be checked by watching the app: three
    /// times in this branch the reporting was implemented and landed somewhere nobody would ever
    /// read it - once behind `#if DEBUG`, once with remote mirroring switched off - while the
    /// don't-brick-the-launch half landed correctly every time, because that half is observable
    /// from inside the process and this one is not. The request is observable, so it is asserted:
    /// turning mirroring back off silently now fails here instead of failing in production.
    @Test
    func everyWayTheMigrationLosesSourcesAsksToBeReportedRemotely() throws {
        let recorder = SpyDiagnosticsRecorder()
        let previousDiagnostics = AscendMigrationPlan.diagnostics
        AscendMigrationPlan.diagnostics = recorder
        defer { AscendMigrationPlan.diagnostics = previousDiagnostics }

        // The read pass giving up and proceeding with what it has.
        try Self.withUnrepairableStore { _, _ in }
        let readStoreURL = Self.makeStoreURL()
        defer { Self.removeStore(at: readStoreURL) }
        let unwritableStash = Self.IsolatedStash(unwritable: true)
        defer { unwritableStash.tearDown() }

        try Self.seedLegacyStore(at: readStoreURL) { context in
            context.insert(
                AscendSchemaV1.Workout(
                    id: UUID(),
                    name: "Live Climb",
                    date: Self.sessionStart,
                    duration: 1800,
                    steps: 3000,
                    floors: 187,
                    source: .headphoneMotion
                )
            )
        }
        try Self.withLegacyStore(at: readStoreURL) { context in
            _ = try? AscendMigrationPlan.stashLegacySources(
                from: context,
                stash: unwritableStash.stash
            )
        }

        try Self.withUnrepairableStore { storeURL, stashScope in
            // The write pass swallowing its failure so `didMigrate` cannot fail the container.
            AscendMigrationPlan.applyStashedSourcesReportingFailure(
                to: try Self.openMigratedStore(at: storeURL, allowsSave: false),
                stash: stashScope.stash
            )

            // The write pass giving up for good.
            for _ in 1..<WorkoutSourceMigrationStash.maximumAttempts {
                _ = try? AscendMigrationPlan.applyStashedSources(
                    to: try Self.openMigratedStore(at: storeURL, allowsSave: false),
                    stash: stashScope.stash
                )
            }

            // A stash that exists but will not decode.
            try Data("not json".utf8).write(to: stashScope.fileURL, options: .atomic)
            _ = try AscendMigrationPlan.applyStashedSources(
                to: try Self.openMigratedStore(at: storeURL),
                stash: stashScope.stash
            )
        }

        for name in [
            "workout_source_migration_read_failed",
            "workout_source_migration_write_failed",
            "workout_source_migration_abandoned",
            "workout_source_migration_stash_unreadable"
        ] {
            let recorded = recorder.events.filter { $0.name == name }
            let everyOneAsksToLeaveTheDevice = recorded.allSatisfy(\.mirrorToCrashlytics)

            #expect(!recorded.isEmpty, "\(name) was never recorded, so this loss reaches nobody")
            #expect(
                everyOneAsksToLeaveTheDevice,
                """
                \(name) was recorded without asking for remote mirroring, so it never leaves the \
                device - the app opens and looks healthy while the sources are gone
                """
            )
        }
    }

    /// The counts a write-pass failure carries have to describe what actually happened.
    ///
    /// A failure that had already repaired most of the store is a different incident from one that
    /// never started, and reporting zeroes for both hides which one it was.
    @Test
    func aSwallowedWriteFailureReportsHowFarItGot() throws {
        let recorder = SpyDiagnosticsRecorder()
        let previousDiagnostics = AscendMigrationPlan.diagnostics
        AscendMigrationPlan.diagnostics = recorder
        defer { AscendMigrationPlan.diagnostics = previousDiagnostics }

        try Self.withUnrepairableStore { storeURL, stashScope in
            AscendMigrationPlan.applyStashedSourcesReportingFailure(
                to: try Self.openMigratedStore(at: storeURL, allowsSave: false),
                stash: stashScope.stash
            )
        }

        let recorded = try #require(
            recorder.events.first { $0.name == "workout_source_migration_write_failed" }
        )
        #expect(
            recorded.details["failed_attempt_count"] == "1",
            """
            the swallowed failure reported failed_attempt_count \
            \(recorded.details["failed_attempt_count"] ?? "nil"); a zeroed report reads as though \
            nothing was attempted
            """
        )
        #expect(recorded.details["resolved_count"] != nil)
        #expect(recorded.details["repaired_count"] != nil)
    }

    /// The memory bound, measured at the store size that produced ASCEND-IOS-1K.
    ///
    /// The other tests in this suite seed one to three workouts, so they pass identically whether
    /// the read is paged or not - they are evidence about *correctness*, not about cost. This one
    /// seeds the shape the hang was reproduced against (900 sessions carrying a 45-minute
    /// heart-rate series each, ~94 MB of inline `heartRateData`) and asserts the structural fact
    /// that actually regressed once already: that the sweep never holds the whole store
    /// materialised at once. Delete the paging and `largestPageSize` becomes the row count.
    ///
    /// Resident footprint is deliberately not the signal. It was tried in this PR and rejected -
    /// CoreData faults binary attributes lazily, so scanning all 900 of these rows moves the
    /// process footprint by single-digit MB, and by a different single-digit MB warm than cold.
    @Test
    func bothMigrationPassesReadTheStoreInBoundedPages() throws {
        let directory = Self.freshStoreDirectory(named: "paging")
        let storeURL = directory.appending(path: "\(UUID().uuidString).store")
        let stashScope = Self.IsolatedStash()
        defer { stashScope.tearDown() }

        var expectedSources: [UUID: WorkoutSource] = [:]
        try Self.seedLegacyStore(at: storeURL) { context in
            for index in 0..<Self.pagingStoreSize {
                let source = Self.rotatingSources[index % Self.rotatingSources.count]
                let workout = AscendSchemaV1.Workout(
                    id: UUID(),
                    name: "Seeded \(index)",
                    date: Self.sessionStart.addingTimeInterval(TimeInterval(index) * -86_400),
                    duration: 45 * 60,
                    steps: 3_200,
                    floors: 200,
                    source: source
                )
                workout.heartRateData = Self.heartRateSeries().encoded
                context.insert(workout)
                expectedSources[workout.id] = source
            }
        }

        // The read pass, run exactly as `willMigrate` runs it.
        let readReport = try Self.withLegacyStore(at: storeURL) { context in
            try AscendMigrationPlan.stashLegacySources(from: context, stash: stashScope.stash)
        }

        // The write pass, run exactly as `didMigrate` runs it, against the migrated store.
        let migratedContext = try Self.openMigratedStore(at: storeURL)
        try stashScope.stash.store(
            expectedSources.reduce(into: [UUID: String]()) { $0[$1.key] = $1.value.rawValue }
        )
        let writeReport = try AscendMigrationPlan.applyStashedSources(
            to: migratedContext,
            stash: stashScope.stash
        )

        let expectedPageCount = (Self.pagingStoreSize + AscendMigrationPlan.readPageSize - 1)
            / AscendMigrationPlan.readPageSize

        print(
            """
            workout source migration paging
              store             \(Self.pagingStoreSize) workouts, \
            \(Self.heartRateSamplesPerWorkout) heart-rate samples each
              page size         \(AscendMigrationPlan.readPageSize)
              read pass         \(readReport.pageCount) pages, \
            largest \(readReport.largestPageSize)
              write pass        \(writeReport.pageCount) pages, \
            largest \(writeReport.largestPageSize)
            """
        )

        #expect(readReport.workoutCount == Self.pagingStoreSize)
        #expect(writeReport.workoutCount == Self.pagingStoreSize)

        // The contract. A single unbounded fetch reports one page holding every row, so removing
        // the paging fails both of these rather than quietly reintroducing the cost.
        #expect(
            readReport.largestPageSize == AscendMigrationPlan.readPageSize,
            """
            the read pass held \(readReport.largestPageSize) workouts materialised at once against \
            a page size of \(AscendMigrationPlan.readPageSize); it is walking the whole store in \
            one fetch
            """
        )
        #expect(
            writeReport.largestPageSize == AscendMigrationPlan.readPageSize,
            """
            the write pass held \(writeReport.largestPageSize) workouts materialised at once \
            against a page size of \(AscendMigrationPlan.readPageSize)
            """
        )
        #expect(readReport.pageCount == expectedPageCount)
        #expect(writeReport.pageCount == expectedPageCount)

        // Paging that skips a row is worse than paging that is slow, so the sources are checked
        // across the whole store rather than sampled.
        let migrated = try migratedContext.fetch(FetchDescriptor<Workout>())
        #expect(migrated.count == Self.pagingStoreSize)
        #expect(migrated.allSatisfy { expectedSources[$0.id] == $0.source })
    }

    // MARK: - Store helpers

    private static let pagingStoreSize = 900
    private static let heartRateSamplesPerWorkout = 2_600
    private static let rotatingSources: [WorkoutSource] = [.headphoneMotion, .appleHealth, .manual]

    private static func heartRateSeries() -> [HeartRateDataPoint] {
        (0..<heartRateSamplesPerWorkout).map { second in
            HeartRateDataPoint(
                timestamp: sessionStart.addingTimeInterval(TimeInterval(second)),
                heartRate: 120 + (second % 60)
            )
        }
    }

    /// A directory nothing else is holding open.
    ///
    /// The path carries a UUID rather than a fixed name because the sweep below unlinks it, and
    /// unlinking a store file while a `ModelContainer` still has it open is an SQLite API
    /// violation. `@Suite(.serialized)` rules that out within one process; it does nothing across
    /// the parallel worktrees that share this machine's simulator. Nothing cleans up on the way
    /// out - a container has no close, so the only safe moment to unlink is before anything opens.
    private static func freshStoreDirectory(named name: String) -> URL {
        let directory = URL.temporaryDirectory
            .appending(path: "ascend-migration-paging/\(name)-\(UUID().uuidString)")
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Points the real migration plan at a scratch stash for the length of one test.
    ///
    /// `MigrationStage` builds its phases statically, so the plan resolves
    /// `WorkoutSourceMigrationStash.shared` rather than taking one - swapping the singleton is the
    /// only way a test can keep its hands off the app's real stash file. `@Suite(.serialized)`
    /// orders these tests against each other but not against other suites, so the isolation has to
    /// come from here rather than from the ordering.
    /// Seeds a migrated store whose stash still holds every source, so a caller can drive the
    /// write pass against a store that refuses writes.
    private static func withUnrepairableStore(
        _ body: (URL, IsolatedStash) throws -> Void
    ) throws {
        let storeURL = makeStoreURL()
        defer { removeStore(at: storeURL) }
        let stashScope = IsolatedStash()
        defer { stashScope.tearDown() }

        try seedLegacyStore(at: storeURL) { context in
            context.insert(
                AscendSchemaV1.Workout(
                    id: UUID(),
                    name: "Live Climb",
                    date: sessionStart,
                    duration: 1800,
                    steps: 3000,
                    floors: 187,
                    source: .headphoneMotion
                )
            )
        }

        #expect(throws: (any Error).self) {
            _ = try openStore(at: storeURL, migrationPlan: FailingWorkoutSourceMigrationPlan.self)
        }

        try body(storeURL, stashScope)
    }

    private final class IsolatedStash {
        let fileURL: URL
        let stash: WorkoutSourceMigrationStash
        private let previous: WorkoutSourceMigrationStash

        private let blockerURL: URL?

        /// `unwritable` puts the stash under a path whose parent is a regular file, so every
        /// `store` and `recordFailedAttempt` fails the way a permanently broken stash would.
        init(unwritable: Bool = false) {
            let root = URL.temporaryDirectory
                .appending(path: "ascend-migration-stash-\(UUID().uuidString)")

            if unwritable {
                try? Data().write(to: root)
                blockerURL = root
                fileURL = root.appending(path: "stash.json")
            } else {
                blockerURL = nil
                fileURL = root.appendingPathExtension("json")
            }

            stash = WorkoutSourceMigrationStash(fileURL: fileURL)
            previous = WorkoutSourceMigrationStash.shared
            WorkoutSourceMigrationStash.shared = stash
        }

        func tearDown() {
            WorkoutSourceMigrationStash.shared = previous
            try? FileManager.default.removeItem(at: fileURL)

            if let blockerURL {
                try? FileManager.default.removeItem(at: blockerURL)
            }
        }
    }

    private static func makeStoreURL() -> URL {
        URL.temporaryDirectory.appending(path: "ascend-migration-\(UUID().uuidString).store")
    }

    private static func removeStore(at url: URL) {
        for candidate in [url, url.appendingPathExtension("shm"), url.appendingPathExtension("wal")] {
            try? FileManager.default.removeItem(at: candidate)
        }
    }

    /// Writes a store in the shape older installs left behind, then closes it.
    ///
    /// The container has to be gone before the migrated one opens the same file, so it stays
    /// scoped to this call and is never handed back.
    private static func seedLegacyStore(
        at url: URL,
        _ seed: (ModelContext) throws -> Void
    ) throws {
        let schema = Schema(versionedSchema: AscendSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: url)
        )
        let context = ModelContext(container)
        try seed(context)
        try context.save()
    }

    /// Reopens the store under the old schema, the way `willMigrate` sees it.
    private static func withLegacyStore<T>(
        at url: URL,
        _ body: (ModelContext) throws -> T
    ) throws -> T {
        let schema = Schema(versionedSchema: AscendSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: url)
        )
        return try body(ModelContext(container))
    }

    private static func openMigratedStore(at url: URL, allowsSave: Bool = true) throws -> ModelContext {
        ModelContext(
            try openStore(at: url, migrationPlan: AscendMigrationPlan.self, allowsSave: allowsSave)
        )
    }

    private static func openStore(
        at url: URL,
        migrationPlan: (any SchemaMigrationPlan.Type)?,
        allowsSave: Bool = true
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: AscendSchemaV2.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: migrationPlan,
            configurations: ModelConfiguration(schema: schema, url: url, allowsSave: allowsSave)
        )
    }

    /// Writes sources straight onto the migrated store, bypassing the stash, so a test can build
    /// the store state a partially-committed sweep leaves behind.
    private static func commitSources(
        at url: URL,
        _ sourcesByWorkoutID: [UUID: WorkoutSource]
    ) throws {
        let context = try openMigratedStore(at: url)

        for workout in try context.fetch(FetchDescriptor<Workout>()) {
            guard let source = sourcesByWorkoutID[workout.id] else { continue }
            workout.source = source
        }

        try context.save()
    }

    private static func recoverSources(
        at url: URL,
        allowsSave: Bool = true
    ) throws -> AscendMigrationPlan.SweepReport {
        try AscendMigrationPlan.recoverInterruptedMigrationIfNeeded(
            in: try openMigratedStore(at: url, allowsSave: allowsSave)
        )
    }

    /// Opens the store the way a launch does, reads the sources out as plain values, and lets the
    /// container go - so the next open in the same test is not fighting a live connection.
    private static func readSources(
        at url: URL,
        finishInterruptedMigration: Bool
    ) throws -> [UUID: WorkoutSource] {
        let context = try openMigratedStore(at: url)
        if finishInterruptedMigration {
            try AscendMigrationPlan.recoverInterruptedMigrationIfNeeded(in: context)
        }

        return try context.fetch(FetchDescriptor<Workout>())
            .reduce(into: [UUID: WorkoutSource]()) { partialResult, workout in
                partialResult[workout.id] = workout.source
            }
    }
}

/// Stands in for the launch where `didMigrate` never lands: the real `willMigrate` runs and
/// stashes the old sources, then the write fails.
private enum FailingWorkoutSourceMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AscendSchemaV1.self, AscendSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            MigrationStage.custom(
                fromVersion: AscendSchemaV1.self,
                toVersion: AscendSchemaV2.self,
                willMigrate: { context in
                    try AscendMigrationPlan.stashLegacySources(from: context)
                },
                didMigrate: { _ in
                    throw InjectedMigrationFailure.didMigrateInterrupted
                }
            )
        ]
    }
}

private enum InjectedMigrationFailure: Error {
    case didMigrateInterrupted
}

/// Captures what the migration *asked* the diagnostics layer for.
private final class SpyDiagnosticsRecorder: AppDiagnosticsRecording, @unchecked Sendable {
    struct Recorded {
        let name: String
        let details: [String: String]
        let mirrorToCrashlytics: Bool
    }

    private let lock = NSLock()
    private var recorded: [Recorded] = []

    var events: [Recorded] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    @discardableResult
    func record(
        _ name: String,
        level: AppDiagnosticEvent.Level,
        details: [String: String],
        mirrorToCrashlytics: Bool
    ) -> AppDiagnosticEvent {
        lock.lock()
        recorded.append(
            Recorded(name: name, details: details, mirrorToCrashlytics: mirrorToCrashlytics)
        )
        lock.unlock()

        return AppDiagnosticEvent(name: name, level: level, details: details)
    }
}
