import Foundation
import SwiftData
import Testing

@testable import AscendApp

/// Proves the Apple Health ledger reaches an existing store without costing a climber anything.
///
/// Every test seeds a real on-disk store through `AscendSchemaV6` - the shape every build before
/// import wrote - and reopens it under the live schema with the real plan. A store the current
/// build just created already has the new table, so it proves nothing about the stores that were
/// written without it.
@MainActor
@Suite(.serialized)
struct HealthWorkoutRecordSchemaMigrationTests {
    private static let sessionStart = Date(timeIntervalSince1970: 1_760_000_000)

    @Test
    func theLiveSchemaIsTheOneTheStageEndsAt() {
        #expect(AscendLocalStore.currentSchema is AscendSchemaV7.Type)
        #expect(AscendMigrationPlan.schemas.last is AscendSchemaV7.Type)
        #expect(AscendMigrationPlan.stages.count == AscendMigrationPlan.schemas.count - 1)
        #expect(AscendLocalStore.models.contains { $0 == HealthWorkoutRecord.self })
    }

    @Test
    func everyExistingClimbSurvivesWithItsFieldsAndTheLedgerStartsEmpty() throws {
        let storeURL = Self.makeStoreURL()
        let liveID = UUID()
        let healthID = UUID()

        try Self.seedPreviousStore(at: storeURL) { context in
            let live = Workout(
                name: "Empire State", date: Self.sessionStart, duration: 2_347, steps: 3_042,
                floors: 190, source: .headphoneMotion
            )
            live.id = liveID
            live.leaderboardStatus = .eligible
            live.notes = "Felt strong"
            context.insert(live)

            let hand = Workout(
                name: "Stair Stepper", date: Self.sessionStart.addingTimeInterval(86_400),
                duration: 1_800, steps: 7_500, floors: 469, source: .manual
            )
            hand.id = healthID
            hand.leaderboardStatus = .excluded
            context.insert(hand)
        }

        let context = try Self.openMigratedStore(at: storeURL)
        let climbs = try context.fetch(FetchDescriptor<Workout>())
        let byID = Dictionary(uniqueKeysWithValues: climbs.map { ($0.id, $0) })

        #expect(climbs.count == 2)
        #expect(byID[liveID]?.notes == "Felt strong")
        #expect(byID[liveID]?.steps == 3_042)
        #expect(byID[liveID]?.leaderboardStatus == .eligible)
        #expect(byID[healthID]?.leaderboardStatus == .excluded, "the pace verdict the previous build recorded is untouched")
        #expect(byID[healthID]?.source == .manual)
        #expect(try context.fetchCount(FetchDescriptor<HealthWorkoutRecord>()) == 0)
    }

    @Test
    func theLedgerIsWritableAndFilterableAfterTheMigration() throws {
        let storeURL = Self.makeStoreURL()
        try Self.seedPreviousStore(at: storeURL) { context in
            context.insert(
                Workout(name: "Old", date: Self.sessionStart, duration: 1_800, steps: 3_000, floors: 187, source: .headphoneMotion)
            )
        }

        let context = try Self.openMigratedStore(at: storeURL)
        let snapshot = HealthWorkoutSnapshot(
            uuid: UUID(), startDate: Self.sessionStart, endDate: Self.sessionStart.addingTimeInterval(1_800),
            duration: 1_800, steps: 4_912, averageHeartRate: 127, maxHeartRate: 158, activeEnergyKilocalories: 411
        )
        let waiting = HealthWorkoutRecord(snapshot: snapshot)
        let skipped = HealthWorkoutRecord(
            snapshot: HealthWorkoutSnapshot(
                uuid: UUID(), startDate: Self.sessionStart, endDate: Self.sessionStart.addingTimeInterval(600), steps: nil
            )
        )
        skipped.state = .skipped
        context.insert(waiting)
        context.insert(skipped)
        try context.save()

        let ledger = HealthWorkoutLedger(modelContext: context)
        #expect(try ledger.notImported().map(\.workoutUUID) == [snapshot.uuid.uuidString])
        #expect(try ledger.record(forUUID: snapshot.uuid.uuidString)?.steps == 4_912)
        #expect(try ledger.record(forUUID: snapshot.uuid.uuidString)?.averageHeartRate == 127)
        #expect(try ledger.record(forUUID: skipped.workoutUUID)?.state == .skipped)
        #expect(try ledger.record(forUUID: skipped.workoutUUID)?.steps == nil)
    }

    @Test
    func aStoreWithNoClimbsStillOpens() throws {
        let storeURL = Self.makeStoreURL()
        try Self.seedPreviousStore(at: storeURL) { _ in }

        let context = try Self.openMigratedStore(at: storeURL)
        #expect(try context.fetchCount(FetchDescriptor<Workout>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<HealthWorkoutRecord>()) == 0)
    }

    @Test
    func aStoreFromTheFirstShippedVersionStillReachesTheLedger() throws {
        let storeURL = Self.makeStoreURL()
        try autoreleasepool {
            let schema = Schema(versionedSchema: AscendSchemaV5.self)
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: storeURL)
            )
            let context = ModelContext(container)
            context.insert(
                AscendSchemaV5.Workout(
                    id: UUID(), name: "Older", date: Self.sessionStart, duration: 1_200,
                    steps: 2_000, floors: 125, source: .headphoneMotion
                )
            )
            try context.save()
        }

        let context = try Self.openMigratedStore(at: storeURL)
        #expect(try context.fetchCount(FetchDescriptor<Workout>()) == 1)
        context.insert(
            HealthWorkoutRecord(
                snapshot: HealthWorkoutSnapshot(
                    uuid: UUID(), startDate: Self.sessionStart, endDate: Self.sessionStart.addingTimeInterval(900)
                )
            )
        )
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<HealthWorkoutRecord>()) == 1)
    }

    // MARK: - Helpers

    private static func makeStoreURL() -> URL {
        let directory = URL.temporaryDirectory.appending(path: "ascend-health-ledger-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "migration.store")
    }

    private static func seedPreviousStore(
        at url: URL,
        _ seed: (ModelContext) throws -> Void
    ) throws {
        try autoreleasepool {
            let schema = Schema(versionedSchema: AscendSchemaV6.self)
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url)
            )
            let context = ModelContext(container)
            try seed(context)
            try context.save()
        }
    }

    private static func openMigratedStore(at url: URL) throws -> ModelContext {
        let schema = Schema(versionedSchema: AscendLocalStore.currentSchema)
        return ModelContext(
            try ModelContainer(
                for: schema,
                migrationPlan: AscendMigrationPlan.self,
                configurations: ModelConfiguration(schema: schema, url: url)
            )
        )
    }
}
