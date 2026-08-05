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
    private let connectivityService: any WorkoutSyncConnectivityProviding
    private let settingReader: any RemoteConfigSettingReading
    private let userDefaults: UserDefaults
    private let buildIdentity: String
    private let now: () -> Date
    private var isProcessingPendingWorkouts = false
    private var shouldProcessPendingWorkoutsAgain = false

    /// Workouts the climber has personally asked to sync, and the ones currently in flight.
    ///
    /// Both live here rather than in a view's `@State` because a tab switch or a navigation would
    /// otherwise discard them while the operation kept running - the surface would forget it had
    /// been asked, and the control would unlock under a request that was still going.
    private var manuallyRequestedWorkoutIds: Set<UUID> = []
    private(set) var inFlightWorkoutIds: Set<UUID> = []

    /// Workouts whose climber has seen the warning, so the transient `Synced` confirmation is only
    /// ever shown to someone who was told there was a problem. In-memory on purpose: losing it on
    /// relaunch costs a confirmation, never a warning.
    private(set) var warnedWorkoutIds: Set<UUID> = []

    init(
        remoteRepository: any WorkoutRemoteRepositoryProtocol = WorkoutRemoteRepository.shared,
        heartRateStorageRepository: any WorkoutHeartRateStorageRepositoryProtocol = WorkoutHeartRateStorageRepository.shared,
        featureFlags: RemoteFeatureFlagStore = .shared,
        operationTimeoutSeconds: Double = 15.0,
        connectivityService: any WorkoutSyncConnectivityProviding = NetworkConnectivityService.shared,
        settingReader: any RemoteConfigSettingReading = FirebaseRemoteConfigSettingReader(),
        userDefaults: UserDefaults = .standard,
        buildIdentity: String = TelemetryBuildMetadata.current.releaseName,
        now: @escaping () -> Date = Date.init
    ) {
        self.remoteRepository = remoteRepository
        self.heartRateStorageRepository = heartRateStorageRepository
        self.featureFlags = featureFlags
        self.operationTimeoutSeconds = operationTimeoutSeconds
        self.connectivityService = connectivityService
        self.settingReader = settingReader
        self.userDefaults = userDefaults
        self.buildIdentity = buildIdentity
        self.now = now
    }

    /// Where the basis for a stopped series is remembered, so a change to it re-opens exactly once.
    static let recoveryBasisDefaultsKeyPrefix = "workoutSync.recoveryBasis."

    /// Gives every stopped workout one more automatic attempt when the basis for stopping moves.
    ///
    /// Two triggers, and the second is the one that matters: `firestore.rules` deploys
    /// independently of app releases, so a build-change trigger alone could not unstick the
    /// workouts a rules fix repairs - including the ones this very change repairs. An operator
    /// bumps `workout_sync_recovery_epoch` after the fix and the whole fleet re-attempts without a
    /// binary.
    ///
    /// Screen appearance, tab switches, repeated coordinator calls and ordinary Remote Config
    /// fetches deliberately do not qualify. The token is compared for difference, and the shipped
    /// default equals the template baseline, so a device's first successful fetch cannot read as a
    /// bump.
    ///
    /// Keyed per user: sign-out does not empty the local store, so one device can hold stopped
    /// workouts for two accounts, and a single global marker would let whichever account ran first
    /// consume the re-open for both.
    func reopenStoppedWorkoutsIfRecoveryBasisChanged(
        modelContext: ModelContext,
        currentUserId: String
    ) throws {
        // Killed: stopped workouts stay stopped and re-open on a later pass once the flag returns.
        // Nothing is lost - the recorded basis is only written after the sweep succeeds.
        guard RemoteFeatureGate.allows(
            .workoutSyncRecoveryReopen,
            path: "WorkoutSyncCoordinator.reopenStoppedWorkoutsIfRecoveryBasisChanged",
            store: featureFlags
        ) else {
            return
        }

        let epoch = settingReader.integer(.workoutSyncRecoveryEpoch)
        let token = "\(buildIdentity)|\(epoch)"
        let key = Self.recoveryBasisDefaultsKeyPrefix + currentUserId

        guard userDefaults.string(forKey: key) != token else { return }

        let descriptor = FetchDescriptor<WorkoutSyncOutboxEntry>(
            predicate: #Predicate<WorkoutSyncOutboxEntry> { entry in
                entry.ownerUserId == currentUserId
            }
        )

        let reopenedAt = now()
        for entry in try modelContext.fetch(descriptor)
        where entry.hasStoppedAutomaticAttempts(now: reopenedAt) {
            entry.reopenOneAutomaticAttempt(now: reopenedAt)

            if let workout = try Self.fetchWorkout(
                workoutId: entry.workoutId,
                userId: currentUserId,
                modelContext: modelContext
            ), !workout.isSyncedToCloud {
                workout.remoteSyncStatus = .pendingUpsert
            }
        }

        try modelContext.save()
        userDefaults.set(token, forKey: key)
    }

    /// One tap, one Ascend-level attempt, unlimited and never exhausting.
    ///
    /// Deliberately does not touch the automatic series: a manual retry re-offers the same payload
    /// revision, so resetting the schedule it bypasses would let taps launder the stopping policy.
    func retryNow(
        workoutId: UUID,
        modelContext: ModelContext,
        currentUserId: String
    ) async {
        guard !inFlightWorkoutIds.contains(workoutId) else { return }

        manuallyRequestedWorkoutIds.insert(workoutId)
        warnedWorkoutIds.insert(workoutId)
        await processPendingWorkouts(modelContext: modelContext, currentUserId: currentUserId)
        manuallyRequestedWorkoutIds.remove(workoutId)
    }

    /// What the surface renders, derived from whether the climb is in the cloud - never from what
    /// the retry machinery happens to be doing.
    func syncPresentation(
        for workout: Workout,
        modelContext: ModelContext
    ) -> WorkoutSyncPresentation {
        if workout.isSyncedToCloud {
            return warnedWorkoutIds.contains(workout.id) ? .synced : .hidden
        }

        if inFlightWorkoutIds.contains(workout.id) {
            // The row keeps saying `Couldn't sync this climb` while the control says `SYNCING`, so
            // tapping can never make the warning disappear.
            return warnedWorkoutIds.contains(workout.id) ? .couldNotSyncRetrying : .syncing
        }

        let entry = try? outboxEntry(
            forWorkoutId: workout.id,
            ownerUserId: workout.ownerUserId ?? "",
            createIfMissing: false,
            modelContext: modelContext
        )

        // Once a climber has been told, the surface stays loud until the climb actually lands.
        //
        // Without this latch a refused manual retry re-derives the status from the automatic
        // series, drops `rejected` back to `failed`, and - if the quiet window has not elapsed -
        // the warning silently becomes `Syncing`. That is the disappearing-warning defect arriving
        // through a different door, and it reads as success.
        let needsAttention = workout.remoteSyncStatus == .rejected ||
            warnedWorkoutIds.contains(workout.id) ||
            (entry?.requiresAttention(now: now()) ?? false)
        guard needsAttention else { return .syncing }

        warnedWorkoutIds.insert(workout.id)
        return connectivityService.isConnected ? .couldNotSync : .couldNotSyncOffline
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

        isProcessingPendingWorkouts = true
        defer { isProcessingPendingWorkouts = false }

        do {
            try reopenStoppedWorkoutsIfRecoveryBasisChanged(
                modelContext: modelContext,
                currentUserId: currentUserId
            )
        } catch {
            recordSyncFailure(error, workoutId: nil, category: .transient)
        }

        repeat {
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
                    inFlightWorkoutIds.insert(snapshot.workoutId)
                    defer { inFlightWorkoutIds.remove(snapshot.workoutId) }

                    do {
                        let heartRateSeries = try await sync(snapshot)
                        // Only a completed remote write gets here. Firestore's `setData` completion
                        // does not fire while offline and fires only after the backend commits, so
                        // reaching this line is the server acknowledgement - not merely a request
                        // having been sent.
                        try markSynced(
                            workoutId: snapshot.workoutId,
                            userId: snapshot.userId,
                            expectedModifiedAt: snapshot.lastModifiedAt,
                            heartRateSeries: heartRateSeries,
                            modelContext: modelContext
                        )
                        try clearOutboxEntry(forWorkoutId: snapshot.workoutId, modelContext: modelContext)
                    } catch {
                        let category = WorkoutSyncFailureClassifier.category(
                            for: error,
                            isConnected: connectivityService.isConnected
                        )

                        // A teardown is not a verdict. It consumes no attempt, reports nothing, and
                        // abandons the rest of the pass rather than running it against a dying
                        // task - recording these is what turned one stuck workout into 499 events.
                        if category == .cancelled || Task.isCancelled {
                            try? recordAttemptOutcome(
                                category,
                                workoutId: snapshot.workoutId,
                                userId: snapshot.userId,
                                expectedModifiedAt: snapshot.lastModifiedAt,
                                errorMessage: error.localizedDescription,
                                modelContext: modelContext
                            )
                            return
                        }

                        recordSyncFailure(error, workoutId: snapshot.workoutId, category: category)
                        try? recordAttemptOutcome(
                            category,
                            workoutId: snapshot.workoutId,
                            userId: snapshot.userId,
                            expectedModifiedAt: snapshot.lastModifiedAt,
                            errorMessage: error.localizedDescription,
                            modelContext: modelContext
                        )
                    }
                }
            } catch {
                if WorkoutSyncFailureClassifier.category(
                    for: error,
                    isConnected: connectivityService.isConnected
                ) == .cancelled || Task.isCancelled {
                    return
                }
                recordSyncFailure(error, workoutId: nil, category: .transient)
            }
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
            let heartRateSeries = try await withRemoteSyncTimeout(seconds: operationTimeoutSeconds) {
                try await self.heartRateStorageRepository.uploadHeartRateSeries(
                    userId: snapshot.userId,
                    workoutId: snapshot.workoutId,
                    blob: heartRateBlob
                )
            }

            finalDocument = baseDocument.replacingHeartRateSeries(heartRateSeries)
        } else if baseDocument.heartRateSeries == nil,
                  snapshot.previousHeartRateSeriesStoragePath != nil {
            try await withRemoteSyncTimeout(seconds: operationTimeoutSeconds) {
                try await self.heartRateStorageRepository.deleteHeartRateSeriesIfPresent(
                    userId: snapshot.userId,
                    workoutId: snapshot.workoutId
                )
            }
            finalDocument = baseDocument
        } else {
            finalDocument = baseDocument
        }

        try await withRemoteSyncTimeout(seconds: operationTimeoutSeconds) {
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
        try await withRemoteSyncTimeout(seconds: operationTimeoutSeconds) {
            try await self.heartRateStorageRepository.deleteHeartRateSeriesIfPresent(
                userId: userId,
                workoutId: workoutId
            )
        }

        try await withRemoteSyncTimeout(seconds: operationTimeoutSeconds) {
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

        let now = self.now()
        let workouts = try modelContext.fetch(descriptor)
            .filter { workout in
                guard !pendingDeletionIds.contains(workout.id) else { return false }
                guard workout.remoteSyncStatus != .synced else { return false }

                // A climber's tap bypasses the due date for exactly one attempt. Everything else
                // waits for its persisted no-earlier-than time, which is what stops seven trigger
                // surfaces from spending the whole series in one millisecond.
                if manuallyRequestedWorkoutIds.contains(workout.id) { return true }
                guard workout.remoteSyncStatus != .rejected else { return false }

                let entry = try? outboxEntry(
                    forWorkoutId: workout.id,
                    ownerUserId: currentUserId,
                    createIfMissing: false,
                    modelContext: modelContext
                )
                guard let entry else { return true }
                return entry.isDueForAutomaticAttempt(now: now)
            }

        var snapshots: [WorkoutRemoteSyncSnapshot] = []
        for workout in workouts {
            do {
                snapshots.append(try WorkoutRemoteSyncMapper.snapshot(from: workout))
            } catch let error as WorkoutSyncError {
                // Every `WorkoutSyncError` is a permanent statement about this one workout's shape,
                // so it takes the terminal status and the pass carries on. Rethrowing - which
                // implausible totals were the only exception to - aborts the whole queue, so one
                // unsyncable workout would stop every healthy one behind it from reaching the
                // cloud at all.
                workout.markRemoteSyncRejected(error.localizedDescription)
                try modelContext.save()
            }
        }

        return snapshots
    }

    /// The persisted schedule for one workout, created on first need.
    ///
    /// A workout that predates this build simply has no entry, which reads as "never attempted" -
    /// the same state a brand-new workout is in, and correct.
    func outboxEntry(
        forWorkoutId workoutId: UUID,
        ownerUserId: String,
        createIfMissing: Bool,
        modelContext: ModelContext
    ) throws -> WorkoutSyncOutboxEntry? {
        let descriptor = FetchDescriptor<WorkoutSyncOutboxEntry>(
            predicate: #Predicate<WorkoutSyncOutboxEntry> { entry in
                entry.workoutId == workoutId
            }
        )

        if let existing = try modelContext.fetch(descriptor).first { return existing }
        guard createIfMissing else { return nil }

        let entry = WorkoutSyncOutboxEntry(
            workoutId: workoutId,
            ownerUserId: ownerUserId,
            firstPendingAt: now()
        )
        modelContext.insert(entry)
        return entry
    }

    /// Drops the schedule once the cloud has acknowledged the workout. Nothing is left to retry.
    func clearOutboxEntry(forWorkoutId workoutId: UUID, modelContext: ModelContext) throws {
        let descriptor = FetchDescriptor<WorkoutSyncOutboxEntry>(
            predicate: #Predicate<WorkoutSyncOutboxEntry> { entry in
                entry.workoutId == workoutId
            }
        )

        for entry in try modelContext.fetch(descriptor) {
            modelContext.delete(entry)
        }
        try modelContext.save()
    }

    /// Records a genuine remote outcome against the persisted schedule.
    ///
    /// Cancellation and offline deliberately reach here too, so the recorded blocker is accurate,
    /// but they consume no attempt and do not move the due date.
    func recordAttemptOutcome(
        _ category: WorkoutSyncFailureCategory,
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

        let entry = try outboxEntry(
            forWorkoutId: workoutId,
            ownerUserId: userId,
            createIfMissing: true,
            modelContext: modelContext
        )
        entry?.recordFailure(category: category, now: now())

        workout.lastRemoteSyncError = errorMessage
        // `rejected` means only that the automatic series has stopped. It is not "unfixable" and
        // never hides the workout: manual retry stays unlimited, and the surface reads
        // `isSyncedToCloud`, so the warning survives whichever status this leaves behind.
        workout.remoteSyncStatus = (entry?.hasStoppedAutomaticAttempts(now: now()) ?? false)
            ? .rejected
            : .failed

        try modelContext.save()
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

    func recordSyncFailure(
        _ error: Error,
        workoutId: UUID?,
        category: WorkoutSyncFailureCategory
    ) {
        var additionalInfo = workoutId.map { ["workout_id": $0.uuidString] } ?? [:]
        additionalInfo["sync_failure_category"] = category.rawValue

        let context: TelemetryManager.ErrorContext
        let code: String

        switch error {
        case is WorkoutSyncError,
             is RemoteSyncTimeoutError:
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
