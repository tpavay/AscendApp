import Foundation
import SwiftData
import Testing
@testable import AscendApp

/// The answer to "what happens when the local copy and the cloud copy
/// disagree", pinned so it cannot drift.
///
/// Ascend is local-first, so an unsent local edit always outranks the backup,
/// and the backup only wins when the local record owes nothing and the remote
/// copy is genuinely newer.
@MainActor
@Suite(.serialized)
struct RoutineHydrationServiceTests {
    private static let userId = "user-304"
    private static let earlier = Date(timeIntervalSince1970: 1_770_000_000)
    private static let later = Date(timeIntervalSince1970: 1_770_086_400)

    @Test
    func aNewerBackupWinsOverASyncedLocalCopy() async throws {
        let modelContext = try makeModelContext()
        let routine = makeLocalRoutine(name: "Old name", updatedAt: Self.earlier)
        routine.markRemoteSyncSucceeded()
        modelContext.insert(routine)
        try modelContext.save()

        let backend = InMemoryUserRoutineBackend()
        await backend.seedRoutine(
            routine.id,
            document: makeDocument(name: "Renamed on the other phone", updatedAt: Self.later)
        )

        RoutineHydrationService.resetSessionTrackingForTesting()
        _ = try await RoutineHydrationService.hydrateIfNeeded(
            modelContext: modelContext,
            currentUserId: Self.userId,
            remoteRepository: backend
        )

        let stored = try #require(try modelContext.fetch(FetchDescriptor<Routine>()).first)
        #expect(stored.name == "Renamed on the other phone")
    }

    @Test
    func anOlderBackupDoesNotOverwriteASyncedLocalCopy() async throws {
        let modelContext = try makeModelContext()
        let routine = makeLocalRoutine(name: "Current name", updatedAt: Self.later)
        routine.markRemoteSyncSucceeded()
        modelContext.insert(routine)
        try modelContext.save()

        let backend = InMemoryUserRoutineBackend()
        await backend.seedRoutine(
            routine.id,
            document: makeDocument(name: "Stale backup", updatedAt: Self.earlier)
        )

        RoutineHydrationService.resetSessionTrackingForTesting()
        _ = try await RoutineHydrationService.hydrateIfNeeded(
            modelContext: modelContext,
            currentUserId: Self.userId,
            remoteRepository: backend
        )

        let stored = try #require(try modelContext.fetch(FetchDescriptor<Routine>()).first)
        #expect(stored.name == "Current name")
    }

    @Test("An edit that has not been uploaded yet is never overwritten by the backup", .bug(id: 304))
    func aPendingLocalEditSurvivesEvenANewerBackup() async throws {
        let modelContext = try makeModelContext()
        let routine = makeLocalRoutine(name: "Edited on the plane", updatedAt: Self.earlier)
        routine.markPendingRemoteUpsert(ownerUserId: Self.userId, modifiedAt: Self.earlier)
        modelContext.insert(routine)
        try modelContext.save()

        let backend = InMemoryUserRoutineBackend()
        await backend.seedRoutine(
            routine.id,
            document: makeDocument(name: "Server copy", updatedAt: Self.later)
        )

        RoutineHydrationService.resetSessionTrackingForTesting()
        _ = try await RoutineHydrationService.hydrateIfNeeded(
            modelContext: modelContext,
            currentUserId: Self.userId,
            remoteRepository: backend
        )

        // The local copy still owes an upload, so it is the newer of the two as
        // far as this device knows. Taking the server copy would throw away work
        // the climber did offline.
        let stored = try #require(try modelContext.fetch(FetchDescriptor<Routine>()).first)
        #expect(stored.name == "Edited on the plane")
        #expect(stored.remoteSyncStatus == .pendingUpsert)
    }

    @Test
    func aFailedUploadIsAlsoTreatedAsAnUnsentLocalEdit() async throws {
        let modelContext = try makeModelContext()
        let routine = makeLocalRoutine(name: "Failed to upload", updatedAt: Self.earlier)
        routine.markPendingRemoteUpsert(ownerUserId: Self.userId, modifiedAt: Self.earlier)
        routine.markRemoteSyncFailed("network down")
        modelContext.insert(routine)
        try modelContext.save()

        let backend = InMemoryUserRoutineBackend()
        await backend.seedRoutine(
            routine.id,
            document: makeDocument(name: "Server copy", updatedAt: Self.later)
        )

        RoutineHydrationService.resetSessionTrackingForTesting()
        _ = try await RoutineHydrationService.hydrateIfNeeded(
            modelContext: modelContext,
            currentUserId: Self.userId,
            remoteRepository: backend
        )

        let stored = try #require(try modelContext.fetch(FetchDescriptor<Routine>()).first)
        #expect(stored.name == "Failed to upload")
    }

    @Test
    func aRoutineQueuedForDeletionIsNotResurrectedByTheBackup() async throws {
        let modelContext = try makeModelContext()
        let routineId = UUID()
        modelContext.insert(
            PendingRoutineDeletion(recordId: routineId, kind: .routine, ownerUserId: Self.userId)
        )
        try modelContext.save()

        let backend = InMemoryUserRoutineBackend()
        await backend.seedRoutine(
            routineId,
            document: makeDocument(name: "Deleted offline", updatedAt: Self.later)
        )

        RoutineHydrationService.resetSessionTrackingForTesting()
        _ = try await RoutineHydrationService.hydrateIfNeeded(
            modelContext: modelContext,
            currentUserId: Self.userId,
            remoteRepository: backend
        )

        #expect(try modelContext.fetch(FetchDescriptor<Routine>()).isEmpty)
    }

    @Test
    func hydrationNeverDeletesALocalRoutineTheBackupHasNotSeenYet() async throws {
        let modelContext = try makeModelContext()
        let routine = makeLocalRoutine(name: "Built five minutes ago", updatedAt: Self.later)
        routine.markPendingRemoteUpsert(ownerUserId: Self.userId, modifiedAt: Self.later)
        modelContext.insert(routine)
        try modelContext.save()

        RoutineHydrationService.resetSessionTrackingForTesting()
        _ = try await RoutineHydrationService.hydrateIfNeeded(
            modelContext: modelContext,
            currentUserId: Self.userId,
            remoteRepository: InMemoryUserRoutineBackend()
        )

        #expect(try modelContext.fetch(FetchDescriptor<Routine>()).count == 1)
    }

    @Test
    func hydrationIsIdempotentWithinASession() async throws {
        let modelContext = try makeModelContext()
        let backend = InMemoryUserRoutineBackend()
        await backend.seedRoutine(UUID(), document: makeDocument(name: "Restored", updatedAt: Self.earlier))

        RoutineHydrationService.resetSessionTrackingForTesting()
        let first = try await RoutineHydrationService.hydrateIfNeeded(
            modelContext: modelContext,
            currentUserId: Self.userId,
            remoteRepository: backend
        )
        let second = try await RoutineHydrationService.hydrateIfNeeded(
            modelContext: modelContext,
            currentUserId: Self.userId,
            remoteRepository: backend
        )

        #expect(first == 1)
        #expect(second == 0)
        #expect(try modelContext.fetch(FetchDescriptor<Routine>()).count == 1)
    }

    @Test
    func aBackupThatCannotBeDecodedCostsOnlyThatRoutine() throws {
        let repository = FirestoreUserRoutineRemoteRepository.shared
        let goodId = UUID()
        let records = repository.decodeRoutineRecords(from: [
            (id: goodId.uuidString, data: rawRoutineData(name: "Readable")),
            (id: UUID().uuidString, data: rawRoutineData(name: "Broken", dropping: "createdAt"))
        ])

        #expect(records.count == 1)
        #expect(records.first?.routineId == goodId)
        #expect(records.first?.document.name == "Readable")
    }

    // MARK: - Helpers

    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Routine.self,
            RoutineFolder.self,
            PendingRoutineDeletion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeLocalRoutine(name: String, updatedAt: Date) -> Routine {
        let routine = Routine(name: name, source: .userCreated)
        routine.ownerUserId = Self.userId
        routine.createdAt = Self.earlier
        routine.updatedAt = updatedAt
        return routine
    }

    private func makeDocument(name: String, updatedAt: Date) -> FirestoreUserRoutineDocument {
        FirestoreUserRoutineDocument(
            userId: Self.userId,
            name: name,
            description: "",
            source: RoutineSource.userCreated.rawValue,
            intervals: [],
            isArchived: false,
            order: 0,
            completionCount: 0,
            createdAt: Self.earlier,
            updatedAt: updatedAt
        )
    }

    private func rawRoutineData(name: String, dropping field: String? = nil) -> [String: Any] {
        var data: [String: Any] = [
            "userId": Self.userId,
            "schemaVersion": 1,
            "name": name,
            "description": "",
            "source": RoutineSource.userCreated.rawValue,
            "intervals": [],
            "isArchived": false,
            "order": 0,
            "completionCount": 0,
            "createdAt": Self.earlier,
            "updatedAt": Self.later
        ]
        if let field {
            data[field] = nil
        }
        return data
    }
}
