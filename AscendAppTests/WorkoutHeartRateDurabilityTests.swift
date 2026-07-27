import Foundation
import SwiftData
import Testing
@testable import AscendApp

@MainActor
struct WorkoutHeartRateDurabilityTests {
    @Test
    func cleanSecondDeviceRestoreRecoversHeartRateChartSamples() async throws {
        let userId = "second-device-heart-rate-user"
        let workoutId = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-FFFFFFFFFFFF")!
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = [
            HeartRateDataPoint(timestamp: start, heartRate: 118),
            HeartRateDataPoint(timestamp: start.addingTimeInterval(60), heartRate: 126),
            HeartRateDataPoint(timestamp: start.addingTimeInterval(120), heartRate: 139)
        ]
        let sourceWorkout = Workout(
            name: "Cross-device climb",
            date: start,
            duration: 1_200,
            steps: 800,
            floors: 50,
            stepsPerFloor: 16,
            notes: "",
            avgHeartRate: 128,
            maxHeartRate: 139,
            heartRateTimeSeries: samples,
            source: .appleHealth
        )
        sourceWorkout.id = workoutId
        sourceWorkout.markPendingRemoteUpsert(ownerUserId: userId, modifiedAt: start)
        let snapshot = try WorkoutRemoteSyncMapper.snapshot(from: sourceWorkout)
        let sidecarRepository = HeartRateDurabilitySidecarRepository(
            blob: try #require(snapshot.heartRateBlob)
        )

        let cleanSecondDeviceContext = try makeContext()
        _ = try await WorkoutHydrationService.hydrateIfNeeded(
            modelContext: cleanSecondDeviceContext,
            currentUserId: userId,
            remoteRepository: HeartRateDurabilityRemoteRepository(
                records: [
                    RemoteWorkoutRecord(
                        workoutId: workoutId,
                        document: snapshot.document
                    )
                ]
            ),
            heartRateStorageRepository: sidecarRepository
        )

        let restoredWorkout = try #require(
            try cleanSecondDeviceContext.fetch(FetchDescriptor<Workout>()).first
        )
        #expect(restoredWorkout.heartRateTimeSeries == samples)

        _ = try await WorkoutHydrationService.hydrateIfNeeded(
            modelContext: cleanSecondDeviceContext,
            currentUserId: userId,
            remoteRepository: HeartRateDurabilityRemoteRepository(
                records: [RemoteWorkoutRecord(workoutId: workoutId, document: snapshot.document)]
            ),
            heartRateStorageRepository: sidecarRepository
        )
        #expect(restoredWorkout.heartRateTimeSeries == samples)
        #expect(await sidecarRepository.downloadCount() == 1)
    }

    @Test
    func restoreClassifiesPermanentAndTransientSidecarFailures() async throws {
        try await verifyFailure(.missing, expectedStatus: .unavailable)
        try await verifyFailure(.integrityMismatch, expectedStatus: .unavailable)
        try await verifyFailure(.transient, expectedStatus: .retryPending)
    }

    @Test
    func repeatedHydrationRetriesTransientFailureAndRestoresSamples() async throws {
        let userId = "transient-retry-user"
        let workoutId = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = [
            HeartRateDataPoint(timestamp: start, heartRate: 121),
            HeartRateDataPoint(timestamp: start.addingTimeInterval(60), heartRate: 134)
        ]
        let reference = FirestoreWorkoutHeartRateSeriesReference(
            storagePath: WorkoutHeartRateStoragePath.path(userId: userId, workoutId: workoutId),
            sampleCount: samples.count,
            seriesStartAt: start,
            seriesEndAt: start.addingTimeInterval(60)
        )
        let document = FirestoreWorkoutDocument(
            userId: userId,
            name: "Transient restore",
            startedAt: start,
            durationSeconds: 600,
            steps: 500,
            floors: 31,
            stepsPerFloor: 16,
            notes: "",
            source: WorkoutSource.appleHealth.rawValue,
            climbId: nil,
            integrityLevel: DataIntegrityLevel.verified.rawValue,
            createdAt: start,
            updatedAt: start,
            heartRateSeries: reference
        )
        let repository = RetryingHeartRateDurabilitySidecarRepository(
            blob: WorkoutHeartRateStorageBlob(
                workoutId: WorkoutDocumentID.canonicalString(for: workoutId),
                samples: samples
            )
        )
        let context = try makeContext()
        let remoteRepository = HeartRateDurabilityRemoteRepository(
            records: [RemoteWorkoutRecord(workoutId: workoutId, document: document)]
        )

        _ = try await WorkoutHydrationService.hydrateIfNeeded(
            modelContext: context,
            currentUserId: userId,
            remoteRepository: remoteRepository,
            heartRateStorageRepository: repository
        )
        var workout = try #require(try context.fetch(FetchDescriptor<Workout>()).first)
        #expect(workout.heartRateRestoreStatus == .retryPending)

        _ = try await WorkoutHydrationService.hydrateIfNeeded(
            modelContext: context,
            currentUserId: userId,
            remoteRepository: remoteRepository,
            heartRateStorageRepository: repository
        )
        workout = try #require(try context.fetch(FetchDescriptor<Workout>()).first)
        #expect(workout.heartRateRestoreStatus == .ready)
        #expect(workout.heartRateTimeSeries == samples)
        #expect(await repository.downloadCount() == 2)
    }

    private func verifyFailure(
        _ error: WorkoutHeartRateSidecarError,
        expectedStatus: WorkoutHeartRateRestoreStatus
    ) async throws {
        let workoutId = UUID()
        let userId = "failure-\(error.diagnosticCode)-\(workoutId.uuidString)"
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let reference = FirestoreWorkoutHeartRateSeriesReference(
            storagePath: WorkoutHeartRateStoragePath.path(userId: userId, workoutId: workoutId),
            sampleCount: 2,
            seriesStartAt: start,
            seriesEndAt: start.addingTimeInterval(60)
        )
        let document = FirestoreWorkoutDocument(
            userId: userId,
            name: "Restore failure",
            startedAt: start,
            durationSeconds: 600,
            steps: 500,
            floors: 31,
            stepsPerFloor: 16,
            notes: "",
            source: WorkoutSource.appleHealth.rawValue,
            climbId: nil,
            integrityLevel: DataIntegrityLevel.verified.rawValue,
            createdAt: start,
            updatedAt: start,
            avgHeartRateBpm: 124,
            maxHeartRateBpm: 132,
            heartRateSeries: reference
        )
        let context = try makeContext()

        _ = try await WorkoutHydrationService.hydrateIfNeeded(
            modelContext: context,
            currentUserId: userId,
            remoteRepository: HeartRateDurabilityRemoteRepository(
                records: [RemoteWorkoutRecord(workoutId: workoutId, document: document)]
            ),
            heartRateStorageRepository: FailingHeartRateDurabilitySidecarRepository(error: error)
        )

        let workout = try #require(try context.fetch(FetchDescriptor<Workout>()).first)
        #expect(workout.heartRateTimeSeries.isEmpty)
        #expect(workout.heartRateRestoreStatus == expectedStatus)
        #expect(workout.heartRateRestoreErrorCode == error.diagnosticCode)
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            ClimbAttempt.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }
}

private struct FailingHeartRateDurabilitySidecarRepository: WorkoutHeartRateStorageRepositoryProtocol {
    let error: WorkoutHeartRateSidecarError

    func uploadHeartRateSeries(
        userId: String,
        workoutId: UUID,
        blob: WorkoutHeartRateStorageBlob
    ) async throws -> FirestoreWorkoutHeartRateSeriesReference {
        throw error
    }

    func downloadHeartRateSeries(
        userId: String,
        workoutId: UUID,
        reference: FirestoreWorkoutHeartRateSeriesReference
    ) async throws -> WorkoutHeartRateStorageBlob {
        throw error
    }

    func deleteHeartRateSeriesIfPresent(userId: String, workoutId: UUID) async throws {}
}

private actor HeartRateDurabilitySidecarRepository: WorkoutHeartRateStorageRepositoryProtocol {
    let blob: WorkoutHeartRateStorageBlob
    private var downloads = 0

    init(blob: WorkoutHeartRateStorageBlob) {
        self.blob = blob
    }

    func uploadHeartRateSeries(
        userId: String,
        workoutId: UUID,
        blob: WorkoutHeartRateStorageBlob
    ) async throws -> FirestoreWorkoutHeartRateSeriesReference {
        throw WorkoutHeartRateSidecarError.transient
    }

    func downloadHeartRateSeries(
        userId: String,
        workoutId: UUID,
        reference: FirestoreWorkoutHeartRateSeriesReference
    ) async throws -> WorkoutHeartRateStorageBlob {
        downloads += 1
        return blob
    }

    func deleteHeartRateSeriesIfPresent(userId: String, workoutId: UUID) async throws {}

    func downloadCount() -> Int {
        downloads
    }
}

private actor RetryingHeartRateDurabilitySidecarRepository: WorkoutHeartRateStorageRepositoryProtocol {
    let blob: WorkoutHeartRateStorageBlob
    private var downloads = 0

    init(blob: WorkoutHeartRateStorageBlob) {
        self.blob = blob
    }

    func uploadHeartRateSeries(
        userId: String,
        workoutId: UUID,
        blob: WorkoutHeartRateStorageBlob
    ) async throws -> FirestoreWorkoutHeartRateSeriesReference {
        throw WorkoutHeartRateSidecarError.transient
    }

    func downloadHeartRateSeries(
        userId: String,
        workoutId: UUID,
        reference: FirestoreWorkoutHeartRateSeriesReference
    ) async throws -> WorkoutHeartRateStorageBlob {
        downloads += 1
        if downloads == 1 {
            throw WorkoutHeartRateSidecarError.transient
        }
        return blob
    }

    func deleteHeartRateSeriesIfPresent(userId: String, workoutId: UUID) async throws {}

    func downloadCount() -> Int {
        downloads
    }
}

private struct HeartRateDurabilityRemoteRepository: WorkoutRemoteRepositoryProtocol {
    let records: [RemoteWorkoutRecord]

    func fetchWorkouts(userId: String) async throws -> [RemoteWorkoutRecord] {
        records.filter { $0.document.userId == userId }
    }

    func upsertWorkout(
        userId: String,
        workoutId: UUID,
        document: FirestoreWorkoutDocument
    ) async throws {}

    func deleteWorkout(userId: String, workoutId: UUID) async throws {}
}
