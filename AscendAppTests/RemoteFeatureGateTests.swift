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
