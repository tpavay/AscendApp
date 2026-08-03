import Foundation
import SwiftData

/// Restores user-authored routines and folders from the cloud backup.
///
/// This is the half that makes the backup worth having: a reinstall or a second
/// device runs this on authenticated bootstrap and gets the climber's routines
/// back.
///
/// **Conflict rule.** Ascend is local-first, so the local copy is authoritative
/// while it still owes an upload, and the remote copy wins only when the local
/// one has nothing pending and the backup is genuinely newer. Concretely, on
/// the first pass of a process:
///
/// - Nothing local: insert the remote copy. This is the reinstall case.
/// - Local record is `pendingUpsert` or `failed`: keep the local copy untouched.
///   It holds an edit that has not reached the server yet, and overwriting it
///   would discard the newer of the two.
/// - Local record is `synced` or `rejected`: take the remote copy only if its
///   `updatedAt` is strictly newer than the local `updatedAt`.
/// - Local record queued for deletion: never re-inserted. The climber deleted
///   it while offline; the remote copy is a tombstone waiting to be collected,
///   not a record to restore.
///
/// This is the same contract `WorkoutHydrationService` applies, on purpose. Two
/// restore paths that resolve a conflict differently is two behaviours to
/// explain to a climber who moved devices, and the workout one is the tested,
/// shipped answer. Nothing here ever deletes a local routine: a routine absent
/// from the backup is a routine that has not been uploaded yet, not one that
/// was withdrawn.
@MainActor
enum RoutineHydrationService {
    private static var hydratedUserIdsThisSession: Set<String> = []
    private static var hydratingUserIds: Set<String> = []

    @discardableResult
    static func hydrateIfNeeded(
        modelContext: ModelContext,
        currentUserId: String,
        remoteRepository: any UserRoutineRemoteRepositoryProtocol = FirestoreUserRoutineRemoteRepository.shared,
        featureFlags: RemoteFeatureFlagStore = .shared
    ) async throws -> Int {
        // Killed before `hydratedUserIdsThisSession` is touched, so the restore
        // is only deferred: the next bootstrap after the flag returns still
        // treats this as the initial hydration.
        guard RemoteFeatureGate.allows(
            .routineCloudRestore,
            path: "RoutineHydrationService.hydrateIfNeeded",
            store: featureFlags
        ) else {
            return 0
        }

        guard !hydratingUserIds.contains(currentUserId),
              !hydratedUserIdsThisSession.contains(currentUserId) else {
            return 0
        }

        hydratingUserIds.insert(currentUserId)
        defer { hydratingUserIds.remove(currentUserId) }

        let folderRecords = try await remoteRepository.fetchFolders(userId: currentUserId)
        let routineRecords = try await remoteRepository.fetchRoutines(userId: currentUserId)
        let deletedIds = try pendingDeletionRecordIds(
            modelContext: modelContext,
            userId: currentUserId
        )

        var changedCount = 0
        // Folders land first so a restored routine's `folderId` already resolves.
        changedCount += try hydrateFolders(
            folderRecords,
            deletedIds: deletedIds,
            userId: currentUserId,
            modelContext: modelContext
        )
        changedCount += try hydrateRoutines(
            routineRecords,
            deletedIds: deletedIds,
            userId: currentUserId,
            modelContext: modelContext
        )

        try modelContext.save()
        hydratedUserIdsThisSession.insert(currentUserId)

        return changedCount
    }

    /// Clears per-process tracking. A reinstall starts from a cold process;
    /// tests use this to simulate a fresh launch. Not called by the app.
    static func resetSessionTrackingForTesting() {
        hydratedUserIdsThisSession.removeAll()
        hydratingUserIds.removeAll()
    }

    private static func hydrateRoutines(
        _ records: [RemoteUserRoutineRecord],
        deletedIds: Set<UUID>,
        userId: String,
        modelContext: ModelContext
    ) throws -> Int {
        let localById = Dictionary(
            try localRoutines(modelContext: modelContext).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var changedCount = 0

        for record in records {
            if let existing = localById[record.routineId] {
                guard shouldApplyRemoteRoutine(record.document, to: existing) else { continue }
                RoutineRemoteSyncMapper.apply(record.document, to: existing, userId: userId)
                changedCount += 1
            } else {
                guard !deletedIds.contains(record.routineId) else { continue }

                let routine = RoutineRemoteSyncMapper.makeRoutine(
                    from: record.document,
                    routineId: record.routineId,
                    userId: userId
                )
                modelContext.insert(routine)
                changedCount += 1
            }
        }

        return changedCount
    }

    private static func hydrateFolders(
        _ records: [RemoteRoutineFolderRecord],
        deletedIds: Set<UUID>,
        userId: String,
        modelContext: ModelContext
    ) throws -> Int {
        let localById = Dictionary(
            try localFolders(modelContext: modelContext).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var changedCount = 0

        for record in records {
            if let existing = localById[record.folderId] {
                guard shouldApplyRemoteFolder(record.document, to: existing) else { continue }
                RoutineRemoteSyncMapper.apply(record.document, to: existing, userId: userId)
                changedCount += 1
            } else {
                guard !deletedIds.contains(record.folderId) else { continue }

                let folder = RoutineRemoteSyncMapper.makeFolder(
                    from: record.document,
                    folderId: record.folderId,
                    userId: userId
                )
                modelContext.insert(folder)
                changedCount += 1
            }
        }

        return changedCount
    }

    private static func shouldApplyRemoteRoutine(
        _ document: FirestoreUserRoutineDocument,
        to routine: Routine
    ) -> Bool {
        switch routine.remoteSyncStatus {
        case .pendingUpsert, .failed:
            return false
        case .synced, .rejected:
            return document.updatedAt > routine.updatedAt
        }
    }

    private static func shouldApplyRemoteFolder(
        _ document: FirestoreRoutineFolderDocument,
        to folder: RoutineFolder
    ) -> Bool {
        switch folder.remoteSyncStatus {
        case .pendingUpsert, .failed:
            return false
        case .synced, .rejected:
            return document.updatedAt > folder.effectiveUpdatedAt
        }
    }

    /// Every local routine, owned or not.
    ///
    /// Not filtered by `ownerUserId`: a routine built before this build shipped
    /// has no owner yet, and filtering it out would insert a second copy under
    /// the same id on the first restore after an update. Ownership is stamped
    /// as the record is adopted, in `RoutineService`.
    private static func localRoutines(modelContext: ModelContext) throws -> [Routine] {
        try modelContext.fetch(FetchDescriptor<Routine>())
    }

    private static func localFolders(modelContext: ModelContext) throws -> [RoutineFolder] {
        try modelContext.fetch(FetchDescriptor<RoutineFolder>())
    }

    private static func pendingDeletionRecordIds(
        modelContext: ModelContext,
        userId: String
    ) throws -> Set<UUID> {
        let descriptor = FetchDescriptor<PendingRoutineDeletion>(
            predicate: #Predicate<PendingRoutineDeletion> { deletion in
                deletion.ownerUserId == userId
            }
        )
        return Set(try modelContext.fetch(descriptor).map(\.recordId))
    }
}
