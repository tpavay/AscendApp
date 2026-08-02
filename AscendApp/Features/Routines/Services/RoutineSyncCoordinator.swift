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
    private let operationTimeoutSeconds: Double
    private var isProcessing = false
    private var shouldProcessAgain = false

    init(
        remoteRepository: any UserRoutineRemoteRepositoryProtocol = FirestoreUserRoutineRemoteRepository.shared,
        featureFlags: RemoteFeatureFlagStore = .shared,
        operationTimeoutSeconds: Double = 15.0
    ) {
        self.remoteRepository = remoteRepository
        self.featureFlags = featureFlags
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
        for folder in try pendingFolders(modelContext: modelContext, currentUserId: currentUserId)
        where !excludedIds.contains(folder.id) {
            let expectedModifiedAt = folder.effectiveUpdatedAt
            let document: FirestoreRoutineFolderDocument

            do {
                document = try RoutineRemoteSyncMapper.document(for: folder)
            } catch {
                folder.markRemoteSyncFailed(error.localizedDescription)
                try modelContext.save()
                continue
            }

            // The model object itself never crosses into the `@Sendable`
            // closure - only the value types it was read into.
            let folderId = folder.id

            do {
                try await withRemoteSyncTimeout(seconds: operationTimeoutSeconds) {
                    try await self.remoteRepository.upsertFolder(
                        userId: currentUserId,
                        folderId: folderId,
                        document: document
                    )
                }
                // A local edit that landed during the upload keeps the record
                // pending, so the newer content is not reported as backed up.
                guard folder.effectiveUpdatedAt <= expectedModifiedAt else { continue }
                folder.markRemoteSyncSucceeded()
            } catch {
                recordFailure(error, code: "routine_folder_sync_failed", recordId: folder.id)
                guard folder.effectiveUpdatedAt <= expectedModifiedAt else { continue }
                folder.markRemoteSyncFailed(error.localizedDescription)
            }

            try modelContext.save()
        }
    }

    func uploadPendingRoutines(
        modelContext: ModelContext,
        currentUserId: String,
        excludedIds: Set<UUID>
    ) async throws {
        for routine in try pendingRoutines(modelContext: modelContext, currentUserId: currentUserId)
        where !excludedIds.contains(routine.id) {
            let expectedModifiedAt = routine.updatedAt
            let document: FirestoreUserRoutineDocument

            do {
                document = try RoutineRemoteSyncMapper.document(for: routine)
            } catch {
                // A routine the server will always refuse - too many intervals,
                // or a catalog template that should never have been queued - is
                // rejected rather than retried on every launch forever.
                routine.markRemoteSyncRejected(error.localizedDescription)
                recordFailure(error, code: "routine_sync_rejected", recordId: routine.id)
                try modelContext.save()
                continue
            }

            let routineId = routine.id

            do {
                try await withRemoteSyncTimeout(seconds: operationTimeoutSeconds) {
                    try await self.remoteRepository.upsertRoutine(
                        userId: currentUserId,
                        routineId: routineId,
                        document: document
                    )
                }
                guard routine.updatedAt <= expectedModifiedAt else { continue }
                routine.markRemoteSyncSucceeded()
            } catch {
                recordFailure(error, code: "routine_sync_failed", recordId: routine.id)
                guard routine.updatedAt <= expectedModifiedAt else { continue }
                routine.markRemoteSyncFailed(error.localizedDescription)
            }

            try modelContext.save()
        }
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

    func recordFailure(_ error: Error, code: String, recordId: UUID?) {
        TelemetryManager.shared.recordError(
            error,
            context: .firestore,
            code: code,
            additionalInfo: recordId.map { ["routine_id": $0.uuidString] }
        )
    }
}
