import Foundation
import FirebaseStorage
import Observation
import SwiftData

@MainActor
@Observable
final class WorkoutSyncCoordinator {
    @ObservationIgnored static let shared = WorkoutSyncCoordinator()

    @ObservationIgnored private let remoteRepository: any WorkoutRemoteRepositoryProtocol
    @ObservationIgnored private let heartRateStorageRepository: any WorkoutHeartRateStorageRepositoryProtocol
    @ObservationIgnored private let featureFlags: RemoteFeatureFlagStore
    @ObservationIgnored private let operationTimeoutSeconds: Double
    @ObservationIgnored private let connectivityService: any WorkoutSyncConnectivityProviding
    @ObservationIgnored private let settingReader: any RemoteConfigSettingReading
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let buildIdentity: String
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var isProcessingPendingWorkouts = false
    @ObservationIgnored private var shouldProcessPendingWorkoutsAgain = false

    /// Bumped once when a pass finishes, and never per workout.
    ///
    /// The one observable thing here, so a surface can re-derive what it shows without polling and
    /// without watching the workout store. A pass saves once per workout outcome, so invalidating a
    /// screen on the store's own churn costs one full recomputation per synced climb - and the
    /// first sign-in restore, when the backlog equals the climber's whole history, is exactly when
    /// that is worst. Every other stored property here is deliberately unobserved: they change
    /// inside the pass, and nothing renders from them directly.
    private(set) var completedPassCount = 0

    /// The one answer every sync surface renders, keyed by workout.
    ///
    /// The detail row and the list badge read this rather than each deriving their own. Two
    /// independent derivations is what let the two surfaces disagree about one climb, and it is
    /// what forced the detail row to bootstrap its derivation from its own lifecycle - a row whose
    /// body is empty until that lifecycle runs is a row that never appears when it does not, which
    /// is exactly what nesting it in the detail screen's stack did.
    ///
    /// Observable, so publishing is also the invalidation: a surface reads it from `body` and needs
    /// no lifecycle of its own. Bounded by the backlog, because only a climb that is not in the
    /// cloud has anything to say.
    private(set) var publishedPresentations: [UUID: WorkoutSyncPresentation] = [:]

    /// Callers waiting for the pass that is already running to finish.
    ///
    /// Only `retryNow` waits. `processPendingWorkouts` keeps its non-blocking coalescing, because
    /// the sync path re-enters itself - a pass that awaited its own successor would deadlock.
    @ObservationIgnored private var passCompletionWaiters: [CheckedContinuation<Void, Never>] = []

    /// Workouts the climber has personally asked to sync, and the ones currently in flight.
    ///
    /// Both live here rather than in a view's `@State` because a tab switch or a navigation would
    /// otherwise discard them while the operation kept running - the surface would forget it had
    /// been asked, and the control would unlock under a request that was still going.
    @ObservationIgnored private var manuallyRequestedWorkoutIds: Set<UUID> = []

    /// Taps still waiting to learn whether their climb reached a verdict, keyed by workout.
    ///
    /// Separate from `manuallyRequestedWorkoutIds` because the two answer different questions at
    /// different moments. The request set is a bypass token, spent when a pass *queues* the
    /// workout; this records whether the queued workout then actually got an answer. A pass torn
    /// down partway through its queue spends the token on a climb it never offers, so deriving
    /// "was it served" from the token reports a refusal that never happened.
    @ObservationIgnored private var manualRetryReachedOutcome: [UUID: Bool] = [:]
    @ObservationIgnored private(set) var inFlightWorkoutIds: Set<UUID> = []

    /// Workouts whose climber has seen the warning, so the transient `Synced` confirmation is only
    /// ever shown to someone who was told there was a problem. In-memory on purpose: losing it on
    /// relaunch costs a confirmation, never a warning.
    @ObservationIgnored private(set) var warnedWorkoutIds: Set<UUID> = []

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
    ///
    /// The request outlives this call rather than being cleared when it returns. Seven surfaces
    /// drive the coordinator, so a tap regularly lands while a pass is already running; clearing
    /// the request on the early return dropped it, and the surface still reported a failure for an
    /// attempt that never ran. The request is now spent by the pass that actually queues it, and
    /// this waits for that climb's verdict rather than answering before it.
    ///
    /// Returns whether this climb actually reached a verdict - a server acknowledgement, a refusal,
    /// or a shape the client will never be able to offer. Several paths end a pass without ever
    /// getting one: the cloud-backup kill switch short-circuits the pending query, a workout owned
    /// by another account is never in this user's candidates, and a pass torn down partway through
    /// its queue abandons everything behind the workout it was on. A caller must be able to tell
    /// those from a genuine refusal, because telling a climber their climb failed to sync when
    /// nothing was ever offered is a lie in the one place the app has promised not to tell one.
    ///
    /// An unspent request is dropped here rather than left behind, so it cannot silently bypass the
    /// rejected guard and the due date on some later automatic pass with no tap behind it.
    @discardableResult
    func retryNow(
        workoutId: UUID,
        modelContext: ModelContext,
        currentUserId: String
    ) async -> Bool {
        // Already being attempted. This tap adds nothing, and the running attempt owns the outcome.
        guard !inFlightWorkoutIds.contains(workoutId) else { return false }

        // The tap itself is the request, so the control locks immediately rather than waiting for
        // the pass to reach this workout. Published rather than held in the row, so navigating away
        // and back cannot unlock a request that is still running.
        publishedPresentations[workoutId] = .couldNotSyncRetrying

        manualRetryReachedOutcome[workoutId] = false
        manuallyRequestedWorkoutIds.insert(workoutId)
        warnedWorkoutIds.insert(workoutId)
        await processPendingWorkouts(modelContext: modelContext, currentUserId: currentUserId)

        // Waits for the verdict itself, not merely for the request to be spent: a pass that queued
        // this climb may still be working towards it.
        while manualRetryReachedOutcome[workoutId] == false, isProcessingPendingWorkouts {
            await awaitRunningPass()
        }

        manuallyRequestedWorkoutIds.remove(workoutId)
        return manualRetryReachedOutcome.removeValue(forKey: workoutId) ?? false
    }

    /// What one climb's row shows right now, from published state and the latches alone.
    ///
    /// Pure and in-memory - no store query - so a view body may read it directly, which is the
    /// whole point: the row is never an empty body waiting for a lifecycle to fill it in.
    ///
    /// A climb nothing has published yet is answered from its own status, the same answer the
    /// published form reaches for a workout with no schedule on file. A published warning wins over
    /// that, because only the published form has read the schedule; a published quiet answer never
    /// does, because the climb's own status is more current than any snapshot of it.
    func presentation(for workout: Workout) -> WorkoutSyncPresentation {
        // Read first and unconditionally: this is the observable a surface registers on, so an
        // early return past it would leave a body that never hears about the next pass.
        let published = publishedPresentations[workout.id]

        if let settled = settledPresentation(for: workout) { return settled }
        if let published, published.isWarning { return published }

        return attentionPresentation(for: workout, entry: nil)
    }

    /// Derives one climb's answer against the persisted schedule and publishes it.
    @discardableResult
    func syncPresentation(
        for workout: Workout,
        modelContext: ModelContext
    ) -> WorkoutSyncPresentation {
        let presentation = derivedPresentation(for: workout, modelContext: modelContext)
        publishedPresentations[workout.id] = presentation
        return presentation
    }

    /// The same answer for a whole screenful, on one store query.
    ///
    /// The per-workout form issues its own `FetchDescriptor`, so calling it in a loop from a
    /// screen's `.task` is a query whose count grows with the climber's history - the shape the
    /// project forbids outright.
    @discardableResult
    func syncPresentations(
        for workouts: [Workout],
        modelContext: ModelContext
    ) -> [UUID: WorkoutSyncPresentation] {
        var presentations: [UUID: WorkoutSyncPresentation] = [:]
        var needingSchedule: [Workout] = []

        for workout in workouts {
            if let settled = settledPresentation(for: workout) {
                presentations[workout.id] = settled
            } else {
                needingSchedule.append(workout)
            }
        }

        guard !needingSchedule.isEmpty else {
            publishedPresentations.merge(presentations) { _, published in published }
            return presentations
        }

        let entries = (try? outboxEntriesByWorkoutId(modelContext: modelContext)) ?? [:]
        for workout in needingSchedule {
            presentations[workout.id] = attentionPresentation(
                for: workout,
                entry: entries[workout.id]
            )
        }

        publishedPresentations.merge(presentations) { _, published in published }
        return presentations
    }

    /// Re-derives what every surface shows, once, at the end of a pass.
    ///
    /// A pass is the only thing that moves a climb's schedule, and a surface reading the published
    /// map has no lifecycle of its own to notice - so the coordinator republishes rather than
    /// waiting to be asked. One query, bounded by the backlog: a climb already in the cloud needs
    /// no schedule read to answer for.
    func republishPresentations(modelContext: ModelContext, currentUserId: String) {
        let syncedRawValue = WorkoutRemoteSyncStatus.synced.rawValue
        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { workout in
                workout.ownerUserId == currentUserId &&
                workout.remoteSyncStatusRawValue != syncedRawValue
            }
        )

        guard let unsynced = try? modelContext.fetch(descriptor) else { return }

        // A climb that has left the backlog has landed or been deleted, and the latches answer for
        // it now. Dropping it keeps a stale warning from outliving the problem it described - and
        // keeps this map bounded by the backlog rather than by everything ever published into it.
        let stillUnsynced = Set(unsynced.map(\.id))
        publishedPresentations = publishedPresentations.filter { stillUnsynced.contains($0.key) }

        syncPresentations(for: unsynced, modelContext: modelContext)
    }

    func enqueuePendingDeletions(
        for workouts: [Workout],
        fallbackUserId: String?,
        modelContext: ModelContext
    ) throws -> Bool {
        guard !workouts.isEmpty else { return false }

        // Both reads happen before anything is staged, and nothing below throws. The caller owns
        // the save, and `WorkoutDetailView.deleteWorkout` abandons the delete on a throw from here
        // without saving - so a throw after staging would leave orphan changes in the shared main
        // context for the next unrelated save to commit.
        let existingDescriptor = FetchDescriptor<PendingWorkoutDeletion>()
        var existingKeys = try Set(
            modelContext.fetch(existingDescriptor).map {
                PendingDeletionKey(
                    workoutId: $0.workoutId,
                    ownerUserId: $0.ownerUserId
                )
            }
        )
        let outboxEntries = try modelContext.fetch(FetchDescriptor<WorkoutSyncOutboxEntry>())

        var enqueuedWorkoutIds: Set<UUID> = []

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
            enqueuedWorkoutIds.insert(workout.id)
        }

        // The workouts are about to leave the store, and nothing else sweeps the outbox by workout
        // id. An entry left behind would outlive its workout forever, be re-read by every recovery
        // sweep, and - since entries are found by workout id - be inherited by any future record
        // that reused it.
        for entry in outboxEntries where enqueuedWorkoutIds.contains(entry.workoutId) {
            modelContext.delete(entry)
        }

        return !enqueuedWorkoutIds.isEmpty
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
        defer {
            isProcessingPendingWorkouts = false
            republishPresentations(modelContext: modelContext, currentUserId: currentUserId)
            completedPassCount &+= 1
            let waiters = passCompletionWaiters
            passCompletionWaiters = []
            for waiter in waiters { waiter.resume() }
        }

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
                        noteOutcomeReached(forWorkoutId: snapshot.workoutId)
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
                        noteOutcomeReached(forWorkoutId: snapshot.workoutId)
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
                // Also covers a deletion queued by a build that predates the sweep in
                // `enqueuePendingDeletions`.
                try deleteOutboxEntries(
                    forWorkoutId: pendingDeletion.workoutId,
                    modelContext: modelContext
                )
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
        // One query for the whole schedule rather than one per candidate workout: this runs on
        // every pass, and a pass after a sign-in restore has every workout to consider.
        let entriesByWorkoutId = try outboxEntriesByWorkoutId(modelContext: modelContext)
        var didResetSchedule = false
        var workouts: [Workout] = []

        for workout in try modelContext.fetch(descriptor) {
            // A climber's tap bypasses the due date for exactly one attempt. It is consumed here,
            // by the pass that actually reads it, so a tap that arrived while another pass was
            // running is still served rather than cleared unread.
            let wasManuallyRequested = manuallyRequestedWorkoutIds.remove(workout.id) != nil

            guard !pendingDeletionIds.contains(workout.id) else { continue }
            guard workout.remoteSyncStatus != .synced else { continue }

            let entry = entriesByWorkoutId[workout.id]
                .flatMap { candidate -> WorkoutSyncOutboxEntry? in
                    candidate.ownerUserId == currentUserId ? candidate : nil
                }

            // A schedule armed against bytes the climber has since changed is not a statement
            // about the bytes now on offer. Starting the series over is what keeps an edited
            // workout from waiting out a stop it never earned - or, once stopped, from being
            // dropped from every automatic pass forever.
            if let entry,
               !entry.isScheduledForPayloadRevision(at: workout.lastModifiedAt, now: now) {
                entry.resetForNewPayloadRevision(now: now)
                didResetSchedule = true
            }

            if wasManuallyRequested {
                workouts.append(workout)
                continue
            }

            guard workout.remoteSyncStatus != .rejected else { continue }
            guard entry?.isDueForAutomaticAttempt(now: now) ?? true else { continue }
            workouts.append(workout)
        }

        if didResetSchedule {
            try modelContext.save()
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
                noteOutcomeReached(forWorkoutId: workout.id)
            }
        }

        return snapshots
    }

    /// Records that a climb reached a verdict, for a tap that is waiting to hear one.
    ///
    /// Deliberately silent for a workout nobody asked about: the map holds only taps in flight, so
    /// it cannot grow with the queue.
    func noteOutcomeReached(forWorkoutId workoutId: UUID) {
        guard manualRetryReachedOutcome[workoutId] != nil else { return }
        manualRetryReachedOutcome[workoutId] = true
    }

    /// Waits for the pass that is already running, without starting one.
    func awaitRunningPass() async {
        guard isProcessingPendingWorkouts else { return }

        await withCheckedContinuation { continuation in
            passCompletionWaiters.append(continuation)
        }
    }

    /// What the surface renders, derived from whether the climb is in the cloud - never from what
    /// the retry machinery happens to be doing.
    func derivedPresentation(
        for workout: Workout,
        modelContext: ModelContext
    ) -> WorkoutSyncPresentation {
        if let settled = settledPresentation(for: workout) { return settled }

        let entry = try? outboxEntry(
            forWorkoutId: workout.id,
            ownerUserId: workout.ownerUserId ?? "",
            createIfMissing: false,
            modelContext: modelContext
        )

        return attentionPresentation(for: workout, entry: entry)
    }

    /// The states that need no schedule to answer, so a batch can settle them before any query.
    func settledPresentation(for workout: Workout) -> WorkoutSyncPresentation? {
        if workout.isSyncedToCloud {
            return warnedWorkoutIds.contains(workout.id) ? .synced : .hidden
        }

        if inFlightWorkoutIds.contains(workout.id) {
            // The row keeps saying `Couldn't sync this climb` while the control says `SYNCING`, so
            // tapping can never make the warning disappear.
            return warnedWorkoutIds.contains(workout.id) ? .couldNotSyncRetrying : .syncing
        }

        return nil
    }

    /// Whether a climb that is not in the cloud is one the climber is meant to know about.
    func attentionPresentation(
        for workout: Workout,
        entry: WorkoutSyncOutboxEntry?
    ) -> WorkoutSyncPresentation {
        // An entry belonging to another account, or armed against bytes the climber has since
        // changed, says nothing about the climb in front of them.
        let now = self.now()
        let entry = entry.flatMap { candidate -> WorkoutSyncOutboxEntry? in
            guard candidate.ownerUserId == (workout.ownerUserId ?? "") else { return nil }
            guard candidate.isScheduledForPayloadRevision(
                at: workout.lastModifiedAt,
                now: now
            ) else {
                return nil
            }
            return candidate
        }

        // Once a climber has been told, the surface stays loud until the climb actually lands.
        //
        // Without this latch a refused manual retry re-derives the status from the automatic
        // series, drops `rejected` back to `failed`, and - if the quiet window has not elapsed -
        // the warning silently becomes `Syncing`. That is the disappearing-warning defect arriving
        // through a different door, and it reads as success.
        let needsAttention = workout.remoteSyncStatus == .rejected ||
            warnedWorkoutIds.contains(workout.id) ||
            (entry?.requiresAttention(now: now) ?? false)
        guard needsAttention else { return .syncing }

        warnedWorkoutIds.insert(workout.id)
        return connectivityService.isConnected ? .couldNotSync : .couldNotSyncOffline
    }

    /// Every persisted schedule in the store, indexed by the workout it belongs to.
    ///
    /// Only workouts that are not yet in the cloud carry one, so this is bounded by the backlog
    /// rather than by the climber's history.
    func outboxEntriesByWorkoutId(
        modelContext: ModelContext
    ) throws -> [UUID: WorkoutSyncOutboxEntry] {
        try modelContext.fetch(FetchDescriptor<WorkoutSyncOutboxEntry>())
            .reduce(into: [:]) { index, entry in index[entry.workoutId] = entry }
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
                entry.workoutId == workoutId && entry.ownerUserId == ownerUserId
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
        try deleteOutboxEntries(forWorkoutId: workoutId, modelContext: modelContext)
        try modelContext.save()
    }

    /// Removes the schedule without committing, for callers that own the surrounding save.
    func deleteOutboxEntries(forWorkoutId workoutId: UUID, modelContext: ModelContext) throws {
        let descriptor = FetchDescriptor<WorkoutSyncOutboxEntry>(
            predicate: #Predicate<WorkoutSyncOutboxEntry> { entry in
                entry.workoutId == workoutId
            }
        )

        for entry in try modelContext.fetch(descriptor) {
            modelContext.delete(entry)
        }
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
