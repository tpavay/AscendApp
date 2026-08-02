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

    /// Folders go up before the routines that point at them, so a restore on a
    /// clean device never sees a `folderId` whose folder has not arrived yet.
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
    /// A routine past a bound in `firestore.rules` - too many intervals, a name
    /// or description past its ceiling, a catalog template that should never
    /// have been queued - is `rejected` rather than retried on every launch
    /// forever, and says so through the diagnostics recorder. Retrying a
    /// permanent refusal is the worst shape available: the routine stays
    /// unbacked and nothing ever says why.
    func loadPendingRoutineSnapshots(
        modelContext: ModelContext,
        currentUserId: String,
        excludedIds: Set<UUID>
    ) throws -> [RoutineUploadSnapshot] {
        var snapshots: [RoutineUploadSnapshot] = []

        for routine in try pendingRoutines(modelContext: modelContext, currentUserId: currentUserId)
        where !excludedIds.contains(routine.id) {
            do {
                snapshots.append(
                    RoutineUploadSnapshot(
                        routineId: routine.id,
                        userId: currentUserId,
                        expectedModifiedAt: routine.updatedAt,
                        document: try RoutineRemoteSyncMapper.document(for: routine)
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

        routine.markRemoteSyncSucceeded()
        try modelContext.save()
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

    func recordFailure(_ error: Error, code: String, recordId: UUID?) {
        TelemetryManager.shared.recordError(
            error,
            context: .firestore,
            code: code,
            additionalInfo: recordId.map { ["routine_id": $0.uuidString] }
        )
    }
}
