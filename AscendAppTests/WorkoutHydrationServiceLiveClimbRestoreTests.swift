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

    /// A recovered draft saves `.interrupted`, which save-time normalization deliberately leaves
    /// alone so it stays out of public results. Status still comes from steps, so the climb must
    /// survive a reinstall as a completion regardless of that reason.
    @Test
    func interruptedBackupPastTheTargetSurvivesReinstallAsCompleted() async throws {
        let userId = "reinstall-interrupted-user"
        let climb = makeClimb(id: "reinstall-interrupted-climb", requiredSteps: 1_000)

        let backup = try makeRemoteBackup(
            for: climb,
            userId: userId,
            steps: 1_010,
            stopReason: .interrupted
        )

        // The climb counted before the reinstall, and the reason was left untouched.
        #expect(backup.localAttemptStatus == .completed)
        #expect(try decodedMetadata(from: backup.record.document).stopReason == .interrupted)

        let restoredContext = try makeModelContext()
        _ = try await WorkoutHydrationService.hydrateIfNeeded(
            modelContext: restoredContext,
            currentUserId: userId,
            remoteRepository: StubWorkoutRemoteRepository(records: [backup.record])
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

    /// The bug in the terms the user feels it: the climb they finished has to still be theirs
    /// after a reinstall. The attempt record is what rehydration writes; these are the surfaces
    /// that record reaches - the Collection card's claimed state and the Climb Detail history.
    @Test
    func aFinishedClimbIsStillClaimedAcrossItsSurfacesAfterReinstall() async throws {
        let userId = "reinstall-surfaces-user"
        let climb = makeClimb(id: "reinstall-surfaces-climb", requiredSteps: 1_000)

        let backup = try makeRemoteBackup(
            for: climb,
            userId: userId,
            steps: 1_010,
            stopReason: .userStopped
        )
        let before = describeSurfaces(
            service: backup.service,
            climb: climb,
            modelContext: backup.sourceContext
        )

        let restoredContext = try makeModelContext()
        _ = try await WorkoutHydrationService.hydrateIfNeeded(
            modelContext: restoredContext,
            currentUserId: userId,
            remoteRepository: StubWorkoutRemoteRepository(records: [backup.record])
        )
        let restoredService = ClimbService(catalogRepository: TestCatalogRepository(climbs: [climb]))
        let after = describeSurfaces(
            service: restoredService,
            climb: climb,
            modelContext: restoredContext
        )

        // Compared as a whole so a regression reports every surface the user lost at once.
        #expect(after == before)

        // Collection: the card keeps its claimed checkmark.
        #expect(restoredService.previewSummary(for: climb, modelContext: restoredContext).isCompleted)
        #expect(restoredService.collectionCount(modelContext: restoredContext) == 1)

        // Climb Detail history: a completion, not a failed attempt.
        let history = restoredService.historySummary(for: climb, modelContext: restoredContext)
        #expect(history.completionsCount == 1)
        #expect(history.failedAttemptsCount == 0)
        let entry = try #require(history.recentEntries.first)
        #expect(entry.status == .completed)
        #expect(entry.recordedSteps == 1_000)
    }

    /// Renders the climb's user-facing state from the same service surfaces the Collection and
    /// Climb Detail screens read, so a reinstall's effect is legible without a device.
    private func describeSurfaces(
        service: ClimbService,
        climb: Climb,
        modelContext: ModelContext
    ) -> String {
        let isClaimed = service.previewSummary(for: climb, modelContext: modelContext).isCompleted
        let history = service.historySummary(for: climb, modelContext: modelContext)
        let entry = history.recentEntries.first

        return """
          Collection card ....... \(isClaimed ? "CLAIMED (checkmark badge)" : "UNCLAIMED (no badge)")
          Collection count ...... \(service.collectionCount(modelContext: modelContext)) climb(s)
          Climb Detail history .. \(history.completionsCount) completion(s), \
        \(history.failedAttemptsCount) failed attempt(s)
          History row ........... \(entry.map { "\($0.status) - \($0.recordedSteps.formatted()) of \($0.totalSteps.formatted()) steps" } ?? "none")
        """
    }

    private struct RemoteBackup {
        let record: RemoteWorkoutRecord
        let attemptId: UUID
        let localAttemptStatus: ClimbAttemptStatus
        let localAttemptSteps: Int
        let sourceContext: ModelContext
        let service: ClimbService
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
            localAttemptSteps: attempt.accumulatedSteps,
            sourceContext: modelContext,
            service: service
        )
    }

    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ClimbAttempt.self,
            Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            PendingWorkoutDeletion.self,
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
