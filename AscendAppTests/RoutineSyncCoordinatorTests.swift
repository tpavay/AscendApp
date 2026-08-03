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

    @Test("A copied template's bad metadata is repaired and reported, not rejected", .bug(id: 304))
    func aRoutineCarryingOutOfBoundsCatalogMetadataUploadsRepaired() async throws {
        let modelContext = try makeModelContext()
        let template = Routine(
            name: "Pyramid Climb",
            source: .remoteTemplate,
            intervals: [RoutineInterval(duration: 120, intensityValue: 8, order: 0)],
            templateId: "pyramid_climb",
            difficulty: FirestoreUserRoutineDocument.maxDifficulty + 5,
            estimatedCalories: -40
        )
        let copy = template.createUserCopy()
        copy.markPendingRemoteUpsert(ownerUserId: Self.userId)
        modelContext.insert(copy)
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
        #expect(stored.remoteSyncStatus == .synced)

        let uploaded = try #require(await backend.routineDocument(copy.id))
        #expect(uploaded.difficulty == FirestoreUserRoutineDocument.maxDifficulty)
        #expect(uploaded.estimatedCalories == 0)

        // The repair converges: the local record holds the repaired values too,
        // so local and backup agree from here on.
        #expect(stored.difficulty == FirestoreUserRoutineDocument.maxDifficulty)
        #expect(stored.estimatedCalories == 0)

        // A value we published being out of bounds is ours to see, so a repair is
        // reported as loudly as a refusal - and never quotes what the climber wrote.
        #expect(diagnostics.events.allSatisfy { $0.name == "routine_backup_repaired" })
        #expect(
            Set(diagnostics.events.compactMap { $0.details["reason"] }) ==
                ["difficulty_clamped", "estimated_calories_clamped"]
        )
        #expect(diagnostics.events.allSatisfy { $0.level == .warning })
        #expect(
            diagnostics.events.contains { event in
                event.details["actual"] == "\(FirestoreUserRoutineDocument.maxDifficulty + 5)" &&
                    event.details["applied"] == "\(FirestoreUserRoutineDocument.maxDifficulty)"
            }
        )
        #expect(
            diagnostics.events.contains { $0.details.values.contains("Pyramid Climb (Copy)") } == false
        )

        // A condition that will never change must not be reported forever. The
        // climber runs this routine three times a week; every completion marks it
        // pending again, and a repair re-detected on each pass would mirror to
        // Crashlytics every time and evict real rejections from the shared ring
        // buffer. Converging is what stops it.
        let reportedOnce = diagnostics.events.count
        stored.markPendingRemoteUpsert(ownerUserId: Self.userId)
        try modelContext.save()

        await coordinator.processPendingRoutines(
            modelContext: modelContext,
            currentUserId: Self.userId
        )

        #expect(diagnostics.events.count == reportedOnce)
        #expect(await backend.routineDocument(copy.id)?.difficulty == uploaded.difficulty)
        #expect(await backend.routineDocument(copy.id)?.estimatedCalories == uploaded.estimatedCalories)
    }

    /// The upload-only side of the rule, through the production path. The drop
    /// must not reach the store: `savedCopy(templateId:)` matches on the local id,
    /// so nulling it would make the catalog Save toggle read unsaved after every
    /// backup and mint another copy on every tap.
    @Test("A dropped templateId never reaches the local record", .bug(id: 304))
    func anOverlongTemplateIdIsDroppedFromTheUploadButKeptLocally() async throws {
        let modelContext = try makeModelContext()
        let overlongId = String(
            repeating: "t",
            count: FirestoreUserRoutineDocument.maxTemplateIdLength + 1
        )
        let routine = Routine(
            name: "Copied",
            source: .copiedFromBuiltin,
            intervals: [RoutineInterval(duration: 120, intensityValue: 8, order: 0)],
            templateId: overlongId,
            templateVersion: -2
        )
        routine.markPendingRemoteUpsert(ownerUserId: Self.userId)
        modelContext.insert(routine)
        try modelContext.save()

        let backend = InMemoryUserRoutineBackend()
        await makeCoordinator(backend).processPendingRoutines(
            modelContext: modelContext,
            currentUserId: Self.userId
        )

        let uploaded = try #require(await backend.routineDocument(routine.id))
        #expect(uploaded.templateId == nil)
        #expect(uploaded.templateVersion == 0)

        let stored = try #require(try modelContext.fetch(FetchDescriptor<Routine>()).first)
        #expect(stored.remoteSyncStatus == .synced)
        #expect(stored.templateId == overlongId)
        #expect(stored.templateVersion == -2)
    }

    /// The other side of the rule from the test above. A colour is the climber's
    /// pick, so it is refused rather than rewritten: the folder stays `.rejected`
    /// and keeps the colour they chose, where dropping it would have deleted a
    /// choice they can see the moment the backup succeeded.
    @Test("A folder colour the rules refuse is rejected, never rewritten", .bug(id: 304))
    func aFolderWithAnUnusableColourIsRejectedWithItsColourIntact() async throws {
        let modelContext = try makeModelContext()
        let folder = RoutineFolder(name: "Race prep", colorHex: "lime")
        folder.markPendingRemoteUpsert(ownerUserId: Self.userId)
        modelContext.insert(folder)
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

        let stored = try #require(try modelContext.fetch(FetchDescriptor<RoutineFolder>()).first)
        #expect(stored.remoteSyncStatus == .rejected)
        #expect(stored.colorHex == "lime")
        #expect(await backend.folderCount() == 0)

        let event = try #require(diagnostics.events.first)
        #expect(event.name == "routine_backup_rejected")
        #expect(event.details["reason"] == "unusable_folder_color")
        #expect(event.details["record_kind"] == "routine_folder")
        #expect(event.details["permitted"] == FirestoreRoutineFolderDocument.colorHexPattern)
        #expect(event.details.values.contains("lime") == false)

        // Rejected is terminal: a second pass must not re-attempt a write the
        // server will refuse every time.
        await coordinator.processPendingRoutines(
            modelContext: modelContext,
            currentUserId: Self.userId
        )
        #expect(await backend.folderCount() == 0)
        #expect(diagnostics.events.count == 1)
    }

    /// Parked, not deleted, and not hidden - see issue #362.
    ///
    /// This fails about half the time under the documented `xcodebuild ... test`
    /// command (4 failures in 8 unmodified runs on a dedicated simulator with no
    /// lane contention), passes 846/846 with `-parallel-testing-enabled NO`, and
    /// passes when the suite runs alone.
    ///
    /// What is established: the routine IS adopted and the upload DOES happen,
    /// but `lastRemoteSyncAt` and `lastRemoteSyncError` both stay nil. The write
    /// is lost *inside* `markRoutineSynced`, immediately after `save()`, and does
    /// not stick even on retry - `save()` is discarding the change to that
    /// object. Refuted along the way: that cross-suite in-memory containers share
    /// a store (separate containers see zero of each other's rows), that unique
    /// in-memory configuration names separate them (every in-memory store is
    /// `file:///dev/null`, so a name cannot), and that unique on-disk URLs fix it
    /// (they do not). This suite is already `.serialized`, so within-suite
    /// parallelism is not the cause.
    ///
    /// It is `.disabled` rather than removed because it is the only proof the
    /// ownerless-routine adoption path works, and its assertions are the point.
    /// Serialising the suite or disabling parallel testing to make it pass is
    /// explicitly not the answer: that hides the defect for the next test to hit.
    /// Re-enable it with the cause fixed, proven over at least 8 unmodified runs.
    @Test(
        "A routine saved with nobody signed in is still backed up later",
        .bug(id: 304),
        .bug(id: 362),
        .disabled("Known-intermittent under parallel testing - see issue #362")
    )
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
