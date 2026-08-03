import Foundation
import SwiftData

/// Owns every pending piece of remote work for user-authored routines and
/// folders.
///
/// Deliberately the same shape as `WorkoutSyncCoordinator` rather than a second
/// pattern: mutations never write to Firestore themselves, they mark the local
/// record pending and kick this, which is what makes the backup survive a cold
/// launch, an offline stretch, or a crash mid-write. Deletes run before
/// upserts so a routine queued for deletion is never re-uploaded first.
@MainActor
final class RoutineSyncCoordinator {
    static let shared = RoutineSyncCoordinator()

    private let remoteRepository: any UserRoutineRemoteRepositoryProtocol
    private let featureFlags: RemoteFeatureFlagStore
    private let diagnostics: any AppDiagnosticsRecording
    private let operationTimeoutSeconds: Double
    private var isProcessing = false
    private var shouldProcessAgain = false

    init(
        remoteRepository: any UserRoutineRemoteRepositoryProtocol = FirestoreUserRoutineRemoteRepository.shared,
        featureFlags: RemoteFeatureFlagStore = .shared,
        diagnostics: any AppDiagnosticsRecording = AppDiagnosticsRecorder.shared,
        operationTimeoutSeconds: Double = 15.0
    ) {
        self.remoteRepository = remoteRepository
        self.featureFlags = featureFlags
        self.diagnostics = diagnostics
        self.operationTimeoutSeconds = operationTimeoutSeconds
    }

    /// Queues the remote half of a local delete.
    ///
    /// Returns whether anything was queued so the caller can decide to save.
    /// A record with no owner has never been backed up, so there is nothing
    /// remote to remove and no row is written.
    @discardableResult
    func enqueuePendingDeletion(
        recordId: UUID,
        kind: PendingRoutineDeletionKind,
        ownerUserId: String?,
        modelContext: ModelContext
    ) throws -> Bool {
        guard let ownerUserId, !ownerUserId.isEmpty else { return false }

        let kindRawValue = kind.rawValue
        let descriptor = FetchDescriptor<PendingRoutineDeletion>(
            predicate: #Predicate<PendingRoutineDeletion> { deletion in
                deletion.recordId == recordId &&
                    deletion.kindRawValue == kindRawValue &&
                    deletion.ownerUserId == ownerUserId
            }
        )
        guard try modelContext.fetch(descriptor).isEmpty else { return false }

        modelContext.insert(
            PendingRoutineDeletion(
                recordId: recordId,
                kind: kind,
                ownerUserId: ownerUserId
            )
        )
        return true
    }

    func processPendingRoutines(
        modelContext: ModelContext,
        currentUserId: String
    ) async {
        if isProcessing {
            shouldProcessAgain = true
            return
        }

        repeat {
            isProcessing = true
            shouldProcessAgain = false

            do {
                let excludedRecordIds = try await processPendingDeletions(
                    modelContext: modelContext,
                    currentUserId: currentUserId
                )

                // Killed: routines and folders stay flagged pending in SwiftData
                // and go up on the next pass once the flag returns. Nothing is
                // marked synced or failed in the meantime.
                if backupsAreEnabled {
                    try await uploadPendingFolders(
                        modelContext: modelContext,
                        currentUserId: currentUserId,
                        excludedIds: excludedRecordIds
                    )
                    try await uploadPendingRoutines(
                        modelContext: modelContext,
                        currentUserId: currentUserId,
                        excludedIds: excludedRecordIds
                    )
                }
            } catch {
                recordFailure(error, code: "routine_sync_failed", recordId: nil)
            }

            isProcessing = false
        } while shouldProcessAgain
    }
}

private extension RoutineSyncCoordinator {
    /// Everything one upload needs, read off the model *before* the await.
    ///
    /// The same discipline `WorkoutSyncCoordinator` keeps, and for the same
    /// reason: an upload can take up to fifteen seconds, the climber can delete
    /// the routine inside that window, and touching a model whose row is gone
    /// raises `NSObjectInaccessibleException`. The resume path re-fetches by id
    /// and owner instead, and does nothing at all when the row has gone.
    struct RoutineUploadSnapshot: Sendable {
        let routineId: UUID
        let userId: String
        let expectedModifiedAt: Date
        let document: FirestoreUserRoutineDocument
        let repairs: [RoutineSyncRepair]
    }

    /// How the backup can see a folder a routine is filed under.
    enum FolderBackupState: Equatable {
        case backedUp
        case awaitingUpload
    }

    struct FolderUploadSnapshot: Sendable {
        let folderId: UUID
        let userId: String
        let expectedModifiedAt: Date
        let document: FirestoreRoutineFolderDocument
    }

    var backupsAreEnabled: Bool {
        RemoteFeatureGate.allows(
            .routineCloudBackupWrites,
            path: "RoutineSyncCoordinator.processPendingRoutines",
            store: featureFlags
        )
    }

    /// Folders go up before the routines that point at them, which is what makes
    /// the ordinary case land in the right order on a restore.
    ///
    /// Ordering alone does not carry the invariant, though, and the two ways it
    /// fails need opposite answers. A folder refused for an unusable name or
    /// colour never arrives at all, so its routines upload with the pointer
    /// omitted. A folder whose upload merely failed has not arrived yet, so its
    /// routines wait for a later pass instead. Both live in
    /// `loadPendingRoutineSnapshots`.
    func uploadPendingFolders(
        modelContext: ModelContext,
        currentUserId: String,
        excludedIds: Set<UUID>
    ) async throws {
        let snapshots = try loadPendingFolderSnapshots(
            modelContext: modelContext,
            currentUserId: currentUserId,
            excludedIds: excludedIds
        )

        for snapshot in snapshots {
            do {
                try await withRemoteSyncTimeout(seconds: operationTimeoutSeconds) {
                    try await self.remoteRepository.upsertFolder(
                        userId: snapshot.userId,
                        folderId: snapshot.folderId,
                        document: snapshot.document
                    )
                }
                try markFolderSynced(snapshot, modelContext: modelContext)
            } catch {
                recordFailure(error, code: "routine_folder_sync_failed", recordId: snapshot.folderId)
                try? markFolderFailed(
                    snapshot,
                    errorMessage: error.localizedDescription,
                    modelContext: modelContext
                )
            }
        }
    }

    func uploadPendingRoutines(
        modelContext: ModelContext,
        currentUserId: String,
        excludedIds: Set<UUID>
    ) async throws {
        let snapshots = try loadPendingRoutineSnapshots(
            modelContext: modelContext,
            currentUserId: currentUserId,
            excludedIds: excludedIds
        )

        for snapshot in snapshots {
            do {
                try await withRemoteSyncTimeout(seconds: operationTimeoutSeconds) {
                    try await self.remoteRepository.upsertRoutine(
                        userId: snapshot.userId,
                        routineId: snapshot.routineId,
                        document: snapshot.document
                    )
                }
                try markRoutineSynced(snapshot, modelContext: modelContext)
            } catch {
                recordFailure(error, code: "routine_sync_failed", recordId: snapshot.routineId)
                try? markRoutineFailed(
                    snapshot,
                    errorMessage: error.localizedDescription,
                    modelContext: modelContext
                )
            }
        }
    }

    /// Builds the upload list, and takes the records the server would refuse
    /// out of it for good.
    ///
    /// A routine past a bound in `firestore.rules` on the climber's own work -
    /// too many intervals, a name or description past its ceiling, a catalog
    /// template that should never have been queued - is `rejected` rather than
    /// retried on every launch forever, and says so through the diagnostics
    /// recorder. Retrying a permanent refusal is the worst shape available: the
    /// routine stays unbacked and nothing ever says why. A bound on metadata
    /// Ascend published is repaired instead, and reported the same way.
    ///
    /// A routine whose folder has not reached the backup *yet* - the folder is
    /// still queued, its last upload failed, or it is ownerless and waiting for
    /// adoption to claim it - is left out of this pass entirely. It stays pending
    /// and goes up on a later pass with its `folderId` intact, which is
    /// self-healing and needs no record of what was deferred. Uploading it now
    /// would file it under nothing permanently: the routine would go `synced` and
    /// nothing re-marks it when the folder lands. `folderBackupStates` owns which
    /// conditions are late and which are terminal.
    ///
    /// This is deliberately *not* "hold a routine back until its folder is
    /// backed up". Holding one behind a folder that will never arrive trades a
    /// dangling pointer for a routine that is never backed up at all, which is
    /// the failure this whole change exists to end. Holding it only behind a
    /// folder that *will* arrive is a different thing. Do not collapse the two.
    func loadPendingRoutineSnapshots(
        modelContext: ModelContext,
        currentUserId: String,
        excludedIds: Set<UUID>
    ) throws -> [RoutineUploadSnapshot] {
        var snapshots: [RoutineUploadSnapshot] = []
        let folderStates = try folderBackupStates(
            modelContext: modelContext,
            currentUserId: currentUserId,
            excludedIds: excludedIds
        )
        let backedUpFolderIds = Set(
            folderStates.filter { $0.value == .backedUp }.keys
        )

        for routine in try pendingRoutines(modelContext: modelContext, currentUserId: currentUserId)
        where !excludedIds.contains(routine.id) {
            if let folderId = routine.folderId, folderStates[folderId] == .awaitingUpload {
                continue
            }

            do {
                let build = try RoutineRemoteSyncMapper.build(
                    for: routine,
                    backedUpFolderIds: backedUpFolderIds
                )
                snapshots.append(
                    RoutineUploadSnapshot(
                        routineId: routine.id,
                        userId: currentUserId,
                        expectedModifiedAt: routine.updatedAt,
                        document: build.document,
                        repairs: build.repairs
                    )
                )
            } catch {
                routine.markRemoteSyncRejected(error.localizedDescription)
                recordRejection(error, kind: "routine", recordId: routine.id)
                try modelContext.save()
            }
        }

        return snapshots
    }

    func loadPendingFolderSnapshots(
        modelContext: ModelContext,
        currentUserId: String,
        excludedIds: Set<UUID>
    ) throws -> [FolderUploadSnapshot] {
        var snapshots: [FolderUploadSnapshot] = []

        for folder in try pendingFolders(modelContext: modelContext, currentUserId: currentUserId)
        where !excludedIds.contains(folder.id) {
            do {
                snapshots.append(
                    FolderUploadSnapshot(
                        folderId: folder.id,
                        userId: currentUserId,
                        expectedModifiedAt: folder.effectiveUpdatedAt,
                        document: try RoutineRemoteSyncMapper.document(for: folder)
                    )
                )
            } catch {
                folder.markRemoteSyncRejected(error.localizedDescription)
                recordRejection(error, kind: "routine_folder", recordId: folder.id)
                try modelContext.save()
            }
        }

        return snapshots
    }

    /// A local edit that landed during the upload keeps the record pending, so
    /// the newer content is not reported as backed up.
    ///
    /// A converged repair is written back onto the local record here, in the same
    /// transaction as the bookkeeping. Repairing only the outgoing document leaves
    /// the local record holding the out-of-range value for the life of the
    /// install, so local and backup disagree permanently and every later pass
    /// re-detects and re-reports the identical repair - which `RoutineSyncRepair`
    /// accepts for the two fields something local reads as a key, and not for the
    /// two it does not.
    func markRoutineSynced(
        _ snapshot: RoutineUploadSnapshot,
        modelContext: ModelContext
    ) throws {
        guard let routine = try Self.fetchRoutine(
            routineId: snapshot.routineId,
            userId: snapshot.userId,
            modelContext: modelContext
        ) else { return }
        guard routine.updatedAt <= snapshot.expectedModifiedAt else { return }

        RoutineRemoteSyncMapper.applyRepairs(snapshot.repairs, to: routine)
        routine.markRemoteSyncSucceeded()
        try modelContext.save()

        recordRepairs(snapshot.repairs, kind: "routine", recordId: snapshot.routineId)
    }

    func markRoutineFailed(
        _ snapshot: RoutineUploadSnapshot,
        errorMessage: String,
        modelContext: ModelContext
    ) throws {
        guard let routine = try Self.fetchRoutine(
            routineId: snapshot.routineId,
            userId: snapshot.userId,
            modelContext: modelContext
        ) else { return }
        guard routine.updatedAt <= snapshot.expectedModifiedAt else { return }

        routine.markRemoteSyncFailed(errorMessage)
        try modelContext.save()
    }

    func markFolderSynced(
        _ snapshot: FolderUploadSnapshot,
        modelContext: ModelContext
    ) throws {
        guard let folder = try Self.fetchFolder(
            folderId: snapshot.folderId,
            userId: snapshot.userId,
            modelContext: modelContext
        ) else { return }
        guard folder.effectiveUpdatedAt <= snapshot.expectedModifiedAt else { return }

        folder.markRemoteSyncSucceeded()
        try modelContext.save()
    }

    func markFolderFailed(
        _ snapshot: FolderUploadSnapshot,
        errorMessage: String,
        modelContext: ModelContext
    ) throws {
        guard let folder = try Self.fetchFolder(
            folderId: snapshot.folderId,
            userId: snapshot.userId,
            modelContext: modelContext
        ) else { return }
        guard folder.effectiveUpdatedAt <= snapshot.expectedModifiedAt else { return }

        folder.markRemoteSyncFailed(errorMessage)
        try modelContext.save()
    }

    static func fetchRoutine(
        routineId: UUID,
        userId: String,
        modelContext: ModelContext
    ) throws -> Routine? {
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate<Routine> { routine in
                routine.id == routineId && routine.ownerUserId == userId
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    static func fetchFolder(
        folderId: UUID,
        userId: String,
        modelContext: ModelContext
    ) throws -> RoutineFolder? {
        let descriptor = FetchDescriptor<RoutineFolder>(
            predicate: #Predicate<RoutineFolder> { folder in
                folder.id == folderId && folder.ownerUserId == userId
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    /// Runs every queued remote delete and returns the record ids the upload
    /// pass must skip.
    ///
    /// That set is deliberately wider than "successfully deleted": a delete
    /// that failed, and a delete the kill switch deferred, both leave a record
    /// the climber has already thrown away. Re-uploading it in the same pass
    /// would resurrect it.
    func processPendingDeletions(
        modelContext: ModelContext,
        currentUserId: String
    ) async throws -> Set<UUID> {
        // Killed: the `PendingRoutineDeletion` rows survive untouched and replay
        // once the flag is back on. Returning no deleted ids is safe because the
        // upload passes read those same rows themselves, so a record awaiting
        // deletion is still excluded.
        guard RemoteFeatureGate.allows(
            .routineRemoteDeletes,
            path: "RoutineSyncCoordinator.processPendingDeletions",
            store: featureFlags
        ) else {
            return try pendingDeletionRecordIds(
                modelContext: modelContext,
                currentUserId: currentUserId
            )
        }

        var excludedRecordIds: Set<UUID> = []

        for pendingDeletion in try pendingDeletions(
            modelContext: modelContext,
            currentUserId: currentUserId
        ) {
            let recordId = pendingDeletion.recordId
            let kind = pendingDeletion.kind

            do {
                try await withRemoteSyncTimeout(seconds: operationTimeoutSeconds) {
                    switch kind {
                    case .routine:
                        try await self.remoteRepository.deleteRoutine(
                            userId: currentUserId,
                            routineId: recordId
                        )
                    case .folder:
                        try await self.remoteRepository.deleteFolder(
                            userId: currentUserId,
                            folderId: recordId
                        )
                    }
                }
                excludedRecordIds.insert(recordId)
                modelContext.delete(pendingDeletion)
            } catch {
                recordFailure(error, code: "routine_delete_failed", recordId: recordId)
                pendingDeletion.recordFailure(error.localizedDescription)
                excludedRecordIds.insert(recordId)
            }

            try modelContext.save()
        }

        return excludedRecordIds
    }

    func pendingRoutines(
        modelContext: ModelContext,
        currentUserId: String
    ) throws -> [Routine] {
        let pendingRawValue = RoutineRemoteSyncStatus.pendingUpsert.rawValue
        let failedRawValue = RoutineRemoteSyncStatus.failed.rawValue
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate<Routine> { routine in
                routine.ownerUserId == currentUserId &&
                    (
                        routine.remoteSyncStatusRawValue == pendingRawValue ||
                            routine.remoteSyncStatusRawValue == failedRawValue
                    )
            },
            sortBy: [SortDescriptor(\Routine.updatedAt)]
        )
        return try modelContext.fetch(descriptor)
    }

    func pendingFolders(
        modelContext: ModelContext,
        currentUserId: String
    ) throws -> [RoutineFolder] {
        let pendingRawValue = RoutineRemoteSyncStatus.pendingUpsert.rawValue
        let failedRawValue = RoutineRemoteSyncStatus.failed.rawValue
        let descriptor = FetchDescriptor<RoutineFolder>(
            predicate: #Predicate<RoutineFolder> { folder in
                folder.ownerUserId == currentUserId &&
                    (
                        folder.remoteSyncStatusRawValue == pendingRawValue ||
                            folder.remoteSyncStatusRawValue == failedRawValue
                    )
            },
            sortBy: [SortDescriptor(\RoutineFolder.createdAt)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Where each of this climber's folders stands with the backup.
    ///
    /// Two states are named because only two lead anywhere different, but three
    /// distinct conditions map onto `awaitingUpload`, and leaving one out of this
    /// list is how the third got misfiled once already:
    ///
    /// - `pendingUpsert` - queued and not yet sent.
    /// - `failed` - sent and refused for something transient; retried next pass.
    /// - ownerless - created while nobody was signed in, so it is not queued
    ///   under any uid yet. `RoutineRemoteSyncAdoptionService` claims it on the
    ///   next authenticated bootstrap and it uploads normally after that. It has
    ///   not failed and it is not absent; it is late.
    ///
    /// A folder absent from the map is genuinely unreachable, and there are only
    /// two of those: `rejected`, which is terminal, and a `folderId` naming no
    /// folder in the store at all. Queued for deletion counts as absent for the
    /// same reason. There is no case for unreachable because "will never arrive"
    /// and "was never here" call for the same answer.
    func folderBackupStates(
        modelContext: ModelContext,
        currentUserId: String,
        excludedIds: Set<UUID>
    ) throws -> [UUID: FolderBackupState] {
        let syncedRawValue = RoutineRemoteSyncStatus.synced.rawValue
        let pendingRawValue = RoutineRemoteSyncStatus.pendingUpsert.rawValue
        let failedRawValue = RoutineRemoteSyncStatus.failed.rawValue
        let descriptor = FetchDescriptor<RoutineFolder>(
            predicate: #Predicate<RoutineFolder> { folder in
                folder.ownerUserId == currentUserId &&
                    (
                        folder.remoteSyncStatusRawValue == syncedRawValue ||
                            folder.remoteSyncStatusRawValue == pendingRawValue ||
                            folder.remoteSyncStatusRawValue == failedRawValue
                    )
            }
        )

        var states: [UUID: FolderBackupState] = [:]

        for folder in try RoutineRemoteSyncAdoptionService.ownerlessFolders(
            modelContext: modelContext
        ) where !excludedIds.contains(folder.id) {
            states[folder.id] = .awaitingUpload
        }

        for folder in try modelContext.fetch(descriptor)
        where !excludedIds.contains(folder.id) {
            states[folder.id] = folder.remoteSyncStatus == .synced ? .backedUp : .awaitingUpload
        }

        return states
    }

    func pendingDeletions(
        modelContext: ModelContext,
        currentUserId: String
    ) throws -> [PendingRoutineDeletion] {
        let descriptor = FetchDescriptor<PendingRoutineDeletion>(
            predicate: #Predicate<PendingRoutineDeletion> { deletion in
                deletion.ownerUserId == currentUserId
            },
            sortBy: [SortDescriptor(\PendingRoutineDeletion.enqueuedAt)]
        )
        return try modelContext.fetch(descriptor)
    }

    func pendingDeletionRecordIds(
        modelContext: ModelContext,
        currentUserId: String
    ) throws -> Set<UUID> {
        Set(
            try pendingDeletions(
                modelContext: modelContext,
                currentUserId: currentUserId
            ).map(\.recordId)
        )
    }

    /// A rejection is terminal, so it has to be visible. The details name the
    /// bound that was breached and the sizes involved, never the climber's own
    /// name or description text.
    func recordRejection(_ error: Error, kind: String, recordId: UUID) {
        var details = (error as? RoutineSyncError)?.diagnosticDetails ?? ["reason": "unmappable"]
        details["record_kind"] = kind
        details["record_id"] = recordId.uuidString

        diagnostics.record(
            "routine_backup_rejected",
            level: .warning,
            details: details,
            mirrorToCrashlytics: true
        )
        recordFailure(error, code: "routine_sync_rejected", recordId: recordId)
    }

    /// A repaired record still uploads, so nothing else would ever say a value we
    /// published was out of bounds. This is the only thing that does.
    ///
    /// Reported from the pass that uploaded the record. For a converged repair
    /// that is also the pass that fixed the local value, so the next pass finds
    /// nothing left to report and a bad catalog number costs one event per
    /// record. An upload-only repair re-reports per upload by design, because the
    /// alternative is breaking a lookup something local depends on.
    func recordRepairs(_ repairs: [RoutineSyncRepair], kind: String, recordId: UUID) {
        for repair in repairs {
            var details = repair.diagnosticDetails
            details["record_kind"] = kind
            details["record_id"] = recordId.uuidString

            diagnostics.record(
                "routine_backup_repaired",
                level: .warning,
                details: details,
                mirrorToCrashlytics: true
            )
        }
    }

    func recordFailure(_ error: Error, code: String, recordId: UUID?) {
        TelemetryManager.shared.recordError(
            error,
            context: .firestore,
            code: code,
            additionalInfo: recordId.map { ["routine_id": $0.uuidString] }
        )
    }
}
