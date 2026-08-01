import Foundation
import FirebaseStorage
import SwiftData

@MainActor
final class WorkoutSyncCoordinator {
    static let shared = WorkoutSyncCoordinator()

    private let remoteRepository: any WorkoutRemoteRepositoryProtocol
    private let heartRateStorageRepository: any WorkoutHeartRateStorageRepositoryProtocol
    private let featureFlags: RemoteFeatureFlagStore
    private let operationTimeoutSeconds: Double
    private var isProcessingPendingWorkouts = false
    private var shouldProcessPendingWorkoutsAgain = false

    init(
        remoteRepository: any WorkoutRemoteRepositoryProtocol = WorkoutRemoteRepository.shared,
        heartRateStorageRepository: any WorkoutHeartRateStorageRepositoryProtocol = WorkoutHeartRateStorageRepository.shared,
        featureFlags: RemoteFeatureFlagStore = .shared,
        operationTimeoutSeconds: Double = 15.0
    ) {
        self.remoteRepository = remoteRepository
        self.heartRateStorageRepository = heartRateStorageRepository
        self.featureFlags = featureFlags
        self.operationTimeoutSeconds = operationTimeoutSeconds
    }

    func enqueuePendingDeletions(
        for workouts: [Workout],
        fallbackUserId: String?,
        modelContext: ModelContext
    ) throws -> Bool {
        guard !workouts.isEmpty else { return false }

        let existingDescriptor = FetchDescriptor<PendingWorkoutDeletion>()
        var existingKeys = try Set(
            modelContext.fetch(existingDescriptor).map {
                PendingDeletionKey(
                    workoutId: $0.workoutId,
                    ownerUserId: $0.ownerUserId
                )
            }
        )

        var didInsertDeletion = false

        for workout in workouts {
            guard let ownerUserId = workout.ownerUserId ?? fallbackUserId else { continue }

            let key = PendingDeletionKey(
                workoutId: workout.id,
                ownerUserId: ownerUserId
            )

            guard existingKeys.insert(key).inserted else { continue }
            modelContext.insert(
                PendingWorkoutDeletion(
                    workoutId: workout.id,
                    ownerUserId: ownerUserId
                )
            )
            didInsertDeletion = true
        }

        return didInsertDeletion
    }

    func processPendingWorkouts(
        modelContext: ModelContext,
        currentUserId: String
    ) async {
        if isProcessingPendingWorkouts {
            shouldProcessPendingWorkoutsAgain = true
            return
        }

        repeat {
            isProcessingPendingWorkouts = true
            shouldProcessPendingWorkoutsAgain = false

            do {
                let deletedWorkoutIds = try await processPendingDeletions(
                    modelContext: modelContext,
                    currentUserId: currentUserId
                )

                // Killed: the workouts stay flagged for upsert in SwiftData and go up on the
                // next pass after the flag returns. Nothing is marked synced or failed.
                let snapshots = backupsAreEnabled
                    ? try loadPendingSnapshots(
                        modelContext: modelContext,
                        currentUserId: currentUserId,
                        excludedWorkoutIds: deletedWorkoutIds
                    )
                    : []

                for snapshot in snapshots {
                    do {
                        let heartRateSeries = try await sync(snapshot)
                        try markSynced(
                            workoutId: snapshot.workoutId,
                            userId: snapshot.userId,
                            expectedModifiedAt: snapshot.lastModifiedAt,
                            heartRateSeries: heartRateSeries,
                            modelContext: modelContext
                        )
                    } catch {
                        recordSyncFailure(error, workoutId: snapshot.workoutId)
                        try? markFailed(
                            workoutId: snapshot.workoutId,
                            userId: snapshot.userId,
                            expectedModifiedAt: snapshot.lastModifiedAt,
                            errorMessage: error.localizedDescription,
                            modelContext: modelContext
                        )
                    }
                }
            } catch {
                recordSyncFailure(error, workoutId: nil)
            }

            isProcessingPendingWorkouts = false
        } while shouldProcessPendingWorkoutsAgain
    }
}

private extension WorkoutSyncCoordinator {
    struct PendingDeletionKey: Hashable {
        let workoutId: UUID
        let ownerUserId: String
    }

    func sync(
        _ snapshot: WorkoutRemoteSyncSnapshot
    ) async throws -> FirestoreWorkoutHeartRateSeriesReference? {
        let baseDocument = snapshot.document
        let finalDocument: FirestoreWorkoutDocument

        if let heartRateBlob = snapshot.heartRateBlob {
            let heartRateSeries = try await withWorkoutSyncTimeout(seconds: operationTimeoutSeconds) {
                try await self.heartRateStorageRepository.uploadHeartRateSeries(
                    userId: snapshot.userId,
                    workoutId: snapshot.workoutId,
                    blob: heartRateBlob
                )
            }

            finalDocument = baseDocument.replacingHeartRateSeries(heartRateSeries)
        } else if baseDocument.heartRateSeries == nil,
                  snapshot.previousHeartRateSeriesStoragePath != nil {
            try await withWorkoutSyncTimeout(seconds: operationTimeoutSeconds) {
                try await self.heartRateStorageRepository.deleteHeartRateSeriesIfPresent(
                    userId: snapshot.userId,
                    workoutId: snapshot.workoutId
                )
            }
            finalDocument = baseDocument
        } else {
            finalDocument = baseDocument
        }

        try await withWorkoutSyncTimeout(seconds: operationTimeoutSeconds) {
            try await self.remoteRepository.upsertWorkout(
                userId: snapshot.userId,
                workoutId: snapshot.workoutId,
                document: finalDocument
            )
        }

        return finalDocument.heartRateSeries
    }

    var backupsAreEnabled: Bool {
        RemoteFeatureGate.allows(
            .workoutCloudBackupWrites,
            path: "WorkoutSyncCoordinator.processPendingWorkouts",
            store: featureFlags
        )
    }

    func processPendingDeletions(
        modelContext: ModelContext,
        currentUserId: String
    ) async throws -> Set<UUID> {
        // Killed: the `PendingWorkoutDeletion` rows survive untouched and replay once the flag is
        // back on. Returning no deleted ids is safe because `loadPendingSnapshots` reads those same
        // rows itself, so a workout awaiting deletion is still excluded from the upsert pass.
        guard RemoteFeatureGate.allows(
            .workoutRemoteDeletes,
            path: "WorkoutSyncCoordinator.processPendingDeletions",
            store: featureFlags
        ) else {
            return []
        }

        let pendingDeletions = try loadPendingDeletions(
            modelContext: modelContext,
            currentUserId: currentUserId
        )
        var deletedWorkoutIds: Set<UUID> = []

        for pendingDeletion in pendingDeletions {
            do {
                try await deleteRemoteResources(for: pendingDeletion)
                deletedWorkoutIds.insert(pendingDeletion.workoutId)
                modelContext.delete(pendingDeletion)
                try modelContext.save()
            } catch {
                recordDeletionFailure(error, workoutId: pendingDeletion.workoutId)
                pendingDeletion.recordFailure(error.localizedDescription)
                try? modelContext.save()
            }
        }

        return deletedWorkoutIds
    }

    func deleteRemoteResources(
        for pendingDeletion: PendingWorkoutDeletion
    ) async throws {
        let userId = pendingDeletion.ownerUserId
        let workoutId = pendingDeletion.workoutId

        // Sidecar-first deletion removes active HR access before deleting the workout envelope.
        // Preventing stale devices from recreating either record still depends on the planned
        // revisioned tombstone and grace-period durability slice.
        try await withWorkoutSyncTimeout(seconds: operationTimeoutSeconds) {
            try await self.heartRateStorageRepository.deleteHeartRateSeriesIfPresent(
                userId: userId,
                workoutId: workoutId
            )
        }

        try await withWorkoutSyncTimeout(seconds: operationTimeoutSeconds) {
            try await self.remoteRepository.deleteWorkout(
                userId: userId,
                workoutId: workoutId
            )
        }
    }

    func loadPendingSnapshots(
        modelContext: ModelContext,
        currentUserId: String,
        excludedWorkoutIds: Set<UUID> = []
    ) throws -> [WorkoutRemoteSyncSnapshot] {
        let pendingDeletionDescriptor = FetchDescriptor<PendingWorkoutDeletion>(
            predicate: #Predicate<PendingWorkoutDeletion> { deletion in
                deletion.ownerUserId == currentUserId
            }
        )
        let pendingDeletionIds = try Set(
            modelContext.fetch(pendingDeletionDescriptor).map(\.workoutId)
        ).union(excludedWorkoutIds)

        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.ownerUserId == currentUserId
            },
            sortBy: [SortDescriptor(\Workout.lastModifiedAt)]
        )

        let workouts = try modelContext.fetch(descriptor)
            .filter { workout in
                guard !pendingDeletionIds.contains(workout.id) else { return false }
                let status = workout.remoteSyncStatus
                return status == .pendingUpsert || status == .failed
            }

        var snapshots: [WorkoutRemoteSyncSnapshot] = []
        for workout in workouts {
            do {
                snapshots.append(try WorkoutRemoteSyncMapper.snapshot(from: workout))
            } catch WorkoutSyncError.implausibleWorkoutTotals {
                workout.markRemoteSyncRejected(WorkoutSyncError.implausibleWorkoutTotals.localizedDescription)
                try modelContext.save()
            } catch {
                throw error
            }
        }

        return snapshots
    }

    func loadPendingDeletions(
        modelContext: ModelContext,
        currentUserId: String
    ) throws -> [PendingWorkoutDeletion] {
        let descriptor = FetchDescriptor<PendingWorkoutDeletion>(
            predicate: #Predicate<PendingWorkoutDeletion> { deletion in
                deletion.ownerUserId == currentUserId
            },
            sortBy: [SortDescriptor(\PendingWorkoutDeletion.enqueuedAt)]
        )
        return try modelContext.fetch(descriptor)
    }

    func markSynced(
        workoutId: UUID,
        userId: String,
        expectedModifiedAt: Date,
        heartRateSeries: FirestoreWorkoutHeartRateSeriesReference?,
        modelContext: ModelContext
    ) throws {
        guard let workout = try Self.fetchWorkout(
            workoutId: workoutId,
            userId: userId,
            modelContext: modelContext
        ) else { return }

        guard workout.lastModifiedAt <= expectedModifiedAt else { return }

        workout.markRemoteSyncSucceeded(
            heartRateSeries: heartRateSeries
        )
        try modelContext.save()
    }

    func markFailed(
        workoutId: UUID,
        userId: String,
        expectedModifiedAt: Date,
        errorMessage: String,
        modelContext: ModelContext
    ) throws {
        guard let workout = try Self.fetchWorkout(
            workoutId: workoutId,
            userId: userId,
            modelContext: modelContext
        ) else { return }

        guard workout.lastModifiedAt <= expectedModifiedAt else { return }

        workout.markRemoteSyncFailed(errorMessage)
        try modelContext.save()
    }

    static func fetchWorkout(
        workoutId: UUID,
        userId: String,
        modelContext: ModelContext
    ) throws -> Workout? {
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.id == workoutId && workout.ownerUserId == userId
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    func recordSyncFailure(_ error: Error, workoutId: UUID?) {
        let additionalInfo = workoutId.map { ["workout_id": $0.uuidString] }
        let context: TelemetryManager.ErrorContext
        let code: String

        switch error {
        case is WorkoutSyncError,
             is WorkoutSyncTimeoutError:
            context = .firestore
            code = "workout_sync_failed"
        case is GzipCodec.Error:
            context = .storage
            code = "workout_hr_encoding_failed"
        default:
            let nsError = error as NSError
            if nsError.domain == StorageErrorDomain {
                context = .storage
                code = "workout_hr_upload_failed"
            } else {
                context = .firestore
                code = "workout_sync_failed"
            }
        }

        TelemetryManager.shared.recordError(
            error,
            context: context,
            code: code,
            additionalInfo: additionalInfo
        )
    }

    func recordDeletionFailure(_ error: Error, workoutId: UUID?) {
        let additionalInfo = workoutId.map { ["workout_id": $0.uuidString] }
        let nsError = error as NSError
        let context: TelemetryManager.ErrorContext
        let code: String

        if nsError.domain == StorageErrorDomain {
            context = .storage
            code = "workout_hr_delete_failed"
        } else {
            context = .firestore
            code = "workout_delete_failed"
        }

        TelemetryManager.shared.recordError(
            error,
            context: context,
            code: code,
            additionalInfo: additionalInfo
        )
    }
}
