import Foundation
import SwiftData
import Testing
@testable import AscendApp

/// Proves the V2 -> V3 stage carries an existing routine store forward instead
/// of resetting it.
///
/// Seeded through `AscendSchemaV2` on disk, not through the current models: a
/// migration tested against a store the current build just created is a
/// migration tested against a store that already has the new schema, and every
/// row it needed to fail on was never written in the old shape. The failure it
/// guards against is silent - a routine that lost its intervals reads back like
/// a routine that never had any.
@MainActor
@Suite(.serialized)
struct RoutineBackupSchemaMigrationTests {
    private static let createdAt = Date(timeIntervalSince1970: 1_760_000_000)

    @Test("An existing routine keeps everything it held", .bug(id: 304))
    func migrationPreservesRoutineContents() throws {
        let storeURL = Self.makeStoreURL()
        defer { Self.removeStore(at: storeURL) }

        let routineId = UUID()
        let folderId = UUID()
        let intervals = [
            RoutineInterval(duration: 120, intensityValue: 8, order: 0),
            RoutineInterval(
                duration: 60,
                intensityType: .stepsPerMinute,
                intensityValue: 90,
                modifiers: IntervalModifiers(sidewaysDirection: .left, skipStep: true),
                order: 1
            )
        ]

        try Self.seedV2Store(at: storeURL) { context in
            let routine = AscendSchemaV2.Routine(id: routineId, name: "Tuesday Pyramid")
            routine.routineDescription = "Build to 14, then unwind."
            routine.sourceRawValue = RoutineSource.userCreated.rawValue
            routine.createdAt = Self.createdAt
            routine.updatedAt = Self.createdAt
            routine.folderId = folderId
            routine.intervalsData = try? JSONEncoder().encode(intervals)
            routine.completionCount = 6
            routine.lastCompletedAt = Self.createdAt
            routine.difficulty = 7
            routine.order = 2
            context.insert(routine)

            let folder = AscendSchemaV2.RoutineFolder(id: folderId, name: "Race prep")
            folder.colorHex = "#86D30A"
            folder.order = 1
            folder.createdAt = Self.createdAt
            context.insert(folder)
        }

        let context = try Self.openMigratedStore(at: storeURL)

        let routine = try #require(try context.fetch(FetchDescriptor<Routine>()).first)
        #expect(routine.id == routineId)
        #expect(routine.name == "Tuesday Pyramid")
        #expect(routine.routineDescription == "Build to 14, then unwind.")
        #expect(routine.source == .userCreated)
        #expect(routine.folderId == folderId)
        #expect(routine.intervals == intervals)
        #expect(routine.completionCount == 6)
        #expect(routine.difficulty == 7)
        #expect(routine.order == 2)
        #expect(routine.createdAt == Self.createdAt)

        let folder = try #require(try context.fetch(FetchDescriptor<RoutineFolder>()).first)
        #expect(folder.id == folderId)
        #expect(folder.name == "Race prep")
        #expect(folder.colorHex == "#86D30A")
        #expect(folder.order == 1)
    }

    @Test("Every migrated routine still owes its first upload", .bug(id: 304))
    func migratedRoutinesArrivePendingWithNoOwner() throws {
        let storeURL = Self.makeStoreURL()
        defer { Self.removeStore(at: storeURL) }

        try Self.seedV2Store(at: storeURL) { context in
            let routine = AscendSchemaV2.Routine(id: UUID(), name: "Built before the backup")
            routine.sourceRawValue = RoutineSource.userCreated.rawValue
            routine.createdAt = Self.createdAt
            routine.updatedAt = Self.createdAt
            context.insert(routine)
            context.insert(AscendSchemaV2.RoutineFolder(id: UUID(), name: "Race prep"))
        }

        let context = try Self.openMigratedStore(at: storeURL)

        // The blanket default has to be honest: a routine written before the
        // backup existed really does still need its first upload. `synced`
        // would have been a lie that silently skipped it forever.
        let routine = try #require(try context.fetch(FetchDescriptor<Routine>()).first)
        #expect(routine.remoteSyncStatus == .pendingUpsert)
        #expect(routine.ownerUserId == nil)
        #expect(routine.lastRemoteSyncAt == nil)

        let folder = try #require(try context.fetch(FetchDescriptor<RoutineFolder>()).first)
        #expect(folder.remoteSyncStatus == .pendingUpsert)
        #expect(folder.ownerUserId == nil)
        // Never edited, so there is no honest last-modified date but its own
        // creation date.
        #expect(folder.updatedAt == nil)
        #expect(folder.effectiveUpdatedAt == folder.createdAt)
    }

    @Test("Sign-in claims routines that predate the backup so they actually upload", .bug(id: 304))
    func adoptionClaimsUnownedUserRoutinesButNotTemplates() throws {
        let storeURL = Self.makeStoreURL()
        defer { Self.removeStore(at: storeURL) }

        let userRoutineId = UUID()
        let templateId = UUID()

        try Self.seedV2Store(at: storeURL) { context in
            let userRoutine = AscendSchemaV2.Routine(id: userRoutineId, name: "Mine")
            userRoutine.sourceRawValue = RoutineSource.userCreated.rawValue
            userRoutine.updatedAt = Self.createdAt
            context.insert(userRoutine)

            let template = AscendSchemaV2.Routine(id: templateId, name: "Pyramid Climb")
            template.sourceRawValue = RoutineSource.remoteTemplate.rawValue
            template.templateId = "pyramid_climb"
            context.insert(template)
        }

        let context = try Self.openMigratedStore(at: storeURL)
        let defaults = UserDefaults(suiteName: "routine-adoption-\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        try RoutineRemoteSyncAdoptionService.runIfNeeded(
            modelContext: context,
            currentUserId: "user-304",
            userDefaults: defaults
        )

        let routines = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<Routine>()).map { ($0.id, $0) }
        )
        #expect(routines[userRoutineId]?.ownerUserId == "user-304")
        // The catalog is server-owned content; claiming it would upload our own
        // published routines back to us under the climber's uid.
        #expect(routines[templateId]?.ownerUserId == nil)
        // The adoption keeps the existing timestamp, so a stale local copy
        // cannot outrank a newer backup on a second device.
        #expect(routines[userRoutineId]?.updatedAt == Self.createdAt)
    }

    @Test
    func anEmptyStoreStillMigrates() throws {
        let storeURL = Self.makeStoreURL()
        defer { Self.removeStore(at: storeURL) }

        try Self.seedV2Store(at: storeURL) { _ in }

        let context = try Self.openMigratedStore(at: storeURL)

        #expect(try context.fetch(FetchDescriptor<Routine>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PendingRoutineDeletion>()).isEmpty)
    }

    // MARK: - Store plumbing

    private static func makeStoreURL() -> URL {
        URL.temporaryDirectory.appending(path: "routine-migration-\(UUID().uuidString).store")
    }

    private static func removeStore(at url: URL) {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(
                at: url.deletingLastPathComponent()
                    .appending(path: url.lastPathComponent + suffix)
            )
        }
    }

    /// Writes rows through the schema that shipped before this change, then lets
    /// the container go. Two live containers on one file fight.
    private static func seedV2Store(
        at url: URL,
        seed: (ModelContext) throws -> Void
    ) throws {
        let schema = Schema(versionedSchema: AscendSchemaV2.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: url)
        )
        let context = ModelContext(container)
        try seed(context)
        try context.save()
    }

    private static func openMigratedStore(at url: URL) throws -> ModelContext {
        let schema = Schema(versionedSchema: AscendSchemaV3.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AscendMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url)
        )
        return ModelContext(container)
    }
}
