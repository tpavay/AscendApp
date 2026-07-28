import Foundation
import SwiftData
import Testing
@testable import AscendApp

@MainActor
struct WorkoutSyncCoordinatorTests {
    @Test
    func noHeartRateWorkoutSyncsDocumentOnly() async throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout(date: makeDate(year: 2026, month: 4, day: 13, hour: 9))
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: workout.createdAt)
        modelContext.insert(workout)
        try modelContext.save()

        let remoteRepository = FakeWorkoutRemoteRepository()
        let heartRateRepository = FakeWorkoutHeartRateStorageRepository()
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: heartRateRepository,
            operationTimeoutSeconds: 1
        )

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        let syncedWorkout = try #require(fetchWorkouts(in: modelContext).first)
        #expect(syncedWorkout.remoteSyncStatus == .synced)
        #expect(syncedWorkout.lastRemoteSyncAt != nil)

        let upserts = await remoteRepository.recordedUpserts()
        #expect(upserts.count == 1)
        #expect(upserts.first?.document.heartRateSeries == nil)
        #expect(await heartRateRepository.uploads().isEmpty)
    }

    @Test
    func heartRateWorkoutUploadsBlobBeforeDocument() async throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout(
            date: makeDate(year: 2026, month: 4, day: 13, hour: 9),
            heartRateSamples: [
                HeartRateDataPoint(timestamp: makeDate(year: 2026, month: 4, day: 13, hour: 9), heartRate: 110),
                HeartRateDataPoint(timestamp: makeDate(year: 2026, month: 4, day: 13, hour: 9, minute: 5), heartRate: 124)
            ]
        )
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: workout.createdAt)
        modelContext.insert(workout)
        try WorkoutParticipationService.addRoutineParticipationIfNeeded(
            for: workout,
            attribution: RoutineWorkoutAttribution(
                routineId: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                routineSource: .userCreated,
                templateId: nil,
                origin: .liveSession(stopReason: .targetReached)
            ),
            userId: "user-123",
            modelContext: modelContext
        )
        try modelContext.save()

        let recorder = CallRecorder()
        let remoteRepository = FakeWorkoutRemoteRepository(recorder: recorder)
        let heartRateRepository = FakeWorkoutHeartRateStorageRepository(recorder: recorder)
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: heartRateRepository,
            operationTimeoutSeconds: 1
        )

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        let events = await recorder.events()
        #expect(events == ["heart-rate-upload", "workout-upsert"])

        let upsert = try #require(await remoteRepository.recordedUpserts().first)
        let heartRateSeries = try #require(upsert.document.heartRateSeries)
        #expect(heartRateSeries.sampleCount == 2)
        #expect(
            heartRateSeries.storagePath ==
                "users/user-123/workout_heart_rate/\(workout.id.uuidString).json.gz"
        )
        let participation = try #require(upsert.document.participations?.first)
        #expect(participation.workoutId == workout.id.uuidString)
        #expect(participation.userId == "user-123")
        #expect(participation.contextType == WorkoutParticipationContextType.routine.rawValue)
        #expect(participation.contextId == "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        #expect(participation.contextVersion == 1)
        #expect(participation.rulesVersion == WorkoutParticipationService.currentRoutineRulesVersion)
        #expect(participation.role == WorkoutParticipationRole.primary.rawValue)
        #expect(participation.leaderboardEligible == false)
        #expect(participation.verificationTier == WorkoutParticipationVerificationTier.unverified.rawValue)
        #expect(participation.metricsSnapshot.steps == workout.steps)
        #expect(participation.createdAt <= Date())
    }

    @Test
    func syncFailureMarksWorkoutFailed() async throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout(date: makeDate(year: 2026, month: 4, day: 13, hour: 9))
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: workout.createdAt)
        modelContext.insert(workout)
        try modelContext.save()

        let remoteRepository = FakeWorkoutRemoteRepository(
            upsertError: TestSyncFailure()
        )
        let heartRateRepository = FakeWorkoutHeartRateStorageRepository()
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: heartRateRepository,
            operationTimeoutSeconds: 1
        )

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        let failedWorkout = try #require(fetchWorkouts(in: modelContext).first)
        #expect(failedWorkout.remoteSyncStatus == .failed)
        #expect(failedWorkout.lastRemoteSyncError?.isEmpty == false)
        #expect(failedWorkout.lastRemoteSyncAt == nil)
    }

    @Test
    func implausiblePendingWorkoutIsRejectedAndDoesNotBlockValidSync() async throws {
        let modelContext = try makeModelContext()
        let invalidWorkout = makeWorkout(
            date: makeDate(year: 2024, month: 8, day: 21, hour: 8),
            duration: 67.5363039970398,
            steps: 966
        )
        invalidWorkout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: invalidWorkout.createdAt)
        let validWorkout = makeWorkout(date: makeDate(year: 2026, month: 4, day: 13, hour: 9))
        validWorkout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: validWorkout.createdAt)
        modelContext.insert(invalidWorkout)
        modelContext.insert(validWorkout)
        try modelContext.save()

        let remoteRepository = FakeWorkoutRemoteRepository()
        let heartRateRepository = FakeWorkoutHeartRateStorageRepository()
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: heartRateRepository,
            operationTimeoutSeconds: 1
        )

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        let workouts = try fetchWorkouts(in: modelContext)
        let rejectedWorkout = try #require(workouts.first { $0.id == invalidWorkout.id })
        let syncedWorkout = try #require(workouts.first { $0.id == validWorkout.id })
        #expect(rejectedWorkout.remoteSyncStatus == .rejected)
        #expect(rejectedWorkout.lastRemoteSyncError?.isEmpty == false)
        #expect(syncedWorkout.remoteSyncStatus == .synced)

        let upserts = await remoteRepository.recordedUpserts()
        #expect(upserts.map(\.workoutId) == [validWorkout.id])
    }

    @Test
    func heartRateUploadFailureMarksWorkoutFailedWithoutUpsertingDocument() async throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout(
            date: makeDate(year: 2026, month: 4, day: 13, hour: 9),
            heartRateSamples: [
                HeartRateDataPoint(timestamp: makeDate(year: 2026, month: 4, day: 13, hour: 9), heartRate: 110)
            ]
        )
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: workout.createdAt)
        modelContext.insert(workout)
        try modelContext.save()

        let remoteRepository = FakeWorkoutRemoteRepository()
        let heartRateRepository = FakeWorkoutHeartRateStorageRepository(
            uploadError: TestSyncFailure()
        )
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: heartRateRepository,
            operationTimeoutSeconds: 1
        )

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        let failedWorkout = try #require(fetchWorkouts(in: modelContext).first)
        #expect(failedWorkout.remoteSyncStatus == .failed)
        #expect(failedWorkout.lastRemoteSyncAt == nil)
        #expect((await remoteRepository.recordedUpserts()).isEmpty)
    }

    @Test
    func failedWorkoutRetriesSuccessfullyOnNextPass() async throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout(date: makeDate(year: 2026, month: 4, day: 13, hour: 9))
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: workout.createdAt)
        modelContext.insert(workout)
        try modelContext.save()

        let remoteRepository = FlakyWorkoutRemoteRepository(failingUpsertAttempts: 1)
        let heartRateRepository = FakeWorkoutHeartRateStorageRepository()
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: heartRateRepository,
            operationTimeoutSeconds: 1
        )

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        let failedWorkout = try #require(fetchWorkouts(in: modelContext).first)
        #expect(failedWorkout.remoteSyncStatus == .failed)
        #expect(failedWorkout.lastRemoteSyncAt == nil)

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        let syncedWorkout = try #require(fetchWorkouts(in: modelContext).first)
        #expect(syncedWorkout.remoteSyncStatus == .synced)
        #expect(syncedWorkout.lastRemoteSyncAt != nil)
        #expect(await remoteRepository.successfulUpsertCount() == 1)
    }

    @Test
    func noHeartRateWorkoutDoesNotDeleteSidecarWhenNoneWasPreviouslySynced() async throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout(date: makeDate(year: 2026, month: 4, day: 13, hour: 9))
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: workout.createdAt)
        workout.markRemoteSyncSucceeded(
            syncedAt: workout.createdAt,
            heartRateSeries: nil
        )
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: workout.createdAt.addingTimeInterval(60))
        modelContext.insert(workout)
        try modelContext.save()

        let remoteRepository = FakeWorkoutRemoteRepository()
        let heartRateRepository = FakeWorkoutHeartRateStorageRepository()
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: heartRateRepository,
            operationTimeoutSeconds: 1
        )

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        #expect(await heartRateRepository.deletes().isEmpty)
    }

    @Test
    func noHeartRateWorkoutDeletesSidecarWhenOneWasPreviouslySynced() async throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout(date: makeDate(year: 2026, month: 4, day: 13, hour: 9))
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: workout.createdAt)
        workout.markRemoteSyncSucceeded(
            syncedAt: workout.createdAt,
            heartRateSeries: makeHeartRateSeriesReference(for: workout)
        )
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: workout.createdAt.addingTimeInterval(60))
        modelContext.insert(workout)
        try modelContext.save()

        let remoteRepository = FakeWorkoutRemoteRepository()
        let heartRateRepository = FakeWorkoutHeartRateStorageRepository()
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: heartRateRepository,
            operationTimeoutSeconds: 1
        )

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        let deletes = await heartRateRepository.deletes()
        #expect(deletes.count == 1)
        #expect(deletes.first?.workoutId == workout.id)
    }

    @Test
    func unrestoredSidecarSurvivesLocalEditAndStaysReferenced() async throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout(date: makeDate(year: 2026, month: 4, day: 13, hour: 9))
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: workout.createdAt)
        let reference = makeHeartRateSeriesReference(for: workout)
        workout.markRemoteSyncSucceeded(
            syncedAt: workout.createdAt,
            heartRateSeries: reference
        )
        workout.heartRateRestoreStatus = .unavailable
        workout.name = "Renamed after a failed restore"
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: workout.createdAt.addingTimeInterval(60))
        modelContext.insert(workout)
        try modelContext.save()

        let remoteRepository = FakeWorkoutRemoteRepository()
        let heartRateRepository = FakeWorkoutHeartRateStorageRepository()
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: heartRateRepository,
            operationTimeoutSeconds: 1
        )

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        #expect(await heartRateRepository.deletes().isEmpty)
        #expect(await heartRateRepository.uploads().isEmpty)
        let upsert = try #require(await remoteRepository.recordedUpserts().last)
        #expect(upsert.document.heartRateSeries == reference)
        let syncedWorkout = try #require(fetchWorkouts(in: modelContext).first)
        #expect(syncedWorkout.lastRemoteHeartRateSeriesReference == reference)
    }

    @Test
    func confirmedMissingSidecarReferenceIsDroppedInsteadOfCarriedForward() async throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout(date: makeDate(year: 2026, month: 4, day: 13, hour: 9))
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: workout.createdAt)
        workout.markRemoteSyncSucceeded(
            syncedAt: workout.createdAt,
            heartRateSeries: makeHeartRateSeriesReference(for: workout)
        )
        workout.heartRateRestoreStatus = .unavailable
        workout.heartRateRestoreErrorCode = WorkoutHeartRateSidecarError.missing.diagnosticCode
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: workout.createdAt.addingTimeInterval(60))
        modelContext.insert(workout)
        try modelContext.save()

        let remoteRepository = FakeWorkoutRemoteRepository()
        let heartRateRepository = FakeWorkoutHeartRateStorageRepository()
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: heartRateRepository,
            operationTimeoutSeconds: 1
        )

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        let upsert = try #require(await remoteRepository.recordedUpserts().last)
        #expect(upsert.document.heartRateSeries == nil)
        let syncedWorkout = try #require(fetchWorkouts(in: modelContext).first)
        #expect(syncedWorkout.lastRemoteHeartRateSeriesReference == nil)
        #expect(syncedWorkout.lastRemoteHeartRateSeriesStoragePath == nil)
    }

    @Test
    func implausibleHeartRateSampleIsDroppedWithoutBlockingItsWorkoutOrTheQueue() async throws {
        let modelContext = try makeModelContext()
        let start = makeDate(year: 2026, month: 4, day: 13, hour: 9)
        let validSamples = [
            HeartRateDataPoint(timestamp: start, heartRate: 121),
            HeartRateDataPoint(timestamp: start.addingTimeInterval(120), heartRate: 148)
        ]
        let glitchedWorkout = makeWorkout(
            date: start,
            heartRateSamples: [
                validSamples[0],
                HeartRateDataPoint(timestamp: start.addingTimeInterval(60), heartRate: 512),
                HeartRateDataPoint(timestamp: start.addingTimeInterval(90), heartRate: 0),
                validSamples[1]
            ]
        )
        glitchedWorkout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: glitchedWorkout.createdAt)
        modelContext.insert(glitchedWorkout)

        let healthyWorkout = makeWorkout(date: makeDate(year: 2026, month: 4, day: 14, hour: 9))
        healthyWorkout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: healthyWorkout.createdAt)
        modelContext.insert(healthyWorkout)
        try modelContext.save()

        let remoteRepository = FakeWorkoutRemoteRepository()
        let heartRateRepository = FakeWorkoutHeartRateStorageRepository()
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: heartRateRepository,
            operationTimeoutSeconds: 1
        )

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        #expect(await remoteRepository.recordedUpserts().count == 2)
        #expect(try fetchWorkouts(in: modelContext).allSatisfy { $0.remoteSyncStatus == .synced })

        let upload = try #require(await heartRateRepository.uploads().first)
        #expect(upload.blob.samples == validSamples)
        let glitchedUpsert = try #require(
            await remoteRepository.recordedUpserts().first { $0.workoutId == glitchedWorkout.id }
        )
        #expect(glitchedUpsert.document.heartRateSeries?.sampleCount == validSamples.count)
    }

    @Test
    func workoutWithOnlyImplausibleHeartRateSamplesSyncsWithoutASidecar() async throws {
        let modelContext = try makeModelContext()
        let start = makeDate(year: 2026, month: 4, day: 13, hour: 9)
        let workout = makeWorkout(
            date: start,
            heartRateSamples: [
                HeartRateDataPoint(timestamp: start, heartRate: 0),
                HeartRateDataPoint(timestamp: start.addingTimeInterval(60), heartRate: 401)
            ]
        )
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: workout.createdAt)
        modelContext.insert(workout)
        try modelContext.save()

        let remoteRepository = FakeWorkoutRemoteRepository()
        let heartRateRepository = FakeWorkoutHeartRateStorageRepository()
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: heartRateRepository,
            operationTimeoutSeconds: 1
        )

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        #expect(await heartRateRepository.uploads().isEmpty)
        let upsert = try #require(await remoteRepository.recordedUpserts().last)
        #expect(upsert.document.heartRateSeries == nil)
        let syncedWorkout = try #require(fetchWorkouts(in: modelContext).first)
        #expect(syncedWorkout.remoteSyncStatus == .synced)
    }

    private func makeHeartRateSeriesReference(
        for workout: Workout
    ) -> FirestoreWorkoutHeartRateSeriesReference {
        FirestoreWorkoutHeartRateSeriesReference(
            storagePath: WorkoutHeartRateStoragePath.path(
                userId: "user-123",
                workoutId: workout.id
            ),
            sampleCount: 3,
            seriesStartAt: workout.date,
            seriesEndAt: workout.date.addingTimeInterval(120),
            objectSchemaVersion: WorkoutHeartRateStorageBlob.currentSchemaVersion,
            compressedByteCount: 256,
            sha256: String(repeating: "a", count: 64)
        )
    }

    @Test
    func newerLocalMutationStaysPendingAfterSuccessfulUpload() async throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout(date: makeDate(year: 2026, month: 4, day: 13, hour: 9))
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: workout.createdAt)
        modelContext.insert(workout)
        try modelContext.save()

        let updatedAt = workout.createdAt.addingTimeInterval(3_600)
        let remoteRepository = FakeWorkoutRemoteRepository(
            onUpsert: {
                workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: updatedAt)
                try? modelContext.save()
            }
        )
        let heartRateRepository = FakeWorkoutHeartRateStorageRepository()
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: heartRateRepository,
            operationTimeoutSeconds: 1
        )

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        let pendingWorkout = try #require(fetchWorkouts(in: modelContext).first)
        #expect(pendingWorkout.remoteSyncStatus == .pendingUpsert)
        #expect(pendingWorkout.lastRemoteSyncAt == nil)
        #expect(pendingWorkout.lastModifiedAt == updatedAt)
    }

    @Test
    func concurrentProcessRequestsCoalesceIntoSingleSyncPass() async throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout(date: makeDate(year: 2026, month: 4, day: 13, hour: 9))
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: workout.createdAt)
        modelContext.insert(workout)
        try modelContext.save()

        let coordinatorReference = CoordinatorReference()
        let remoteRepository = FakeWorkoutRemoteRepository(
            onUpsert: {
                await coordinatorReference.value?.processPendingWorkouts(
                    modelContext: modelContext,
                    currentUserId: "user-123"
                )
            }
        )
        let heartRateRepository = FakeWorkoutHeartRateStorageRepository()
        // onUpsert re-enters the coordinator, so the sync only finishes once it
        // can hop back to the main actor - which CI saturates for tens of seconds
        // by running this @MainActor suite alongside every other one. A timeout
        // short enough to lose that race fails the first pass, and the coalesced
        // pass then correctly retries it, producing a second upsert that reads as
        // a coalescing bug. Coalescing is what's under test, so pin a timeout the
        // run can never reach instead of one that is merely usually long enough.
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: heartRateRepository,
            operationTimeoutSeconds: 3600
        )
        coordinatorReference.value = coordinator

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        let upserts = await remoteRepository.recordedUpserts()
        #expect(upserts.count == 1)
    }

    @Test
    func pendingDeletionDeletesRemoteResourcesAndRemovesQueueRecord() async throws {
        let modelContext = try makeModelContext()
        let pendingDeletion = PendingWorkoutDeletion(
            workoutId: UUID(),
            ownerUserId: "user-123"
        )
        modelContext.insert(pendingDeletion)
        try modelContext.save()

        let recorder = CallRecorder()
        let remoteRepository = FakeWorkoutRemoteRepository(recorder: recorder)
        let heartRateRepository = FakeWorkoutHeartRateStorageRepository(recorder: recorder)
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: heartRateRepository,
            operationTimeoutSeconds: 1
        )

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        #expect(try fetchPendingDeletions(in: modelContext).isEmpty)

        let events = await recorder.events()
        #expect(events == ["heart-rate-delete", "workout-delete"])

        let deletes = await remoteRepository.recordedDeletes()
        #expect(deletes.count == 1)
        #expect(deletes.first?.workoutId == pendingDeletion.workoutId)
        #expect((await heartRateRepository.deletes()).count == 1)
    }

    @Test
    func pendingDeletionFailureRetriesAndKeepsQueueRecord() async throws {
        let modelContext = try makeModelContext()
        let pendingDeletion = PendingWorkoutDeletion(
            workoutId: UUID(),
            ownerUserId: "user-123"
        )
        modelContext.insert(pendingDeletion)
        try modelContext.save()

        let remoteRepository = FakeWorkoutRemoteRepository(
            deleteError: TestSyncFailure()
        )
        let heartRateRepository = FakeWorkoutHeartRateStorageRepository()
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: heartRateRepository,
            operationTimeoutSeconds: 1
        )

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        let persistedDeletion = try #require(fetchPendingDeletions(in: modelContext).first)
        #expect(persistedDeletion.retryCount == 1)
        #expect(persistedDeletion.lastError?.isEmpty == false)
    }

    @Test
    func pendingDeletionHeartRateDeleteFailureKeepsQueueRecordAndSkipsRemoteDelete() async throws {
        let modelContext = try makeModelContext()
        let pendingDeletion = PendingWorkoutDeletion(
            workoutId: UUID(),
            ownerUserId: "user-123"
        )
        modelContext.insert(pendingDeletion)
        try modelContext.save()

        let remoteRepository = FakeWorkoutRemoteRepository()
        let heartRateRepository = FakeWorkoutHeartRateStorageRepository(
            deleteError: TestSyncFailure()
        )
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: heartRateRepository,
            operationTimeoutSeconds: 1
        )

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        let persistedDeletion = try #require(fetchPendingDeletions(in: modelContext).first)
        #expect(persistedDeletion.retryCount == 1)
        #expect(persistedDeletion.lastError?.isEmpty == false)
        #expect((await remoteRepository.recordedDeletes()).isEmpty)
    }

    @Test
    func pendingDeletionPreventsWorkoutFromBeingReuploaded() async throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout(date: makeDate(year: 2026, month: 4, day: 13, hour: 9))
        workout.markPendingRemoteUpsert(ownerUserId: "user-123", modifiedAt: workout.createdAt)
        modelContext.insert(workout)
        modelContext.insert(
            PendingWorkoutDeletion(
                workoutId: workout.id,
                ownerUserId: "user-123"
            )
        )
        try modelContext.save()

        let remoteRepository = FakeWorkoutRemoteRepository()
        let heartRateRepository = FakeWorkoutHeartRateStorageRepository()
        let coordinator = WorkoutSyncCoordinator(
            remoteRepository: remoteRepository,
            heartRateStorageRepository: heartRateRepository,
            operationTimeoutSeconds: 1
        )

        await coordinator.processPendingWorkouts(
            modelContext: modelContext,
            currentUserId: "user-123"
        )

        #expect((await remoteRepository.recordedUpserts()).isEmpty)
        #expect((await remoteRepository.recordedDeletes()).count == 1)
    }

    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            PendingWorkoutDeletion.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func fetchWorkouts(in modelContext: ModelContext) throws -> [Workout] {
        try modelContext.fetch(FetchDescriptor<Workout>())
    }

    private func fetchPendingDeletions(
        in modelContext: ModelContext
    ) throws -> [PendingWorkoutDeletion] {
        try modelContext.fetch(FetchDescriptor<PendingWorkoutDeletion>())
    }

    private func makeWorkout(
        date: Date,
        duration: TimeInterval = 1_800,
        steps: Int = 1_000,
        heartRateSamples: [HeartRateDataPoint] = []
    ) -> Workout {
        Workout(
            name: "Workout",
            date: date,
            duration: duration,
            steps: steps,
            floors: Workout.stepsToFloors(steps, stepsPerFloor: 16),
            stepsPerFloor: 16,
            notes: "Test",
            heartRateTimeSeries: heartRateSamples.isEmpty ? nil : heartRateSamples,
            source: .manual
        )
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}

private actor CallRecorder {
    private var recordedEvents: [String] = []

    func record(_ value: String) {
        recordedEvents.append(value)
    }

    func events() -> [String] {
        recordedEvents
    }
}

private actor FakeWorkoutRemoteRepository: WorkoutRemoteRepositoryProtocol {
    struct Upsert: Equatable {
        let userId: String
        let workoutId: UUID
        let document: FirestoreWorkoutDocument
    }

    struct Delete: Equatable {
        let userId: String
        let workoutId: UUID
    }

    private var upserts: [Upsert] = []
    private var deletes: [Delete] = []
    private let recorder: CallRecorder?
    private let upsertError: (any Error & Sendable)?
    private let deleteError: (any Error & Sendable)?
    private let onUpsert: (@MainActor () async -> Void)?

    init(
        recorder: CallRecorder? = nil,
        upsertError: (any Error & Sendable)? = nil,
        deleteError: (any Error & Sendable)? = nil,
        onUpsert: (@MainActor () async -> Void)? = nil
    ) {
        self.recorder = recorder
        self.upsertError = upsertError
        self.deleteError = deleteError
        self.onUpsert = onUpsert
    }

    func fetchWorkouts(userId: String) async throws -> [RemoteWorkoutRecord] {
        []
    }

    func upsertWorkout(
        userId: String,
        workoutId: UUID,
        document: FirestoreWorkoutDocument
    ) async throws {
        await recorder?.record("workout-upsert")
        if let upsertError {
            throw upsertError
        }

        upserts.append(Upsert(userId: userId, workoutId: workoutId, document: document))
        await onUpsert?()
    }

    func deleteWorkout(userId: String, workoutId: UUID) async throws {
        await recorder?.record("workout-delete")
        if let deleteError {
            throw deleteError
        }

        deletes.append(Delete(userId: userId, workoutId: workoutId))
    }

    func recordedUpserts() -> [Upsert] {
        upserts
    }

    func recordedDeletes() -> [Delete] {
        deletes
    }
}

private actor FakeWorkoutHeartRateStorageRepository: WorkoutHeartRateStorageRepositoryProtocol {
    struct Upload: Equatable {
        let userId: String
        let workoutId: UUID
        let blob: WorkoutHeartRateStorageBlob
    }

    struct Delete: Equatable {
        let userId: String
        let workoutId: UUID
    }

    private var recordedUploads: [Upload] = []
    private var recordedDeletes: [Delete] = []
    private let recorder: CallRecorder?
    private let uploadError: (any Error & Sendable)?
    private let deleteError: (any Error & Sendable)?

    init(
        recorder: CallRecorder? = nil,
        uploadError: (any Error & Sendable)? = nil,
        deleteError: (any Error & Sendable)? = nil
    ) {
        self.recorder = recorder
        self.uploadError = uploadError
        self.deleteError = deleteError
    }

    func uploadHeartRateSeries(
        userId: String,
        workoutId: UUID,
        blob: WorkoutHeartRateStorageBlob
    ) async throws -> FirestoreWorkoutHeartRateSeriesReference {
        await recorder?.record("heart-rate-upload")
        if let uploadError {
            throw uploadError
        }

        recordedUploads.append(Upload(userId: userId, workoutId: workoutId, blob: blob))
        return FirestoreWorkoutHeartRateSeriesReference(
            storagePath: "users/\(userId)/workout_heart_rate/\(workoutId.uuidString).json.gz",
            sampleCount: blob.samples.count,
            seriesStartAt: blob.samples.first?.timestamp ?? .distantPast,
            seriesEndAt: blob.samples.last?.timestamp ?? .distantPast
        )
    }

    func deleteHeartRateSeriesIfPresent(
        userId: String,
        workoutId: UUID
    ) async throws {
        await recorder?.record("heart-rate-delete")
        if let deleteError {
            throw deleteError
        }
        recordedDeletes.append(Delete(userId: userId, workoutId: workoutId))
    }

    func downloadHeartRateSeries(
        userId: String,
        workoutId: UUID,
        reference: FirestoreWorkoutHeartRateSeriesReference
    ) async throws -> WorkoutHeartRateStorageBlob {
        throw WorkoutHeartRateSidecarError.missing
    }

    func uploads() -> [Upload] {
        recordedUploads
    }

    func deletes() -> [Delete] {
        recordedDeletes
    }
}

private struct TestSyncFailure: Error, Sendable {}

private actor FlakyWorkoutRemoteRepository: WorkoutRemoteRepositoryProtocol {
    private var remainingFailingUpsertAttempts: Int
    private var upsertCount = 0

    init(failingUpsertAttempts: Int) {
        self.remainingFailingUpsertAttempts = failingUpsertAttempts
    }

    func fetchWorkouts(userId: String) async throws -> [RemoteWorkoutRecord] {
        []
    }

    func upsertWorkout(
        userId: String,
        workoutId: UUID,
        document: FirestoreWorkoutDocument
    ) async throws {
        if remainingFailingUpsertAttempts > 0 {
            remainingFailingUpsertAttempts -= 1
            throw TestSyncFailure()
        }

        upsertCount += 1
    }

    func deleteWorkout(userId: String, workoutId: UUID) async throws {}

    func successfulUpsertCount() -> Int {
        upsertCount
    }
}

@MainActor
private final class CoordinatorReference {
    var value: WorkoutSyncCoordinator?
}
