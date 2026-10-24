import Foundation
import SwiftData
import Testing
@testable import AscendApp

/// A sync pass of a persistent-cache process on a volume at the floor defers rather than runs.
///
/// The upsert and the delete are both Firestore writes, and a Firestore write is a LevelDB
/// transaction before it is a network call: `LocalStore::WriteLocally` commits the mutation
/// to the cache first, and on a full volume that commit aborts the process. The coordinator
/// already knows how to leave the outbox exactly as it found it (that is what a kill switch
/// does), so the guard reuses that: nothing is attempted, nothing is counted, nothing is
/// marked, and the next trigger after the phone has room runs the pass as if nothing happened.
@MainActor
struct WorkoutSyncLowDiskDeferralTests {
    @Test
    func aFullVolumeLeavesThePendingWorkoutUntouchedAndAsksTheRepositoryNothing() async throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout()
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: workout.createdAt)
        modelContext.insert(workout)
        try modelContext.save()

        // The kill switch off and room at launch - the persistent cache - then the volume fills.
        let volume = ScriptedVolume(availableBytes: FirestoreDiskPolicy.lowDiskFloorBytes * 2, importantUsageBytes: nil)
        let diskGuard = makeGuard(volume: volume, featureFlags: .withMemoryCacheOff())
        volume.freeBytes = 0
        let remoteRepository = LowDiskFakeWorkoutRemoteRepository()
        let diagnostics = SpyDiagnosticsRecorder()
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: LowDiskFakeHeartRateStorageRepository(),
            operationTimeoutSeconds: 1,
            diskGuard: diskGuard,
            diagnostics: diagnostics
        )

        await coordinator.processPendingWorkouts(modelContext: modelContext, currentUserId: "user-123")
        await coordinator.processPendingWorkouts(modelContext: modelContext, currentUserId: "user-123")

        #expect(await remoteRepository.upsertCount() == 0)
        let stored = try #require(modelContext.fetch(FetchDescriptor<Workout>()).first)
        #expect(stored.remoteSyncStatus == .pendingUpsert)
        #expect(stored.lastRemoteSyncAt == nil)
        #expect(try modelContext.fetch(FetchDescriptor<WorkoutSyncOutboxEntry>()).isEmpty, "no attempt was consumed")
        #expect(
            diagnostics.events.filter { $0.name == "workout_sync_deferred_low_disk" }.count == 1,
            "the deferral is recorded once, not once per trigger"
        )
        #expect(diagnostics.events.first { $0.name == "workout_sync_deferred_low_disk" }?.details["free_bytes"] == "0")

        volume.freeBytes = FirestoreDiskPolicy.lowDiskFloorBytes * 2
        await coordinator.processPendingWorkouts(modelContext: modelContext, currentUserId: "user-123")

        #expect(await remoteRepository.upsertCount() == 1)
        let synced = try #require(modelContext.fetch(FetchDescriptor<Workout>()).first)
        #expect(synced.remoteSyncStatus == .synced)
    }

    @Test
    func aFullVolumeLeavesAPendingDeletionQueued() async throws {
        let modelContext = try makeModelContext()
        let deletion = PendingWorkoutDeletion(workoutId: UUID(), ownerUserId: "user-123")
        modelContext.insert(deletion)
        try modelContext.save()

        let volume = ScriptedVolume(availableBytes: FirestoreDiskPolicy.lowDiskFloorBytes * 2, importantUsageBytes: nil)
        let diskGuard = makeGuard(volume: volume, featureFlags: .withMemoryCacheOff())
        volume.freeBytes = 0
        let remoteRepository = LowDiskFakeWorkoutRemoteRepository()
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: LowDiskFakeHeartRateStorageRepository(),
            operationTimeoutSeconds: 1,
            diskGuard: diskGuard,
            diagnostics: SpyDiagnosticsRecorder()
        )

        await coordinator.processPendingWorkouts(modelContext: modelContext, currentUserId: "user-123")

        #expect(await remoteRepository.deleteCount() == 0)
        #expect(try modelContext.fetch(FetchDescriptor<PendingWorkoutDeletion>()).count == 1)
    }

    @Test
    func aMemoryCacheProcessSyncsOnAFullVolume() async throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout()
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: workout.createdAt)
        modelContext.insert(workout)
        try modelContext.save()

        let diskGuard = makeGuard(volume: ScriptedVolume(availableBytes: 0, importantUsageBytes: nil))
        #expect(diskGuard.cacheMode == .memory)
        let remoteRepository = LowDiskFakeWorkoutRemoteRepository()
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: LowDiskFakeHeartRateStorageRepository(),
            operationTimeoutSeconds: 1,
            diskGuard: diskGuard,
            diagnostics: SpyDiagnosticsRecorder()
        )

        await coordinator.processPendingWorkouts(modelContext: modelContext, currentUserId: "user-123")

        #expect(await remoteRepository.upsertCount() == 1)
    }

    private func makeGuard(
        volume: ScriptedVolume,
        featureFlags: RemoteFeatureFlagStore = RemoteFeatureFlagStore()
    ) -> FirestoreDiskGuard {
        let diskGuard = FirestoreDiskGuard(
            freeSpace: volume,
            featureFlags: featureFlags,
            diagnostics: SpyDiagnosticsRecorder(),
            telemetry: { _ in }
        )
        diskGuard.decideCacheMode()
        return diskGuard
    }

    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: AscendLocalStore.schema,
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

private actor LowDiskFakeWorkoutRemoteRepository: WorkoutRemoteRepositoryProtocol {
    private var upserts = 0
    private var deletes = 0

    func fetchWorkouts(userId: String) async throws -> [RemoteWorkoutRecord] { [] }

    func upsertWorkout(userId: String, workoutId: UUID, document: FirestoreWorkoutDocument) async throws {
        upserts += 1
    }

    func deleteWorkout(userId: String, workoutId: UUID) async throws {
        deletes += 1
    }

    func upsertCount() -> Int { upserts }
    func deleteCount() -> Int { deletes }
}

private actor LowDiskFakeHeartRateStorageRepository: WorkoutHeartRateStorageRepositoryProtocol {
    func uploadHeartRateSeries(
        userId: String,
        workoutId: UUID,
        blob: WorkoutHeartRateStorageBlob
    ) async throws -> FirestoreWorkoutHeartRateSeriesReference {
        FirestoreWorkoutHeartRateSeriesReference(
            storagePath: "users/\(userId)/workout_heart_rate/\(workoutId.uuidString).json.gz",
            sampleCount: blob.samples.count,
            seriesStartAt: blob.samples.first?.timestamp ?? .distantPast,
            seriesEndAt: blob.samples.last?.timestamp ?? .distantPast
        )
    }

    func deleteHeartRateSeriesIfPresent(userId: String, workoutId: UUID) async throws {}

    func downloadHeartRateSeries(
        userId: String,
        workoutId: UUID,
        reference: FirestoreWorkoutHeartRateSeriesReference
    ) async throws -> WorkoutHeartRateStorageBlob {
        throw WorkoutHeartRateSidecarError.missing
    }
}
