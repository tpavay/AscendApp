import Foundation
import SwiftData
import Testing

@testable import AscendApp

/// Proves `Workout.leaderboardStatusRawValue` reaches an existing store without costing a climber
/// anything.
///
/// Every test seeds a real on-disk store through `AscendSchemaV5` - the frozen shape every build
/// before this one wrote - and reopens it under the live schema with the real plan. A store the
/// current build just created already has the new column, so it proves nothing about the rows that
/// were written without it.
@MainActor
@Suite(.serialized)
struct LeaderboardStatusSchemaMigrationTests {
    private static let sessionStart = Date(timeIntervalSince1970: 1_760_000_000)

    @Test
    func theLiveSchemaIsTheOneTheStageEndsAt() {
        #expect(AscendLocalStore.currentSchema is AscendSchemaV6.Type)
        #expect(AscendMigrationPlan.schemas.last is AscendSchemaV6.Type)
        #expect(AscendMigrationPlan.stages.count == AscendMigrationPlan.schemas.count - 1)
    }

    @Test
    func everyExistingClimbMigratesAsEligibleWithItsSourceUntouched() throws {
        let storeURL = Self.makeStoreURL()
        let liveID = UUID()
        let healthID = UUID()
        let handID = UUID()

        try Self.seedPreviousStore(at: storeURL) { context in
            context.insert(
                AscendSchemaV5.Workout(
                    id: liveID, name: "Live Climb", date: Self.sessionStart,
                    duration: 1_800, steps: 3_000, floors: 187, source: .headphoneMotion
                )
            )
            context.insert(
                AscendSchemaV5.Workout(
                    id: healthID, name: "Stair Stepper", date: Self.sessionStart.addingTimeInterval(86_400),
                    duration: 1_200, steps: 2_000, floors: 125, source: .appleHealth
                )
            )
            // A climb typed in before logging was removed: it is a hand-logged climb again, not a
            // row to repair, and its pace is the only thing that could ever exclude it.
            context.insert(
                AscendSchemaV5.Workout(
                    id: handID, name: "Logged by hand", date: Self.sessionStart.addingTimeInterval(172_800),
                    duration: 900, steps: 1_500, floors: 94, source: .manual
                )
            )
        }

        let context = try Self.openMigratedStore(at: storeURL)
        let migrated = try context.fetch(FetchDescriptor<Workout>())
        let byID = Dictionary(uniqueKeysWithValues: migrated.map { ($0.id, $0) })

        #expect(migrated.count == 3)
        for workout in migrated {
            #expect(workout.leaderboardStatus == .eligible, "\(workout.name) counted before and still does")
            #expect(workout.leaderboardStatusRawValue == LeaderboardStatus.eligible.rawValue)
        }
        #expect(byID[liveID]?.source == .headphoneMotion)
        #expect(byID[liveID]?.origin == .live)
        #expect(byID[healthID]?.source == .appleHealth)
        #expect(byID[healthID]?.origin == .healthImport)
        #expect(byID[handID]?.source == .manual)
        #expect(byID[handID]?.origin == .manual)
    }

    @Test
    func migrationLeavesTheRestOfEveryClimbIntact() throws {
        let storeURL = Self.makeStoreURL()
        let workoutID = UUID()

        try Self.seedPreviousStore(at: storeURL) { context in
            let workout = AscendSchemaV5.Workout(
                id: workoutID, name: "Empire State", date: Self.sessionStart,
                duration: 2_347.75, steps: 3_042, floors: 190, source: .headphoneMotion
            )
            workout.notes = "Felt strong"
            workout.avgHeartRate = 151
            workout.effortRating = 4
            workout.sourceMetadata = #"{"climbId":"empire-state-building"}"#
            workout.ownerUserId = "owner-1"
            workout.remoteSyncStatusRawValue = WorkoutRemoteSyncStatus.synced.rawValue
            context.insert(workout)
            context.insert(
                AscendSchemaV5.WorkoutParticipation(workout: workout, contextId: "empire-state-building")
            )
            context.insert(
                AscendSchemaV5.WorkoutSourceLink(
                    provider: .appleHealth, externalRecordID: "hk-1",
                    providerWindowStart: Self.sessionStart, providerWindowEnd: Self.sessionStart.addingTimeInterval(2_347),
                    workout: workout
                )
            )
        }

        let context = try Self.openMigratedStore(at: storeURL)
        let migrated = try #require(try context.fetch(FetchDescriptor<Workout>()).first { $0.id == workoutID })

        #expect(migrated.name == "Empire State")
        #expect(migrated.duration == 2_347.75)
        #expect(migrated.steps == 3_042)
        #expect(migrated.floors == 190)
        #expect(migrated.notes == "Felt strong")
        #expect(migrated.avgHeartRate == 151)
        #expect(migrated.effortRating == 4)
        #expect(migrated.sourceMetadata == #"{"climbId":"empire-state-building"}"#)
        #expect(migrated.ownerUserId == "owner-1")
        #expect(migrated.remoteSyncStatus == .synced, "a climb already in the cloud is not re-queued by the migration")
        #expect(migrated.participations.count == 1)
        #expect(migrated.participations.first?.contextId == "empire-state-building")
        #expect(migrated.sourceLinks.count == 1)
        #expect(migrated.sourceLinks.first?.externalRecordID == "hk-1")
    }

    @Test
    func theNewColumnIsWritableAndFilterableAfterTheMigration() throws {
        let storeURL = Self.makeStoreURL()

        try Self.seedPreviousStore(at: storeURL) { context in
            context.insert(
                AscendSchemaV5.Workout(
                    id: UUID(), name: "Old", date: Self.sessionStart,
                    duration: 1_800, steps: 3_000, floors: 187, source: .headphoneMotion
                )
            )
        }

        let context = try Self.openMigratedStore(at: storeURL)
        let typed = Workout(
            name: "Stair Stepper", date: Self.sessionStart, duration: 1_800,
            steps: 7_500, floors: 469, source: .manual
        )
        typed.refreshLeaderboardStatus()
        context.insert(typed)
        try context.save()

        let excluded = LeaderboardStatus.excluded.rawValue
        let offTheBoards = try context.fetch(
            FetchDescriptor<Workout>(predicate: #Predicate { $0.leaderboardStatusRawValue == excluded })
        )
        #expect(offTheBoards.map(\.id) == [typed.id])

        let eligible = LeaderboardStatus.eligible.rawValue
        #expect(
            try context.fetchCount(
                FetchDescriptor<Workout>(predicate: #Predicate { $0.leaderboardStatusRawValue == eligible })
            ) == 1
        )
    }

    @Test
    func aStoreWithNoClimbsStillOpens() throws {
        let storeURL = Self.makeStoreURL()
        try Self.seedPreviousStore(at: storeURL) { _ in }

        let context = try Self.openMigratedStore(at: storeURL)
        #expect(try context.fetchCount(FetchDescriptor<Workout>()) == 0)
    }

    @Test
    func aBrandNewInstallOpensOnTheCurrentSchemaDirectly() throws {
        let storeURL = Self.makeStoreURL()
        let context = try Self.openMigratedStore(at: storeURL)

        context.insert(Workout(name: "First", duration: 600, steps: 900, floors: 56, source: .headphoneMotion))
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Workout>()).first?.leaderboardStatus == .eligible)
    }

    // MARK: - Helpers

    private static func makeStoreURL() -> URL {
        let directory = URL.temporaryDirectory.appending(path: "ascend-leaderboard-status-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "migration.store")
    }

    /// Writes a store in the shape the previous build left behind, then lets the container go. Two
    /// live containers on one file fight, so the seeding one never outlives this call.
    private static func seedPreviousStore(
        at url: URL,
        _ seed: (ModelContext) throws -> Void
    ) throws {
        try autoreleasepool {
            let schema = Schema(versionedSchema: AscendSchemaV5.self)
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url)
            )
            let context = ModelContext(container)
            try seed(context)
            try context.save()
        }
    }

    /// Opens the store the way a launch does: the live schema with the real plan.
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
