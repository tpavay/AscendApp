import Foundation
import SwiftData

/// Claims ownerless routines and folders for the signed-in climber, so their
/// first upload actually happens.
///
/// Everything the coordinator uploads is keyed on `ownerUserId`, and a record
/// built before this build shipped - or saved during a window where nobody was
/// signed in - has none. Without this pass those records sit at `pendingUpsert`
/// forever and are never backed up, which is the original bug wearing a new hat.
///
/// Deliberately NOT one-shot. A one-shot key answers "have the records that
/// predate the backup been claimed", but ownerless records keep being created
/// after that: any save while `Auth.auth().currentUser` is nil produces one, and
/// a stamped key would strand it permanently with nothing to say so. The sweep
/// runs on every authenticated bootstrap instead, and stays cheap by asking the
/// store only for records that are actually ownerless - normally none.
/// Templates are excluded: they are server-owned content, not the climber's.
enum RoutineRemoteSyncAdoptionService {
    static func runIfNeeded(
        modelContext: ModelContext,
        currentUserId: String,
        featureFlags: RemoteFeatureFlagStore = .shared
    ) throws {
        // Killed: the records keep their missing owner and are claimed on the
        // next bootstrap after the flag returns. Nothing is dropped, because
        // nothing here is stamped as done.
        guard RemoteFeatureGate.allows(
            .localDataMigrations,
            path: "RoutineRemoteSyncAdoptionService.runIfNeeded",
            store: featureFlags
        ) else {
            return
        }

        var didChange = false

        for routine in try ownerlessRoutines(modelContext: modelContext) {
            didChange = adopt(routine, currentUserId: currentUserId) || didChange
        }

        for folder in try ownerlessFolders(modelContext: modelContext) {
            didChange = adopt(folder, currentUserId: currentUserId) || didChange
        }

        if didChange {
            try modelContext.save()
        }
    }

    /// Ownerless user-authored routines only - the catalog is permanently
    /// ownerless by design, so filtering it in the store rather than in memory
    /// keeps the common case (nothing to claim) at zero rows.
    static func ownerlessRoutines(modelContext: ModelContext) throws -> [Routine] {
        let builtinRaw = RoutineSource.builtin.rawValue
        let remoteTemplateRaw = RoutineSource.remoteTemplate.rawValue
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate<Routine> { routine in
                routine.ownerUserId == nil &&
                    routine.sourceRawValue != builtinRaw &&
                    routine.sourceRawValue != remoteTemplateRaw
            }
        )
        return try modelContext.fetch(descriptor)
    }

    static func ownerlessFolders(modelContext: ModelContext) throws -> [RoutineFolder] {
        let descriptor = FetchDescriptor<RoutineFolder>(
            predicate: #Predicate<RoutineFolder> { folder in
                folder.ownerUserId == nil
            }
        )
        return try modelContext.fetch(descriptor)
    }

    @discardableResult
    static func adopt(_ routine: Routine, currentUserId: String) -> Bool {
        guard routine.ownerUserId == nil, routine.isUserAuthored else { return false }

        // The existing `updatedAt` is kept rather than refreshed: it is what the
        // conflict rule compares against, and moving it forward would let a
        // stale local copy outrank a newer backup on a second device.
        routine.markPendingRemoteUpsert(
            ownerUserId: currentUserId,
            modifiedAt: routine.updatedAt
        )
        return true
    }

    @discardableResult
    static func adopt(_ folder: RoutineFolder, currentUserId: String) -> Bool {
        guard folder.ownerUserId == nil else { return false }

        folder.markPendingRemoteUpsert(
            ownerUserId: currentUserId,
            modifiedAt: folder.effectiveUpdatedAt
        )
        return true
    }
}
