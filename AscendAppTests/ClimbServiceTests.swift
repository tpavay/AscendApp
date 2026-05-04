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
    func singleSessionClimbFailsIfFirstEligibleWorkoutFallsShort() throws {
        let climb = makeClimb(id: "single-session-climb", multiSession: false, requiredSteps: 1_000)
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
        #expect(try service.activeAttempt(modelContext: modelContext) == nil)

        let historySummary = service.historySummary(for: climb, modelContext: modelContext)
        #expect(historySummary.completionsCount == 0)
        #expect(historySummary.failedAttemptsCount == 1)
        #expect(historySummary.attemptsCount == 1)
        #expect(historySummary.recentEntries.first?.status == .failed)
        #expect(workout.participations.first?.contextType == .climbAttempt)
        #expect(workout.participations.first?.leaderboardEligible == false)
    }

    @Test
    func multiSessionClimbRemainsActiveIfWorkoutFallsShort() throws {
        let climb = makeClimb(id: "multi-session-climb", multiSession: true, requiredSteps: 1_000)
        let service = ClimbService(catalogRepository: TestClimbCatalogRepository(climbs: [climb]))
        let modelContext = try makeModelContext()
        let climbStartedAt = Date(timeIntervalSince1970: 1_775_217_600)

        modelContext.insert(ClimbAttempt(climbId: climb.id, startedAt: climbStartedAt))
        try modelContext.save()

        let workout = Workout(
            name: "Short Workout",
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

        #expect(attempt.status == .active)
        #expect(attempt.accumulatedSteps == 800)
        #expect(attempt.sessionsCount == 1)
        #expect(try service.activeAttempt(modelContext: modelContext)?.climbId == climb.id)
        #expect(workout.participations.first?.contextType == .climbAttempt)
        #expect(workout.participations.first?.leaderboardEligible == false)
    }

    @Test
    func manualWorkoutDoesNotAdvanceActiveLiveClimb() throws {
        let climb = makeClimb(id: "headphone-only-climb", multiSession: true, requiredSteps: 1_000)
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

        let attempt = try #require(try service.activeAttempt(modelContext: modelContext))
        #expect(attempt.accumulatedSteps == 0)
        #expect(attempt.sessionsCount == 0)
        #expect(workout.participations.isEmpty)
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

    private func makeClimb(id: String, multiSession: Bool, requiredSteps: Int) -> Climb {
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
            multiSession: multiSession,
            funFact: "Fact",
            sourceURL: "https://example.com",
            imageSetVersion: 1,
            isPublished: true
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
