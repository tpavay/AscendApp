import Foundation
import SwiftData
import Testing
@testable import AscendApp

@MainActor
struct WorkoutParticipationServiceTests {
    @Test
    func builtInRoutineAttributionUsesTemplateContext() throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout(source: .manual)
        modelContext.insert(workout)

        try WorkoutParticipationService.addRoutineParticipationIfNeeded(
            for: workout,
            attribution: RoutineWorkoutAttribution(
                routineId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                routineSource: .builtin,
                templateId: "pyramid_climb",
                origin: .liveSession(stopReason: .targetReached)
            ),
            userId: "user-123",
            modelContext: modelContext
        )

        try modelContext.save()

        let participation = try #require(workout.participations.first)
        #expect(participation.contextType == .routineTemplate)
        #expect(participation.contextId == "pyramid_climb")
        #expect(participation.leaderboardEligible)
        #expect(participation.verificationTier == .unverified)
        #expect(participation.metricsSnapshot?.steps == workout.steps)
    }

    @Test
    func userRoutineAttributionUsesLocalRoutineContextWithoutLeaderboardEligibility() throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout(source: .manual)
        let routineId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        modelContext.insert(workout)

        try WorkoutParticipationService.addRoutineParticipationIfNeeded(
            for: workout,
            attribution: RoutineWorkoutAttribution(
                routineId: routineId,
                routineSource: .userCreated,
                templateId: nil,
                origin: .liveSession(stopReason: .targetReached)
            ),
            userId: "user-123",
            modelContext: modelContext
        )

        try modelContext.save()

        let participation = try #require(workout.participations.first)
        #expect(participation.contextType == .routine)
        #expect(participation.contextId == routineId.uuidString)
        #expect(participation.leaderboardEligible == false)
    }

    @Test(arguments: [
        HeadphoneMotionSessionStopReason.skipped,
        .userStopped,
        .interrupted,
        .discarded
    ])
    func templateRoutineIsIneligibleForEveryStopReasonButTargetReached(
        stopReason: HeadphoneMotionSessionStopReason
    ) throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout(source: .headphoneMotion)
        modelContext.insert(workout)

        try WorkoutParticipationService.addRoutineParticipationIfNeeded(
            for: workout,
            attribution: RoutineWorkoutAttribution(
                routineId: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                routineSource: .builtin,
                templateId: "pyramid_climb",
                origin: .liveSession(stopReason: stopReason)
            ),
            userId: "user-123",
            modelContext: modelContext
        )

        try modelContext.save()

        let participation = try #require(workout.participations.first)
        #expect(participation.contextType == .routineTemplate)
        #expect(participation.contextId == "pyramid_climb")
        #expect(participation.leaderboardEligible == false)
    }

    /// Routine completions come only from the live routine flow, so a hand-typed template routine
    /// entry never earns competitive credit no matter how it is filled in.
    @Test
    func manuallyEnteredTemplateRoutineIsNotLeaderboardEligible() throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout(source: .manual)
        modelContext.insert(workout)

        try WorkoutParticipationService.addRoutineParticipationIfNeeded(
            for: workout,
            attribution: RoutineWorkoutAttribution(
                routineId: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                routineSource: .builtin,
                templateId: "pyramid_climb",
                origin: .manualEntry
            ),
            userId: "user-123",
            modelContext: modelContext
        )

        try modelContext.save()

        let participation = try #require(workout.participations.first)
        #expect(participation.contextType == .routineTemplate)
        #expect(participation.leaderboardEligible == false)
    }

    @Test(arguments: [
        HeadphoneMotionSessionStopReason.targetReached,
        .skipped,
        .userStopped,
        .interrupted
    ])
    func userCreatedRoutineIsNeverLeaderboardEligible(
        stopReason: HeadphoneMotionSessionStopReason
    ) {
        let attribution = RoutineWorkoutAttribution(
            routineId: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            routineSource: .userCreated,
            templateId: nil,
            origin: .liveSession(stopReason: stopReason)
        )

        #expect(attribution.isLeaderboardEligible == false)
    }

    @Test
    func remoteSyncSnapshotIncludesParticipationContext() throws {
        let modelContext = try makeModelContext()
        let workout = makeWorkout(source: .headphoneMotion)
        workout.markPendingRemoteUpsert(ownerUserId: "user-123")
        modelContext.insert(workout)

        let attempt = ClimbAttempt(climbId: "gateway-arch")
        modelContext.insert(attempt)

        try WorkoutParticipationService.addClimbAttemptParticipationIfNeeded(
            for: workout,
            attempt: attempt,
            userId: "user-123",
            leaderboardEligible: true,
            modelContext: modelContext
        )
        try modelContext.save()

        let snapshot = try WorkoutRemoteSyncMapper.snapshot(from: workout)
        let participation = try #require(snapshot.document.participations?.first)

        #expect(participation.userId == "user-123")
        #expect(participation.workoutId == workout.id.uuidString)
        #expect(participation.contextType == WorkoutParticipationContextType.climbAttempt.rawValue)
        #expect(participation.contextId == attempt.id.uuidString)
        #expect(participation.leaderboardEligible)
        #expect(participation.verificationTier == WorkoutParticipationVerificationTier.sensorVerified.rawValue)
    }

    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            ClimbAttempt.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeWorkout(source: WorkoutSource) -> Workout {
        Workout(
            name: "Workout",
            date: Date(timeIntervalSince1970: 1_775_217_600),
            duration: 1_800,
            steps: 1_200,
            floors: 75,
            stepsPerFloor: 16,
            source: source
        )
    }
}
