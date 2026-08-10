//
//  ClimbServiceTests.swift
//  AscendAppTests
//
//  Created by Codex on 4/3/26.
//

import Foundation
import SwiftData
import Testing
@testable import AscendApp

@MainActor
struct ClimbServiceTests {
    @Test
    func activeClimbEligibilityUsesWorkoutSessionDateNotInsertionDate() {
        let climbStartedAt = Date(timeIntervalSince1970: 1_775_217_600) // Apr 3 2026 00:00 UTC
        let performedBeforeClimb = climbStartedAt.addingTimeInterval(-3_600)
        let importedAfterClimb = climbStartedAt.addingTimeInterval(300)

        let workout = Workout(
            name: "Imported Workout",
            date: performedBeforeClimb,
            duration: 1_800,
            steps: 1_200,
            floors: 75,
            stepsPerFloor: 16,
            source: .appleHealth
        )
        workout.createdAt = importedAfterClimb

        #expect(ClimbService.isEligibleForActiveClimb(workout, startedAt: climbStartedAt) == false)
    }

    @Test
    func sessionEndDateUsesWorkoutDurationFromSessionStart() {
        let workoutStart = Date(timeIntervalSince1970: 1_775_217_600)
        let workout = Workout(
            name: "Workout",
            date: workoutStart,
            duration: 2_700,
            steps: 1_500,
            floors: 94,
            stepsPerFloor: 16,
            source: .manual
        )

        #expect(ClimbService.sessionEndDate(for: workout) == workoutStart.addingTimeInterval(2_700))
    }

    @Test
    func liveClimbFailsIfEligibleWorkoutFallsShort() throws {
        let climb = makeClimb(id: "live-climb", requiredSteps: 1_000)
        let service = ClimbService(catalogRepository: TestClimbCatalogRepository(climbs: [climb]))
        let modelContext = try makeModelContext()
        let climbStartedAt = Date(timeIntervalSince1970: 1_775_217_600)

        modelContext.insert(ClimbAttempt(climbId: climb.id, startedAt: climbStartedAt))
        try modelContext.save()

        let workout = Workout(
            name: "Too Short",
            date: climbStartedAt.addingTimeInterval(60),
            duration: 900,
            steps: 800,
            floors: 50,
            stepsPerFloor: 16,
            source: .headphoneMotion
        )
        modelContext.insert(workout)
        try modelContext.save()

        try service.apply(workouts: [workout], modelContext: modelContext)

        let attempts = try modelContext.fetch(FetchDescriptor<ClimbAttempt>())
        let attempt = try #require(attempts.first)

        #expect(attempt.status == .failed)
        #expect(attempt.accumulatedSteps == 800)
        #expect(attempt.sessionsCount == 1)
        #expect(attempt.completedAt == nil)
        #expect(attempt.endedAt == workout.date.addingTimeInterval(workout.duration))
        #expect(attempts.contains(where: { $0.status == .active }) == false)

        let historySummary = service.historySummary(for: climb, modelContext: modelContext)
        #expect(historySummary.completionsCount == 0)
        #expect(historySummary.failedAttemptsCount == 1)
        #expect(historySummary.attemptsCount == 1)
        #expect(historySummary.recentEntries.first?.status == .failed)
        #expect(workout.participations.first?.contextType == .climbAttempt)
        #expect(workout.participations.first?.leaderboardEligible == false)
    }

    @Test
    func liveClimbCompletionIsLeaderboardEligible() throws {
        let climb = makeClimb(id: "live-climb-complete", requiredSteps: 1_000)
        let service = ClimbService(catalogRepository: TestClimbCatalogRepository(climbs: [climb]))
        let modelContext = try makeModelContext()
        let climbStartedAt = Date(timeIntervalSince1970: 1_775_217_600)

        modelContext.insert(ClimbAttempt(climbId: climb.id, startedAt: climbStartedAt))
        try modelContext.save()

        let workout = Workout(
            name: "Complete Climb",
            date: climbStartedAt.addingTimeInterval(60),
            duration: 900,
            steps: 1_000,
            floors: 63,
            stepsPerFloor: 16,
            source: .headphoneMotion
        )
        modelContext.insert(workout)
        try modelContext.save()

        try service.apply(workouts: [workout], modelContext: modelContext)

        let attempt = try #require(try modelContext.fetch(FetchDescriptor<ClimbAttempt>()).first)
        #expect(attempt.status == .completed)
        #expect(attempt.sessionsCount == 1)
        #expect(workout.participations.first?.leaderboardEligible == true)
    }

    @Test
    func liveClimbCompletionWithInterruptedTrackingRemainsLeaderboardEligible() throws {
        let climb = makeClimb(id: "live-climb-interrupted-complete", requiredSteps: 1_000)
        let service = ClimbService(catalogRepository: TestClimbCatalogRepository(climbs: [climb]))
        let modelContext = try makeModelContext()
        let climbStartedAt = Date(timeIntervalSince1970: 1_775_217_600)

        modelContext.insert(ClimbAttempt(climbId: climb.id, startedAt: climbStartedAt))
        try modelContext.save()

        let trackingIntegrity = HeadphoneMotionTrackingIntegrity(
            currentUnavailableDuration: 0,
            totalUnavailableDuration: 18,
            longestUnavailableDuration: 18,
            interruptionCount: 1
        )
        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: 500,
            climbId: climb.id,
            targetStepCount: climb.referenceStepCount,
            stopReason: .targetReached,
            trackingIntegrity: trackingIntegrity
        )
        let workout = Workout(
            name: "Complete Interrupted Climb",
            date: climbStartedAt.addingTimeInterval(60),
            duration: 900,
            steps: 1_000,
            floors: 63,
            stepsPerFloor: 16,
            source: .headphoneMotion,
            sourceMetadata: metadata.jsonString
        )
        modelContext.insert(workout)
        try modelContext.save()

        try service.apply(workouts: [workout], modelContext: modelContext)

        let attempt = try #require(try modelContext.fetch(FetchDescriptor<ClimbAttempt>()).first)
        #expect(attempt.status == .completed)
        #expect(workout.participations.first?.leaderboardEligible == true)
    }

    @Test
    func endingManuallyPastTheTargetRecordsTheClimbAsTargetReached() throws {
        let climb = makeClimb(id: "manual-end-past-target", requiredSteps: 1_000)
        let service = ClimbService(catalogRepository: TestClimbCatalogRepository(climbs: [climb]))
        let modelContext = try makeModelContext()
        let climbStartedAt = Date(timeIntervalSince1970: 1_775_217_600)

        modelContext.insert(ClimbAttempt(climbId: climb.id, startedAt: climbStartedAt))
        try modelContext.save()

        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: 500,
            climbId: climb.id,
            targetStepCount: climb.referenceStepCount,
            climbTargetStepCount: climb.referenceStepCount,
            stopReason: .userStopped
        )
        let workout = Workout(
            name: "Ended On The Target",
            date: climbStartedAt.addingTimeInterval(60),
            duration: 900,
            steps: 1_010,
            floors: 63,
            stepsPerFloor: 16,
            source: .headphoneMotion,
            sourceMetadata: metadata.jsonString
        )
        modelContext.insert(workout)
        try modelContext.save()

        let attempt = try #require(try service.apply(workouts: [workout], modelContext: modelContext))

        #expect(attempt.status == .completed)
        #expect(LiveClimbWorkoutSummaryData.metadata(for: workout)?.stopReason == .targetReached)
    }

    @Test
    func endingManuallyShortOfTheTargetKeepsTheRecordedStopReason() throws {
        let climb = makeClimb(id: "manual-end-short-of-target", requiredSteps: 1_000)
        let service = ClimbService(catalogRepository: TestClimbCatalogRepository(climbs: [climb]))
        let modelContext = try makeModelContext()
        let climbStartedAt = Date(timeIntervalSince1970: 1_775_217_600)

        modelContext.insert(ClimbAttempt(climbId: climb.id, startedAt: climbStartedAt))
        try modelContext.save()

        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: 500,
            climbId: climb.id,
            targetStepCount: climb.referenceStepCount,
            climbTargetStepCount: climb.referenceStepCount,
            stopReason: .userStopped
        )
        let workout = Workout(
            name: "Gave Up Early",
            date: climbStartedAt.addingTimeInterval(60),
            duration: 900,
            steps: 800,
            floors: 50,
            stepsPerFloor: 16,
            source: .headphoneMotion,
            sourceMetadata: metadata.jsonString
        )
        modelContext.insert(workout)
        try modelContext.save()

        let attempt = try #require(try service.apply(workouts: [workout], modelContext: modelContext))

        #expect(attempt.status == .failed)
        #expect(LiveClimbWorkoutSummaryData.metadata(for: workout)?.stopReason == .userStopped)
    }

    @Test
    func laterWorkoutDoesNotAccumulateTowardPriorAttempt() throws {
        let climb = makeClimb(id: "restart-required-climb", requiredSteps: 1_000)
        let service = ClimbService(catalogRepository: TestClimbCatalogRepository(climbs: [climb]))
        let modelContext = try makeModelContext()
        let climbStartedAt = Date(timeIntervalSince1970: 1_775_217_600)

        let legacyActiveAttempt = ClimbAttempt(
            climbId: climb.id,
            startedAt: climbStartedAt,
            accumulatedSteps: 800,
            accumulatedDurationSeconds: 900,
            sessionsCount: 1,
            appliedWorkoutIds: ["legacy-workout"]
        )
        modelContext.insert(legacyActiveAttempt)
        try modelContext.save()

        let restartedAt = climbStartedAt.addingTimeInterval(1_800)
        let freshAttempt = try service.prepareLiveClimbAttempt(
            for: climb,
            startedAt: restartedAt,
            modelContext: modelContext
        )

        let workout = Workout(
            name: "Still Short",
            date: restartedAt.addingTimeInterval(60),
            duration: 300,
            steps: 200,
            floors: 13,
            stepsPerFloor: 16,
            source: .headphoneMotion
        )
        modelContext.insert(workout)
        try modelContext.save()

        try service.apply(workouts: [workout], modelContext: modelContext)

        let attempts = try modelContext.fetch(FetchDescriptor<ClimbAttempt>())
        let retiredAttempt = try #require(attempts.first { $0.id == legacyActiveAttempt.id })
        let savedAttempt = try #require(attempts.first { $0.id == freshAttempt.id })

        #expect(retiredAttempt.status == .failed)
        #expect(retiredAttempt.accumulatedSteps == 800)
        #expect(savedAttempt.status == .failed)
        #expect(savedAttempt.accumulatedSteps == 200)
        #expect(savedAttempt.sessionsCount == 1)
        #expect(workout.participations.first?.contextType == .climbAttempt)
        #expect(workout.participations.first?.leaderboardEligible == false)
    }

    @Test
    func partialWorkoutCannotCompleteWithAnotherWorkoutInSameAttempt() throws {
        let climb = makeClimb(id: "single-attempt-only", requiredSteps: 1_000)
        let service = ClimbService(catalogRepository: TestClimbCatalogRepository(climbs: [climb]))
        let modelContext = try makeModelContext()
        let climbStartedAt = Date(timeIntervalSince1970: 1_775_217_600)

        modelContext.insert(ClimbAttempt(climbId: climb.id, startedAt: climbStartedAt))
        try modelContext.save()

        let firstWorkout = Workout(
            name: "First Partial",
            date: climbStartedAt.addingTimeInterval(60),
            duration: 900,
            steps: 800,
            floors: 50,
            stepsPerFloor: 16,
            source: .headphoneMotion
        )
        let secondWorkout = Workout(
            name: "Final Partial",
            date: climbStartedAt.addingTimeInterval(1_200),
            duration: 300,
            steps: 200,
            floors: 13,
            stepsPerFloor: 16,
            source: .headphoneMotion
        )
        modelContext.insert(firstWorkout)
        modelContext.insert(secondWorkout)
        try modelContext.save()

        try service.apply(workouts: [firstWorkout], modelContext: modelContext)
        try service.apply(workouts: [secondWorkout], modelContext: modelContext)

        let attempt = try #require(try modelContext.fetch(FetchDescriptor<ClimbAttempt>()).first)
        #expect(attempt.status == .failed)
        #expect(attempt.accumulatedSteps == 800)
        #expect(attempt.sessionsCount == 1)
        #expect(firstWorkout.participations.first?.leaderboardEligible == false)
        #expect(secondWorkout.participations.isEmpty)
    }

    @Test
    func manualWorkoutDoesNotAdvanceActiveLiveClimb() throws {
        let climb = makeClimb(id: "headphone-only-climb", requiredSteps: 1_000)
        let service = ClimbService(catalogRepository: TestClimbCatalogRepository(climbs: [climb]))
        let modelContext = try makeModelContext()
        let climbStartedAt = Date(timeIntervalSince1970: 1_775_217_600)

        modelContext.insert(ClimbAttempt(climbId: climb.id, startedAt: climbStartedAt))

        let workout = Workout(
            name: "Manual Workout",
            date: climbStartedAt.addingTimeInterval(60),
            duration: 900,
            steps: 1_200,
            floors: 75,
            stepsPerFloor: 16,
            source: .manual
        )
        modelContext.insert(workout)
        try modelContext.save()

        try service.apply(workouts: [workout], modelContext: modelContext)

        let attempt = try #require(try modelContext.fetch(FetchDescriptor<ClimbAttempt>()).first)
        #expect(attempt.accumulatedSteps == 0)
        #expect(attempt.sessionsCount == 0)
        #expect(attempt.status == .active)
        #expect(workout.participations.isEmpty)
    }

    @Test
    func releaseStatesSeparateAvailableFromVisibleCatalogClimbs() throws {
        let available = makeClimb(id: "available-climb", requiredSteps: 1_000)
        let comingSoon = makeClimb(
            id: "coming-soon-climb",
            requiredSteps: 2_000,
            releaseState: .comingSoon
        )
        let hidden = makeClimb(
            id: "hidden-climb",
            requiredSteps: 3_000,
            releaseState: .hidden
        )
        let service = ClimbService(catalogRepository: TestClimbCatalogRepository(climbs: [available, comingSoon, hidden]))

        #expect(try service.loadClimbs().map(\.id) == [available.id])
        #expect(try service.loadVisibleClimbs().map(\.id) == [available.id, comingSoon.id])
        #expect(try service.climb(for: comingSoon.id)?.id == comingSoon.id)
    }

    @Test("A deleted climb costs its own completion, not the whole Home card", .bug(id: 440))
    func homeCardFallsBackToTheNewestResolvableCompletion() throws {
        let survivingClimb = makeClimb(id: "statue-of-liberty", requiredSteps: 377)
        let service = ClimbService(
            catalogRepository: TestClimbCatalogRepository(climbs: [survivingClimb])
        )
        let modelContext = try makeModelContext()
        let olderCompletion = Date(timeIntervalSince1970: 1_775_217_600)
        let newestCompletion = olderCompletion.addingTimeInterval(86_400)

        modelContext.insert(
            makeCompletedAttempt(climbId: survivingClimb.id, completedAt: olderCompletion)
        )
        modelContext.insert(
            makeCompletedAttempt(climbId: "machu-picchu", completedAt: newestCompletion)
        )
        try modelContext.save()

        let summary = try service.lastCompletedSummary(modelContext: modelContext)

        #expect(summary?.climb.id == survivingClimb.id)
        #expect(summary?.completedAt == olderCompletion)

        let homeCardState = try service.homeCardState(modelContext: modelContext)
        if case .neverClimbed = homeCardState {
            Issue.record("A resolvable completion must not reset Home to never-climbed")
        }
    }

    @Test("Home's collected fraction never outgrows its own total", .bug(id: 440))
    func homeCollectionFractionCountsRetiredClaimsOnBothSides() throws {
        let availableClimb = makeClimb(id: "statue-of-liberty", requiredSteps: 377)
        let retiredClimb = makeClimb(
            id: "mount-everest",
            requiredSteps: 48_664,
            releaseState: .hidden
        )
        let service = ClimbService(
            catalogRepository: TestClimbCatalogRepository(climbs: [availableClimb, retiredClimb])
        )
        let modelContext = try makeModelContext()
        let completedAt = Date(timeIntervalSince1970: 1_775_217_600)

        modelContext.insert(
            makeCompletedAttempt(climbId: availableClimb.id, completedAt: completedAt)
        )
        modelContext.insert(
            makeCompletedAttempt(
                climbId: retiredClimb.id,
                completedAt: completedAt.addingTimeInterval(-86_400)
            )
        )
        try modelContext.save()

        let summary = try #require(try service.lastCompletedSummary(modelContext: modelContext))

        #expect(summary.collectionCount == 2)
        #expect(summary.totalClimbs == 2)
        #expect(summary.collectionCount <= summary.totalClimbs)
        #expect(summary.collectionProgressText == "2 / 2")
    }

    @Test("A deleted climb leaves both sides of Home's fraction alone", .bug(id: 440))
    func homeCollectionFractionIgnoresUnresolvableClaims() throws {
        let availableClimb = makeClimb(id: "statue-of-liberty", requiredSteps: 377)
        let service = ClimbService(
            catalogRepository: TestClimbCatalogRepository(climbs: [availableClimb])
        )
        let modelContext = try makeModelContext()
        let completedAt = Date(timeIntervalSince1970: 1_775_217_600)

        modelContext.insert(
            makeCompletedAttempt(climbId: availableClimb.id, completedAt: completedAt)
        )
        modelContext.insert(
            makeCompletedAttempt(
                climbId: "machu-picchu",
                completedAt: completedAt.addingTimeInterval(-86_400)
            )
        )
        try modelContext.save()

        let summary = try #require(try service.lastCompletedSummary(modelContext: modelContext))

        #expect(summary.collectionCount == 1)
        #expect(summary.totalClimbs == 1)
    }

    @Test("Home and Profile state one collection fraction, not two", .bug(id: 440))
    func homeAndProfileAgreeOnTheCollectionFraction() throws {
        let availableClimb = makeClimb(id: "statue-of-liberty", requiredSteps: 377)
        let retiredClimb = makeClimb(
            id: "mount-everest",
            requiredSteps: 48_664,
            releaseState: .hidden
        )
        let catalogue = [availableClimb, retiredClimb]
        let service = ClimbService(
            catalogRepository: TestClimbCatalogRepository(climbs: catalogue)
        )
        let modelContext = try makeModelContext()
        let attempts = [
            makeCompletedAttempt(
                climbId: retiredClimb.id,
                completedAt: Date(timeIntervalSince1970: 1_775_217_600)
            )
        ]

        for attempt in attempts {
            modelContext.insert(attempt)
        }
        try modelContext.save()

        let homeSummary = try #require(try service.lastCompletedSummary(modelContext: modelContext))
        let profile = ProfileSnapshotBuilder.makeOwnSnapshot(
            demographics: ProfileDemographicsSnapshot(userId: "test-user"),
            workouts: [],
            climbAttempts: attempts,
            bestEffortCacheEntries: [],
            achievements: .zero,
            standings: [],
            climbs: catalogue,
            fitnessLevel: .beginner
        )

        #expect(homeSummary.collectionCount == profile.collection.collectedCount)
        #expect(homeSummary.totalClimbs == profile.collection.catalogCount)
    }

    @Test("A retired climb still fronts the Home card it was earned on", .bug(id: 440))
    func homeCardKeepsACompletionOnAHiddenClimb() throws {
        let retiredClimb = makeClimb(
            id: "mount-everest",
            requiredSteps: 48_664,
            releaseState: .hidden
        )
        let service = ClimbService(
            catalogRepository: TestClimbCatalogRepository(climbs: [retiredClimb])
        )
        let modelContext = try makeModelContext()
        let completedAt = Date(timeIntervalSince1970: 1_775_217_600)

        modelContext.insert(
            makeCompletedAttempt(climbId: retiredClimb.id, completedAt: completedAt)
        )
        try modelContext.save()

        #expect(try service.lastCompletedSummary(modelContext: modelContext)?.climb.id == retiredClimb.id)
    }

    private func makeCompletedAttempt(climbId: String, completedAt: Date) -> ClimbAttempt {
        ClimbAttempt(
            climbId: climbId,
            status: .completed,
            startedAt: completedAt.addingTimeInterval(-600),
            endedAt: completedAt,
            completedAt: completedAt,
            accumulatedSteps: 1_000,
            accumulatedDurationSeconds: 600,
            sessionsCount: 1
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

    private func makeClimb(
        id: String,
        requiredSteps: Int,
        releaseState: ClimbReleaseState = .available
    ) -> Climb {
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
            releaseState: releaseState
        )
    }
}

private struct TestClimbCatalogRepository: ClimbCatalogRepository {
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
