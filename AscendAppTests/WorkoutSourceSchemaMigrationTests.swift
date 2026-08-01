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
        defer { try? WorkoutSourceMigrationStash.shared.clear() }

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
            try WorkoutSourceMigrationStash.shared.load().isEmpty,
            "a completed recovery has to clear the stash so later launches stop repairing"
        )

        let afterRecovery = try Self.readSources(at: storeURL, finishInterruptedMigration: true)
        #expect(afterRecovery[headphoneID] == .headphoneMotion)
    }

    // MARK: - Store helpers

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

    private static func openMigratedStore(at url: URL) throws -> ModelContext {
        ModelContext(try openStore(at: url, migrationPlan: AscendMigrationPlan.self))
    }

    private static func openStore(
        at url: URL,
        migrationPlan: (any SchemaMigrationPlan.Type)?
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: AscendSchemaV2.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: migrationPlan,
            configurations: ModelConfiguration(schema: schema, url: url)
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
