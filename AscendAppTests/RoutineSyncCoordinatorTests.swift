import Foundation
import SwiftData
import Testing
@testable import AscendApp

/// What the routine backup queue does when the network, the server, or an
/// operator gets in the way.
@MainActor
@Suite(.serialized)
struct RoutineSyncCoordinatorTests {
    private static let userId = "user-304"

    @Test
    func pendingRoutineUploadsAndIsMarkedSynced() async throws {
        let modelContext = try makeModelContext()
        let routine = makeRoutine()
        routine.markPendingRemoteUpsert(ownerUserId: Self.userId)
        modelContext.insert(routine)
        try modelContext.save()

        let backend = InMemoryUserRoutineBackend()
        await makeCoordinator(backend).processPendingRoutines(
            modelContext: modelContext,
            currentUserId: Self.userId
        )

        let stored = try #require(try modelContext.fetch(FetchDescriptor<Routine>()).first)
        #expect(stored.remoteSyncStatus == .synced)
        #expect(stored.lastRemoteSyncAt != nil)
        #expect(await backend.routineCount() == 1)
    }

    @Test
    func folderUploadsBeforeTheRoutineThatPointsAtIt() async throws {
        let modelContext = try makeModelContext()
        let folder = RoutineFolder(name: "Race prep")
        folder.markPendingRemoteUpsert(ownerUserId: Self.userId)
        modelContext.insert(folder)

        let routine = makeRoutine()
        routine.folderId = folder.id
        routine.markPendingRemoteUpsert(ownerUserId: Self.userId)
        modelContext.insert(routine)
        try modelContext.save()

        let backend = InMemoryUserRoutineBackend()
        await makeCoordinator(backend).processPendingRoutines(
            modelContext: modelContext,
            currentUserId: Self.userId
        )

        // A restore that saw the routine first would hold a folderId pointing at
        // nothing.
        #expect(await backend.upsertSequence() == [folder.id, routine.id])
    }

    @Test
    func uploadFailureMarksTheRoutineFailedAndRetriesOnTheNextPass() async throws {
        let modelContext = try makeModelContext()
        let routine = makeRoutine()
        routine.markPendingRemoteUpsert(ownerUserId: Self.userId)
        modelContext.insert(routine)
        try modelContext.save()

        let backend = InMemoryUserRoutineBackend(upsertError: TestBackupFailure())
        let coordinator = makeCoordinator(backend)
        await coordinator.processPendingRoutines(
            modelContext: modelContext,
            currentUserId: Self.userId
        )

        let failed = try #require(try modelContext.fetch(FetchDescriptor<Routine>()).first)
        #expect(failed.remoteSyncStatus == .failed)
        #expect(failed.lastRemoteSyncAt == nil)
        #expect(failed.lastRemoteSyncError?.isEmpty == false)

        await backend.setUpsertError(nil)
        await coordinator.processPendingRoutines(
            modelContext: modelContext,
            currentUserId: Self.userId
        )

        let synced = try #require(try modelContext.fetch(FetchDescriptor<Routine>()).first)
        #expect(synced.remoteSyncStatus == .synced)
        #expect(await backend.routineCount() == 1)
    }

    @Test
    func routinePastTheIntervalCeilingIsRejectedRatherThanRetriedForever() async throws {
        let modelContext = try makeModelContext()
        let routine = makeRoutine()
        routine.intervals = (0..<(FirestoreUserRoutineDocument.maxIntervals + 1)).map { index in
            RoutineInterval(duration: 60, intensityValue: 8, order: index)
        }
        routine.markPendingRemoteUpsert(ownerUserId: Self.userId)
        modelContext.insert(routine)
        try modelContext.save()

        let backend = InMemoryUserRoutineBackend()
        let coordinator = makeCoordinator(backend)
        await coordinator.processPendingRoutines(
            modelContext: modelContext,
            currentUserId: Self.userId
        )

        let stored = try #require(try modelContext.fetch(FetchDescriptor<Routine>()).first)
        #expect(stored.remoteSyncStatus == .rejected)
        #expect(await backend.routineCount() == 0)

        // Rejected is terminal: a second pass must not re-attempt a write the
        // server will refuse every time.
        await coordinator.processPendingRoutines(
            modelContext: modelContext,
            currentUserId: Self.userId
        )
        #expect(await backend.routineCount() == 0)
    }

    @Test
    func aLocalEditDuringTheUploadKeepsTheRoutinePending() async throws {
        let modelContext = try makeModelContext()
        let routine = makeRoutine()
        routine.markPendingRemoteUpsert(ownerUserId: Self.userId)
        modelContext.insert(routine)
        try modelContext.save()

        let backend = EditingDuringUploadBackend {
            routine.markPendingRemoteUpsert(
                ownerUserId: Self.userId,
                modifiedAt: routine.updatedAt.addingTimeInterval(3_600)
            )
        }
        await RoutineSyncCoordinator(
            remoteRepository: backend,
            operationTimeoutSeconds: 5
        ).processPendingRoutines(
            modelContext: modelContext,
            currentUserId: Self.userId
        )

        let stored = try #require(try modelContext.fetch(FetchDescriptor<Routine>()).first)
        #expect(stored.remoteSyncStatus == .pendingUpsert)
        #expect(stored.lastRemoteSyncAt == nil)
    }

    @Test("A routine deleted mid-upload is not touched again", .bug(id: 304))
    func aRoutineDeletedDuringTheUploadIsNeitherTouchedNorResurrected() async throws {
        let modelContext = try makeModelContext()
        let routine = makeRoutine()
        routine.markPendingRemoteUpsert(ownerUserId: Self.userId)
        modelContext.insert(routine)
        try modelContext.save()

        // The climber deletes the routine inside the upload window. Reading
        // `updatedAt` off the model afterwards - or marking it synced - would be
        // touching a row that no longer exists: NSObjectInaccessibleException,
        // or a deleted routine dirtied back into the pending queue.
        let backend = EditingDuringUploadBackend {
            modelContext.delete(routine)
            try? modelContext.save()
        }
        await RoutineSyncCoordinator(
            remoteRepository: backend,
            operationTimeoutSeconds: 5
        ).processPendingRoutines(
            modelContext: modelContext,
            currentUserId: Self.userId
        )

        #expect(try modelContext.fetch(FetchDescriptor<Routine>()).isEmpty)
    }

    @Test("A routine past a rules string bound is rejected, not retried forever", .bug(id: 304))
    func aRoutineWithAnOverlongNameIsRejectedAndReported() async throws {
        let modelContext = try makeModelContext()
        let routine = makeRoutine(
            name: String(repeating: "A", count: FirestoreUserRoutineDocument.maxNameLength + 5)
        )
        routine.markPendingRemoteUpsert(ownerUserId: Self.userId)
        modelContext.insert(routine)
        try modelContext.save()

        let diagnostics = RecordingDiagnostics()
        let backend = InMemoryUserRoutineBackend()
        let coordinator = RoutineSyncCoordinator(
            remoteRepository: backend,
            diagnostics: diagnostics,
            operationTimeoutSeconds: 5
        )
        await coordinator.processPendingRoutines(
            modelContext: modelContext,
            currentUserId: Self.userId
        )

        let stored = try #require(try modelContext.fetch(FetchDescriptor<Routine>()).first)
        #expect(stored.remoteSyncStatus == .rejected)
        #expect(await backend.routineCount() == 0)

        let event = try #require(diagnostics.events.first)
        #expect(event.name == "routine_backup_rejected")
        #expect(event.level == .warning)
        #expect(event.details["reason"] == "name_too_long")
        #expect(event.details["actual"] == "\(FirestoreUserRoutineDocument.maxNameLength + 5)")
        #expect(event.details["permitted"] == "\(FirestoreUserRoutineDocument.maxNameLength)")
        // The climber's own words never leave the device in a diagnostic.
        #expect(event.details.values.contains { $0.contains("AAAA") } == false)

        // Rejected is terminal: a second pass must not re-attempt a write the
        // server will refuse every time.
        await coordinator.processPendingRoutines(
            modelContext: modelContext,
            currentUserId: Self.userId
        )
        #expect(await backend.routineCount() == 0)
        #expect(diagnostics.events.count == 1)
    }

    @Test("A routine saved with nobody signed in is still backed up later", .bug(id: 304))
    func anOwnerlessRoutineIsClaimedOnALaterBootstrapAndUploaded() async throws {
        let modelContext = try makeModelContext()
        let backend = InMemoryUserRoutineBackend()
        let coordinator = makeCoordinator(backend)

        // The first bootstrap sweeps an empty store: under a one-shot adoption
        // key, everything created afterwards would be stranded for good.
        try RoutineRemoteSyncAdoptionService.runIfNeeded(
            modelContext: modelContext,
            currentUserId: Self.userId
        )

        let signedOutService = RoutineService(
            modelContext: modelContext,
            templateRepository: StubRoutineTemplateRepository(),
            syncCoordinator: coordinator,
            currentUserId: { nil }
        )
        let stranded = try signedOutService.createRoutine(
            name: "Built while signed out",
            intervals: [RoutineInterval(duration: 60, intensityValue: 8, order: 0)]
        )
        #expect(stranded.ownerUserId == nil)

        try RoutineRemoteSyncAdoptionService.runIfNeeded(
            modelContext: modelContext,
            currentUserId: Self.userId
        )
        await coordinator.processPendingRoutines(
            modelContext: modelContext,
            currentUserId: Self.userId
        )

        let claimed = try #require(try modelContext.fetch(FetchDescriptor<Routine>()).first)
        #expect(claimed.ownerUserId == Self.userId)
        #expect(claimed.remoteSyncStatus == .synced)
        #expect(await backend.uploadedRoutineIds() == [stranded.id])
    }

    @Test
    func pendingDeletionRemovesTheRemoteDocumentAndClearsTheQueue() async throws {
        let modelContext = try makeModelContext()
        let routineId = UUID()
        modelContext.insert(
            PendingRoutineDeletion(recordId: routineId, kind: .routine, ownerUserId: Self.userId)
        )
        try modelContext.save()

        let backend = InMemoryUserRoutineBackend()
        await backend.seedRoutine(routineId, document: makeRemoteDocument(name: "Doomed"))

        await makeCoordinator(backend).processPendingRoutines(
            modelContext: modelContext,
            currentUserId: Self.userId
        )

        #expect(await backend.routineCount() == 0)
        #expect(try modelContext.fetch(FetchDescriptor<PendingRoutineDeletion>()).isEmpty)
    }

    @Test
    func failedDeletionKeepsTheTombstoneSoItRetries() async throws {
        let modelContext = try makeModelContext()
        modelContext.insert(
            PendingRoutineDeletion(recordId: UUID(), kind: .routine, ownerUserId: Self.userId)
        )
        try modelContext.save()

        let backend = InMemoryUserRoutineBackend(deleteError: TestBackupFailure())
        await makeCoordinator(backend).processPendingRoutines(
            modelContext: modelContext,
            currentUserId: Self.userId
        )

        let tombstone = try #require(
            try modelContext.fetch(FetchDescriptor<PendingRoutineDeletion>()).first
        )
        #expect(tombstone.retryCount == 1)
        #expect(tombstone.lastError?.isEmpty == false)
    }

    @Test
    func aRoutineQueuedForDeletionIsNeverReUploadedInTheSamePass() async throws {
        let modelContext = try makeModelContext()
        let routine = makeRoutine()
        routine.markPendingRemoteUpsert(ownerUserId: Self.userId)
        modelContext.insert(routine)
        modelContext.insert(
            PendingRoutineDeletion(recordId: routine.id, kind: .routine, ownerUserId: Self.userId)
        )
        try modelContext.save()

        let backend = InMemoryUserRoutineBackend()
        await makeCoordinator(backend).processPendingRoutines(
            modelContext: modelContext,
            currentUserId: Self.userId
        )

        #expect(await backend.routineCount() == 0)
    }

    // MARK: - Kill switches

    @Test
    func killingBackupWritesLeavesTheRoutinePendingRatherThanFailed() async throws {
        let modelContext = try makeModelContext()
        let routine = makeRoutine()
        routine.markPendingRemoteUpsert(ownerUserId: Self.userId)
        modelContext.insert(routine)
        try modelContext.save()

        let backend = InMemoryUserRoutineBackend()
        await RoutineSyncCoordinator(
            remoteRepository: backend,
            featureFlags: makeStore(disabling: .routineCloudBackupWrites),
            operationTimeoutSeconds: 5
        ).processPendingRoutines(
            modelContext: modelContext,
            currentUserId: Self.userId
        )

        #expect(await backend.routineCount() == 0)
        let stored = try #require(try modelContext.fetch(FetchDescriptor<Routine>()).first)
        #expect(stored.remoteSyncStatus == .pendingUpsert)
        #expect(stored.lastRemoteSyncAt == nil)
    }

    @Test
    func killingRemoteDeletesKeepsTheTombstoneAndStillBlocksTheReUpload() async throws {
        let modelContext = try makeModelContext()
        let routine = makeRoutine()
        routine.markPendingRemoteUpsert(ownerUserId: Self.userId)
        modelContext.insert(routine)
        modelContext.insert(
            PendingRoutineDeletion(recordId: routine.id, kind: .routine, ownerUserId: Self.userId)
        )
        try modelContext.save()

        let backend = InMemoryUserRoutineBackend()
        await RoutineSyncCoordinator(
            remoteRepository: backend,
            featureFlags: makeStore(disabling: .routineRemoteDeletes),
            operationTimeoutSeconds: 5
        ).processPendingRoutines(
            modelContext: modelContext,
            currentUserId: Self.userId
        )

        // The delete is deferred, not dropped - and the routine it points at must
        // not be uploaded in the meantime, or the switch would resurrect it.
        #expect(try modelContext.fetch(FetchDescriptor<PendingRoutineDeletion>()).count == 1)
        #expect(await backend.routineCount() == 0)
    }

    @Test
    func killingCloudRestoreDefersHydrationRatherThanMarkingItDone() async throws {
        let modelContext = try makeModelContext()
        let backend = InMemoryUserRoutineBackend()
        await backend.seedRoutine(UUID(), document: makeRemoteDocument(name: "Waiting"))

        RoutineHydrationService.resetSessionTrackingForTesting()
        let blockedCount = try await RoutineHydrationService.hydrateIfNeeded(
            modelContext: modelContext,
            currentUserId: Self.userId,
            remoteRepository: backend,
            featureFlags: makeStore(disabling: .routineCloudRestore)
        )

        #expect(blockedCount == 0)
        #expect(try modelContext.fetch(FetchDescriptor<Routine>()).isEmpty)

        // The switch returning must still produce the initial restore.
        let restoredCount = try await RoutineHydrationService.hydrateIfNeeded(
            modelContext: modelContext,
            currentUserId: Self.userId,
            remoteRepository: backend
        )
        #expect(restoredCount == 1)
    }

    // MARK: - Helpers

    private func makeCoordinator(_ backend: InMemoryUserRoutineBackend) -> RoutineSyncCoordinator {
        RoutineSyncCoordinator(remoteRepository: backend, operationTimeoutSeconds: 5)
    }

    private func makeStore(disabling flag: RemoteFeatureFlag) -> RemoteFeatureFlagStore {
        RemoteFeatureFlagStore(
            snapshot: RemoteFeatureFlagSnapshot.resolving(remoteValues: [flag.key: false])
        )
    }

    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Routine.self,
            RoutineFolder.self,
            PendingRoutineDeletion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeRoutine(name: String = "Tuesday Pyramid") -> Routine {
        Routine(
            name: name,
            source: .userCreated,
            intervals: [RoutineInterval(duration: 120, intensityValue: 8, order: 0)]
        )
    }

    private func makeRemoteDocument(name: String) -> FirestoreUserRoutineDocument {
        FirestoreUserRoutineDocument(
            userId: Self.userId,
            name: name,
            description: "",
            source: RoutineSource.userCreated.rawValue,
            intervals: [],
            isArchived: false,
            order: 0,
            completionCount: 0,
            createdAt: Date(timeIntervalSince1970: 1_770_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_770_000_000)
        )
    }
}

private struct TestBackupFailure: Error, Sendable {}

/// Keeps what was asked for, which is the only checkable half of a diagnostic:
/// whether it reached Crashlytics cannot be observed from inside the process.
private final class RecordingDiagnostics: AppDiagnosticsRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [AppDiagnosticEvent] = []

    var events: [AppDiagnosticEvent] {
        lock.withLock { recorded }
    }

    @discardableResult
    func record(
        _ name: String,
        level: AppDiagnosticEvent.Level,
        details: [String: String],
        mirrorToCrashlytics: Bool
    ) -> AppDiagnosticEvent {
        let event = AppDiagnosticEvent(name: name, level: level, details: details)
        lock.withLock { recorded.append(event) }
        return event
    }
}

/// Runs a side effect on the main actor in the middle of an upload, so the
/// "a local edit landed while we were uploading" branch can be exercised.
private actor EditingDuringUploadBackend: UserRoutineRemoteRepositoryProtocol {
    private let onUpsert: @MainActor () -> Void

    init(onUpsert: @escaping @MainActor () -> Void) {
        self.onUpsert = onUpsert
    }

    func fetchRoutines(userId: String) async throws -> [RemoteUserRoutineRecord] { [] }
    func fetchFolders(userId: String) async throws -> [RemoteRoutineFolderRecord] { [] }

    func upsertRoutine(
        userId: String,
        routineId: UUID,
        document: FirestoreUserRoutineDocument
    ) async throws {
        await onUpsert()
    }

    func upsertFolder(
        userId: String,
        folderId: UUID,
        document: FirestoreRoutineFolderDocument
    ) async throws {}

    func deleteRoutine(userId: String, routineId: UUID) async throws {}
    func deleteFolder(userId: String, folderId: UUID) async throws {}
}
