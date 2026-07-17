//
//  WorkoutHydrationServiceLiveClimbRestoreTests.swift
//  AscendAppTests
//

import Foundation
import SwiftData
import Testing
@testable import AscendApp

/// Covers the reinstall path end to end: a climb is saved on one install, backed up through the
/// real remote mapper, and rehydrated into a fresh store the way a reinstall would see it.
@MainActor
struct WorkoutHydrationServiceLiveClimbRestoreTests {
    @Test
    func manuallyEndedClimbPastTheTargetSurvivesReinstallAsCompleted() async throws {
        let userId = "reinstall-manual-end-user"
        let climb = makeClimb(id: "reinstall-manual-end-climb", requiredSteps: 1_000)

        let backup = try makeRemoteBackup(
            for: climb,
            userId: userId,
            steps: 1_010,
            stopReason: .userStopped
        )

        // The climb counted before the reinstall.
        #expect(backup.localAttemptStatus == .completed)

        let restoredContext = try makeModelContext()
        let changedCount = try await WorkoutHydrationService.hydrateIfNeeded(
            modelContext: restoredContext,
            currentUserId: userId,
            remoteRepository: StubWorkoutRemoteRepository(records: [backup.record])
        )

        #expect(changedCount == 1)

        let restoredAttempt = try #require(
            try restoredContext.fetch(FetchDescriptor<ClimbAttempt>()).first
        )
        #expect(restoredAttempt.id == backup.attemptId)
        #expect(restoredAttempt.status == .completed)
        #expect(restoredAttempt.completedAt != nil)
        // A climb stops counting at its target, so rehydrating must not restate the steps.
        #expect(restoredAttempt.accumulatedSteps == 1_000)
        #expect(restoredAttempt.accumulatedSteps == backup.localAttemptSteps)
    }

    /// A backup written by a build that predates save-time stop reason normalization: the stored
    /// reason still says the user stopped even though the session passed the target.
    @Test
    func legacyBackupWithAStaleStopReasonRestoresAsCompleted() async throws {
        let userId = "reinstall-legacy-reason-user"
        let climb = makeClimb(id: "reinstall-legacy-reason-climb", requiredSteps: 1_000)

        let backup = try makeRemoteBackup(
            for: climb,
            userId: userId,
            steps: 1_010,
            stopReason: .userStopped
        )
        let legacyDocument = try rewritingStopReason(on: backup.record.document, to: .userStopped)

        #expect(try decodedMetadata(from: legacyDocument).stopReason == .userStopped)

        let restoredContext = try makeModelContext()
        _ = try await WorkoutHydrationService.hydrateIfNeeded(
            modelContext: restoredContext,
            currentUserId: userId,
            remoteRepository: StubWorkoutRemoteRepository(
                records: [
                    RemoteWorkoutRecord(
                        workoutId: backup.record.workoutId,
                        document: legacyDocument
                    )
                ]
            )
        )

        let restoredAttempt = try #require(
            try restoredContext.fetch(FetchDescriptor<ClimbAttempt>()).first
        )
        #expect(restoredAttempt.status == .completed)
        #expect(restoredAttempt.completedAt != nil)
        #expect(restoredAttempt.accumulatedSteps == 1_000)
    }

    @Test
    func attemptShortOfTheTargetStillRestoresAsFailed() async throws {
        let userId = "reinstall-short-attempt-user"
        let climb = makeClimb(id: "reinstall-short-attempt-climb", requiredSteps: 1_000)

        let backup = try makeRemoteBackup(
            for: climb,
            userId: userId,
            steps: 800,
            stopReason: .userStopped
        )

        #expect(backup.localAttemptStatus == .failed)

        let restoredContext = try makeModelContext()
        _ = try await WorkoutHydrationService.hydrateIfNeeded(
            modelContext: restoredContext,
            currentUserId: userId,
            remoteRepository: StubWorkoutRemoteRepository(records: [backup.record])
        )

        let restoredAttempt = try #require(
            try restoredContext.fetch(FetchDescriptor<ClimbAttempt>()).first
        )
        #expect(restoredAttempt.status == .failed)
        #expect(restoredAttempt.completedAt == nil)
    }

    private struct RemoteBackup {
        let record: RemoteWorkoutRecord
        let attemptId: UUID
        let localAttemptStatus: ClimbAttemptStatus
        let localAttemptSteps: Int
    }

    /// Rewrites the stored stop reason on an already-serialized backup, so a fixture can carry a
    /// reason that save-time normalization would never leave behind.
    private func rewritingStopReason(
        on document: FirestoreWorkoutDocument,
        to stopReason: HeadphoneMotionSessionStopReason
    ) throws -> FirestoreWorkoutDocument {
        var metadata = try decodedMetadata(from: document)
        metadata.stopReason = stopReason

        var json = try #require(
            try JSONSerialization.jsonObject(
                with: try JSONEncoder().encode(document)
            ) as? [String: Any]
        )
        json["sourceMetadata"] = try #require(metadata.jsonString)

        return try JSONDecoder().decode(
            FirestoreWorkoutDocument.self,
            from: try JSONSerialization.data(withJSONObject: json)
        )
    }

    private func decodedMetadata(
        from document: FirestoreWorkoutDocument
    ) throws -> HeadphoneMotionWorkoutMetadata {
        let json = try #require(document.sourceMetadata)
        return try JSONDecoder().decode(
            HeadphoneMotionWorkoutMetadata.self,
            from: try #require(json.data(using: .utf8))
        )
    }

    /// Saves a live climb the way the live session does, then serializes it through the real
    /// remote sync mapper so the restored document is the one a reinstall would download.
    private func makeRemoteBackup(
        for climb: Climb,
        userId: String,
        steps: Int,
        stopReason: HeadphoneMotionSessionStopReason
    ) throws -> RemoteBackup {
        let service = ClimbService(catalogRepository: TestCatalogRepository(climbs: [climb]))
        let modelContext = try makeModelContext()
        let climbStartedAt = Date(timeIntervalSince1970: 1_775_217_600)

        let attempt = try service.prepareLiveClimbAttempt(
            for: climb,
            startedAt: climbStartedAt,
            modelContext: modelContext
        )

        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: 500,
            climbId: climb.id,
            targetStepCount: climb.referenceStepCount,
            climbTargetStepCount: climb.referenceStepCount,
            stopReason: stopReason
        )
        let workout = Workout(
            name: "\(climb.name) Live Climb",
            date: climbStartedAt.addingTimeInterval(60),
            duration: 900,
            steps: steps,
            floors: Workout.stepsToFloors(steps),
            stepsPerFloor: Workout.defaultStepsPerFloor,
            source: .headphoneMotion,
            sourceMetadata: metadata.jsonString
        )
        modelContext.insert(workout)
        try modelContext.save()

        try service.apply(workouts: [workout], modelContext: modelContext)
        workout.markPendingRemoteUpsert(ownerUserId: userId)
        try modelContext.save()

        let snapshot = try WorkoutRemoteSyncMapper.snapshot(from: workout)

        return RemoteBackup(
            record: RemoteWorkoutRecord(workoutId: snapshot.workoutId, document: snapshot.document),
            attemptId: attempt.id,
            localAttemptStatus: attempt.status,
            localAttemptSteps: attempt.accumulatedSteps
        )
    }

    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ClimbAttempt.self,
            Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeClimb(id: String, requiredSteps: Int) -> Climb {
        Climb(
            id: id,
            name: id,
            city: "City",
            country: "Country",
            continent: "Continent",
            latitude: 0,
            longitude: 0,
            totalHeightMeters: 100,
            totalHeightFeet: 328,
            realClimbableHeightMeters: nil,
            realClimbableHeightFeet: nil,
            totalSteps: requiredSteps,
            realStairCount: nil,
            calculatedFloors: 50,
            category: "tower",
            tier: .gold,
            tags: [],
            funFact: "Fact",
            sourceURL: "https://example.com",
            imageSetVersion: 1,
            releaseState: .available
        )
    }
}

private struct StubWorkoutRemoteRepository: WorkoutRemoteRepositoryProtocol {
    let records: [RemoteWorkoutRecord]

    func fetchWorkouts(userId: String) async throws -> [RemoteWorkoutRecord] {
        records
    }

    func upsertWorkout(
        userId: String,
        workoutId: UUID,
        document: FirestoreWorkoutDocument
    ) async throws {}

    func deleteWorkout(userId: String, workoutId: UUID) async throws {}
}

private struct TestCatalogRepository: ClimbCatalogRepository {
    let climbs: [Climb]

    func loadInitialCatalog() throws -> ClimbCatalogSnapshot {
        ClimbCatalogSnapshot(
            climbs: climbs,
            source: .bootstrap,
            catalogVersion: 0,
            featuredClimbId: climbs.first?.id,
            updatedAt: nil
        )
    }

    func refreshCatalog() async throws -> ClimbCatalogSnapshot {
        try loadInitialCatalog()
    }
}
