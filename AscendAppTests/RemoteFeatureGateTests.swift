import Foundation
import SwiftData
import Testing
@testable import AscendApp

/// What a flipped kill switch actually does to the data paths it guards.
///
/// The invariant under test everywhere here: a blocked path defers its work rather than dropping
/// it. Pending state must survive untouched so the queue drains on its own once the flag is back
/// on.
@MainActor
struct RemoteFeatureGateTests {
    @Test
    func killingCloudBackupWritesLeavesTheWorkoutPendingRatherThanFailed() async throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout()
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: workout.createdAt)
        modelContext.insert(workout)
        try modelContext.save()

        let remoteRepository = FakeGatedWorkoutRemoteRepository()
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: FakeGatedHeartRateStorageRepository(),
            featureFlags: makeStore(disabling: .workoutCloudBackupWrites),
            operationTimeoutSeconds: 1
        )

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        #expect(await remoteRepository.upsertCount() == 0)
        let stored = try #require(modelContext.fetch(FetchDescriptor<Workout>()).first)
        #expect(stored.remoteSyncStatus == .pendingUpsert)
        #expect(stored.lastRemoteSyncAt == nil)
    }

    @Test
    func cloudBackupWritesRunWhileTheFlagIsOn() async throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout()
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: workout.createdAt)
        modelContext.insert(workout)
        try modelContext.save()

        let remoteRepository = FakeGatedWorkoutRemoteRepository()
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: FakeGatedHeartRateStorageRepository(),
            featureFlags: RemoteFeatureFlagStore(),
            operationTimeoutSeconds: 1
        )

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        #expect(await remoteRepository.upsertCount() == 1)
        let stored = try #require(modelContext.fetch(FetchDescriptor<Workout>()).first)
        #expect(stored.remoteSyncStatus == .synced)
    }

    /// Turning the switch back on must drain the queue with no further user action.
    @Test
    func restoringCloudBackupWritesFlushesTheDeferredWorkout() async throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout()
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: workout.createdAt)
        modelContext.insert(workout)
        try modelContext.save()

        let remoteRepository = FakeGatedWorkoutRemoteRepository()
        let store = makeStore(disabling: .workoutCloudBackupWrites)
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: FakeGatedHeartRateStorageRepository(),
            featureFlags: store,
            operationTimeoutSeconds: 1
        )
        await coordinator.processPendingWorkouts(modelContext: modelContext, currentUserId: "user-123")
        #expect(await remoteRepository.upsertCount() == 0)

        store.apply(.shippedDefaults)
        await coordinator.processPendingWorkouts(modelContext: modelContext, currentUserId: "user-123")

        #expect(await remoteRepository.upsertCount() == 1)
        let stored = try #require(modelContext.fetch(FetchDescriptor<Workout>()).first)
        #expect(stored.remoteSyncStatus == .synced)
    }

    @Test
    func killingRemoteDeletesKeepsTheTombstoneQueued() async throws {
        let modelContext = try makeModelContext()
        modelContext.insert(
            PendingWorkoutDeletion(workoutId: UUID(), ownerUserId: "user-123")
        )
        try modelContext.save()

        let remoteRepository = FakeGatedWorkoutRemoteRepository()
        let heartRateRepository = FakeGatedHeartRateStorageRepository()
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: heartRateRepository,
            featureFlags: makeStore(disabling: .workoutRemoteDeletes),
            operationTimeoutSeconds: 1
        )

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        #expect(await remoteRepository.deleteCount() == 0)
        #expect(await heartRateRepository.deleteCount() == 0)
        let pending = try modelContext.fetch(FetchDescriptor<PendingWorkoutDeletion>())
        #expect(pending.count == 1)
        #expect(pending.first?.lastError == nil)
        #expect(pending.first?.retryCount == 0)
    }

    /// The two workout switches are independent: killing deletes must not stop backups.
    @Test
    func killingRemoteDeletesDoesNotStopCloudBackupWrites() async throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout()
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: workout.createdAt)
        modelContext.insert(workout)
        modelContext.insert(PendingWorkoutDeletion(workoutId: UUID(), ownerUserId: "user-123"))
        try modelContext.save()

        let remoteRepository = FakeGatedWorkoutRemoteRepository()
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: FakeGatedHeartRateStorageRepository(),
            featureFlags: makeStore(disabling: .workoutRemoteDeletes),
            operationTimeoutSeconds: 1
        )

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        #expect(await remoteRepository.upsertCount() == 1)
        #expect(await remoteRepository.deleteCount() == 0)
    }

    /// A workout awaiting deletion must not be pushed back up while the delete switch is off.
    @Test
    func aWorkoutAwaitingDeletionIsNotUpsertedWhileDeletesAreKilled() async throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout()
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: workout.createdAt)
        modelContext.insert(workout)
        modelContext.insert(
            PendingWorkoutDeletion(workoutId: workout.id, ownerUserId: "user-123")
        )
        try modelContext.save()

        let remoteRepository = FakeGatedWorkoutRemoteRepository()
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: FakeGatedHeartRateStorageRepository(),
            featureFlags: makeStore(disabling: .workoutRemoteDeletes),
            operationTimeoutSeconds: 1
        )

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        #expect(await remoteRepository.upsertCount() == 0)
        #expect(await remoteRepository.deleteCount() == 0)
    }

    @Test
    func killingCloudRestoreSkipsHydrationWithoutFetching() async throws {
        let modelContext = try makeModelContext()
        let remoteRepository = FakeGatedWorkoutRemoteRepository()

        let restored = try await WorkoutHydrationService.hydrateIfNeeded(
            modelContext: modelContext,
            currentUserId: "user-123",
            remoteRepository: remoteRepository,
            heartRateStorageRepository: FakeGatedHeartRateStorageRepository(),
            featureFlags: makeStore(disabling: .workoutCloudRestore)
        )

        #expect(restored == 0)
        #expect(await remoteRepository.fetchCount() == 0)
    }

    /// The gate sits ahead of the "already hydrated this session" bookkeeping, so a deferred
    /// restore is still treated as the initial one when the flag returns.
    @Test
    func restoringCloudRestoreStillPerformsTheInitialHydration() async throws {
        WorkoutHydrationService.resetSessionTrackingForTesting()
        let modelContext = try makeModelContext()
        let remoteRepository = FakeGatedWorkoutRemoteRepository()
        let store = makeStore(disabling: .workoutCloudRestore)

        _ = try await WorkoutHydrationService.hydrateIfNeeded(
            modelContext: modelContext,
            currentUserId: "user-123",
            remoteRepository: remoteRepository,
            heartRateStorageRepository: FakeGatedHeartRateStorageRepository(),
            featureFlags: store
        )
        #expect(await remoteRepository.fetchCount() == 0)

        store.apply(.shippedDefaults)
        _ = try await WorkoutHydrationService.hydrateIfNeeded(
            modelContext: modelContext,
            currentUserId: "user-123",
            remoteRepository: remoteRepository,
            heartRateStorageRepository: FakeGatedHeartRateStorageRepository(),
            featureFlags: store
        )

        #expect(await remoteRepository.fetchCount() == 1)
    }

    @Test
    func killingLocalMigrationsDefersTheBackfillWithoutStampingItDone() throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout()
        modelContext.insert(workout)
        try modelContext.save()

        let userDefaults = try #require(UserDefaults(suiteName: "RemoteFeatureGateTests.\(UUID().uuidString)"))
        let store = makeStore(disabling: .localDataMigrations)

        try WorkoutRemoteSyncMigrationService.runIfNeeded(
            modelContext: modelContext,
            currentUserId: "user-123",
            userDefaults: userDefaults,
            featureFlags: store
        )

        #expect(workout.ownerUserId == nil)
        let versionKey = WorkoutRemoteSyncMigrationService.migrationVersionKey(for: "user-123")
        #expect(userDefaults.bool(forKey: versionKey) == false)

        store.apply(.shippedDefaults)
        try WorkoutRemoteSyncMigrationService.runIfNeeded(
            modelContext: modelContext,
            currentUserId: "user-123",
            userDefaults: userDefaults,
            featureFlags: store
        )

        #expect(workout.ownerUserId == "user-123")
        #expect(userDefaults.bool(forKey: versionKey) == true)
    }

    /// The media queue's sweep deletes local originals, so a bad build here loses files that
    /// exist nowhere else yet. Killing it must leave both the queue and the files alone.
    @Test
    func killingMediaUploadsLeavesTheQueueAndLocalFilesAlone() async throws {
        let modelContext = try makeModelContext()
        modelContext.insert(
            PendingMediaUpload(
                workoutId: UUID(),
                localFileName: "pending-media.jpg",
                mediaType: "photo",
                orderIndex: 0
            )
        )
        try modelContext.save()

        let photoRepository = FakeGatedPhotoRepository()
        let manager = MediaUploadManager(
            photoRepo: photoRepository,
            featureFlags: makeStore(disabling: .workoutMediaUploads)
        )

        await manager.processPendingUploads(modelContext: modelContext)

        #expect(await photoRepository.uploadCount() == 0)
        let pending = try modelContext.fetch(FetchDescriptor<PendingMediaUpload>())
        #expect(pending.count == 1)
        #expect(pending.first?.status == PendingUploadStatus.pending.rawValue)
        #expect(pending.first?.retryCount == 0)
    }

    /// A user-triggered retry reaches the same upload-then-delete-the-original path as the sweep,
    /// so the switch has to hold it too - and hold it before the rows are touched.
    @Test
    func killingMediaUploadsLeavesAUserTriggeredRetryQueuedAndUntouched() async throws {
        let modelContext = try makeModelContext()
        let workoutId = UUID()
        let pending = PendingMediaUpload(
            workoutId: workoutId,
            localFileName: "failed-media.jpg",
            mediaType: "photo",
            orderIndex: 0
        )
        pending.uploadStatus = .failed
        pending.retryCount = 2
        pending.lastError = "previous failure"
        modelContext.insert(pending)
        try modelContext.save()

        let photoRepository = FakeGatedPhotoRepository()
        let manager = MediaUploadManager(
            photoRepo: photoRepository,
            featureFlags: makeStore(disabling: .workoutMediaUploads)
        )

        await manager.retryFailedUploads(for: workoutId, modelContext: modelContext)

        #expect(await photoRepository.uploadCount() == 0)
        let stored = try modelContext.fetch(FetchDescriptor<PendingMediaUpload>())
        #expect(stored.count == 1)
        #expect(stored.first?.status == PendingUploadStatus.failed.rawValue)
        #expect(stored.first?.retryCount == 2)
        #expect(stored.first?.lastError == "previous failure")
    }

    /// A switch thrown while a batch is already running has to stop the next item, not wait out the
    /// remaining retries. Every row the loop never reached must be untouched so it drains later.
    @Test
    func killingMediaUploadsMidBatchHaltsBeforeTheNextItem() async throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout()
        modelContext.insert(workout)
        for index in 0..<3 {
            modelContext.insert(
                PendingMediaUpload(
                    workoutId: workout.id,
                    localFileName: "queued-media-\(index).jpg",
                    mediaType: "photo",
                    orderIndex: index
                )
            )
        }
        try modelContext.save()

        let store = RemoteFeatureFlagStore()
        let manager = MediaUploadManager(photoRepo: FakeGatedPhotoRepository(), featureFlags: store)

        let processing = Task { await manager.processPendingUploads(modelContext: modelContext) }
        #expect(await firstUploadStarted(in: modelContext))

        store.apply(
            RemoteFeatureFlagSnapshot.resolving(
                remoteValues: [RemoteFeatureFlag.workoutMediaUploads.key: false]
            )
        )
        await processing.value

        let stored = try modelContext.fetch(
            FetchDescriptor<PendingMediaUpload>(
                sortBy: [SortDescriptor(\PendingMediaUpload.orderIndex)]
            )
        )
        #expect(stored.count == 3)
        #expect(stored.first?.status == PendingUploadStatus.failed.rawValue)
        for untouched in stored.dropFirst() {
            #expect(untouched.status == PendingUploadStatus.pending.rawValue)
            #expect(untouched.retryCount == 0)
            #expect(untouched.lastError == nil)
        }
    }

    /// `processUpload` stamps the row it is working on before its first attempt, which is the only
    /// signal that the loop has entered an item rather than merely been asked to start.
    private func firstUploadStarted(in modelContext: ModelContext) async -> Bool {
        for _ in 0..<200 {
            let rows = try? modelContext.fetch(
                FetchDescriptor<PendingMediaUpload>(
                    sortBy: [SortDescriptor(\PendingMediaUpload.orderIndex)]
                )
            )
            if rows?.first?.status == PendingUploadStatus.uploading.rawValue { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    /// A held queue must not claim to be uploading. The rows stay queued either way, so the only
    /// thing at stake is whether the banner tells the truth for as long as the switch is thrown.
    @Test
    func killingMediaUploadsStopsTheBannerClaimingAnUploadIsInProgress() {
        #expect(
            MediaUploadManager.resolvedStatus(pendingCount: 3, failedCount: 0, isQueueActive: false)
                == MediaUploadStatus.none
        )
        #expect(
            MediaUploadManager.resolvedStatus(pendingCount: 3, failedCount: 0, isQueueActive: true)
                == .uploading(current: 1, total: 3)
        )
    }

    /// A failure that already happened is still true while the switch is off, so the banner keeps
    /// reporting it. Only the retry affordance goes away, in `MediaUploadBanner`.
    @Test
    func killingMediaUploadsStillReportsFailuresThatAlreadyHappened() {
        #expect(
            MediaUploadManager.resolvedStatus(pendingCount: 1, failedCount: 2, isQueueActive: false)
                == .failed(count: 2)
        )
        #expect(
            MediaUploadManager.resolvedStatus(pendingCount: 0, failedCount: 0, isQueueActive: false)
                == MediaUploadStatus.none
        )
    }

    /// The banner reads this to decide whether to offer retry at all.
    @Test
    func theUploadQueueReportsWhetherItIsHeld() {
        let held = MediaUploadManager(
            photoRepo: FakeGatedPhotoRepository(),
            featureFlags: makeStore(disabling: .workoutMediaUploads)
        )
        let running = MediaUploadManager(
            photoRepo: FakeGatedPhotoRepository(),
            featureFlags: RemoteFeatureFlagStore()
        )

        #expect(held.isUploadQueueActive == false)
        #expect(running.isUploadQueueActive == true)
    }

    /// Turning the switch back on has to drain what accumulated while it was off, from the same
    /// user-triggered retry that the gate blocked.
    @Test
    func turningMediaUploadsBackOnLetsTheRetryRunAgain() async throws {
        let modelContext = try makeModelContext()
        let workoutId = UUID()
        let pending = PendingMediaUpload(
            workoutId: workoutId,
            localFileName: "failed-media.jpg",
            mediaType: "photo",
            orderIndex: 0
        )
        pending.uploadStatus = .failed
        pending.retryCount = 2
        modelContext.insert(pending)
        try modelContext.save()

        let manager = MediaUploadManager(
            photoRepo: FakeGatedPhotoRepository(),
            featureFlags: RemoteFeatureFlagStore()
        )

        await manager.retryFailedUploads(for: workoutId, modelContext: modelContext)

        let stored = try modelContext.fetch(FetchDescriptor<PendingMediaUpload>())
        #expect(stored.first?.retryCount == 0)
        #expect(stored.first?.status != PendingUploadStatus.failed.rawValue)
    }

    private func makeStore(disabling flag: RemoteFeatureFlag) -> RemoteFeatureFlagStore {
        RemoteFeatureFlagStore(
            snapshot: RemoteFeatureFlagSnapshot.resolving(remoteValues: [flag.key: false])
        )
    }

    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            PendingWorkoutDeletion.self,
            PendingMediaUpload.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeWorkout() -> Workout {
        Workout(
            name: "Workout",
            date: Date(timeIntervalSince1970: 1_780_000_000),
            duration: 1_800,
            steps: 1_000,
            floors: Workout.stepsToFloors(1_000, stepsPerFloor: 16),
            stepsPerFloor: 16,
            notes: "Test",
            source: .manual
        )
    }
}

private actor FakeGatedWorkoutRemoteRepository: WorkoutRemoteRepositoryProtocol {
    private var fetches = 0
    private var upserts = 0
    private var deletes = 0

    func fetchWorkouts(userId: String) async throws -> [RemoteWorkoutRecord] {
        fetches += 1
        return []
    }

    func upsertWorkout(
        userId: String,
        workoutId: UUID,
        document: FirestoreWorkoutDocument
    ) async throws {
        upserts += 1
    }

    func deleteWorkout(userId: String, workoutId: UUID) async throws {
        deletes += 1
    }

    func fetchCount() -> Int { fetches }
    func upsertCount() -> Int { upserts }
    func deleteCount() -> Int { deletes }
}

private actor FakeGatedPhotoRepository: PhotoRepositoryProtocol {
    private var uploads = 0

    func upload(_ data: Data, filename: String) async throws -> URL {
        uploads += 1
        return URL(string: "https://example.invalid/\(filename)")!
    }

    func delete(url: URL) async throws {}

    func uploadCount() -> Int { uploads }
}

private actor FakeGatedHeartRateStorageRepository: WorkoutHeartRateStorageRepositoryProtocol {
    private var uploads = 0
    private var deletes = 0

    func uploadHeartRateSeries(
        userId: String,
        workoutId: UUID,
        blob: WorkoutHeartRateStorageBlob
    ) async throws -> FirestoreWorkoutHeartRateSeriesReference {
        uploads += 1
        return FirestoreWorkoutHeartRateSeriesReference(
            storagePath: "users/\(userId)/workout_heart_rate/\(workoutId.uuidString).json.gz",
            sampleCount: blob.samples.count,
            seriesStartAt: blob.samples.first?.timestamp ?? .distantPast,
            seriesEndAt: blob.samples.last?.timestamp ?? .distantPast
        )
    }

    func deleteHeartRateSeriesIfPresent(userId: String, workoutId: UUID) async throws {
        deletes += 1
    }

    func downloadHeartRateSeries(
        userId: String,
        workoutId: UUID,
        reference: FirestoreWorkoutHeartRateSeriesReference
    ) async throws -> WorkoutHeartRateStorageBlob {
        throw WorkoutHeartRateSidecarError.missing
    }

    func uploadCount() -> Int { uploads }
    func deleteCount() -> Int { deletes }
}
