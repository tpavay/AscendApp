import Foundation
import SwiftData
import Testing

@testable import AscendApp

/// The save path for a climb typed in by hand: what it stores, what it counts toward, and the
/// pace check at the two places it is allowed to run - save, and an edit to the steps or time.
@MainActor
struct LoggedClimbSaveTests {
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)
    private static let userId = "logged-climb-user"

    private func makeContext() throws -> ModelContext {
        let container = try RetainedModelContainer.inMemory(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            LeaderboardStats.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self
        )
        return ModelContext(container)
    }

    private func input(
        steps: Int,
        floors: Bool = false,
        seconds: Int,
        date: Date = LoggedClimbSaveTests.now
    ) -> LoggedClimbInput {
        var input = LoggedClimbInput(date: date)
        input.select(unit: floors ? .floors : .steps)
        String(steps).compactMap(\.wholeNumberValue).forEach { input.appendAmountDigit($0) }
        LogClimbViewModel.consoleDigits(for: TimeInterval(seconds)).forEach { input.timeEntry.append($0) }
        return input
    }

    // MARK: - What a saved climb is

    @Test
    func aLoggedClimbIsStoredAsAHandLoggedClimbThatCounts() throws {
        let context = try makeContext()
        let workout = try #require(
            LoggedClimbService.makeWorkout(
                input: input(steps: 3_200, seconds: 2_400),
                details: LoggedClimbDetails(effortRating: 4, averageHeartRate: 142, note: "  Leg day  "),
                now: Self.now
            )
        )

        try LoggedClimbService.save(workout, modelContext: context)

        let stored = try context.fetch(FetchDescriptor<Workout>())
        #expect(stored.count == 1)
        let climb = try #require(stored.first)
        #expect(climb.source == .manual)
        #expect(climb.origin == .manual)
        #expect(climb.name == "Stair Stepper")
        #expect(climb.steps == 3_200)
        #expect(climb.floors == 200)
        #expect(climb.stepsPerFloor == FloorsClimbed.stepsPerFloor)
        #expect(climb.duration == 2_400)
        #expect(climb.date == Self.now)
        #expect(climb.effortRating == 4)
        #expect(climb.avgHeartRate == 142)
        #expect(climb.notes == "Leg day")
        #expect(climb.leaderboardStatus == .eligible)
        #expect(!climb.isMissingSteps)
        #expect(climb.recordedSteps == 3_200)
        #expect(!climb.isLiveClimbAttemptWorkout, "a logged climb stays editable and deletable")
    }

    @Test
    func aClimbLoggedInFloorsStoresTheStepsTheyConvertTo() throws {
        let workout = try #require(
            LoggedClimbService.makeWorkout(
                input: input(steps: 200, floors: true, seconds: 2_400),
                details: LoggedClimbDetails(),
                now: Self.now
            )
        )

        #expect(workout.floors == 200)
        #expect(workout.steps == 200 * FloorsClimbed.stepsPerFloor)
        #expect(workout.steps == Workout.floorsToSteps(200))
        #expect(workout.stepsPerFloor == Workout.defaultStepsPerFloor)
    }

    @Test
    func aClimbPastTheCeilingSavesButStaysOffTheBoards() throws {
        let context = try makeContext()
        // 7,500 steps in 30:00 is 250 a minute.
        let workout = try #require(
            LoggedClimbService.makeWorkout(
                input: input(steps: 7_500, seconds: 1_800),
                details: LoggedClimbDetails(),
                now: Self.now
            )
        )

        try LoggedClimbService.save(workout, modelContext: context)

        #expect(try context.fetchCount(FetchDescriptor<Workout>()) == 1)
        #expect(workout.leaderboardStatus == .excluded)
        #expect(workout.exceedsPaceCeiling)
    }

    @Test
    func anImpossibleClimbIsNeverBuilt() {
        #expect(
            LoggedClimbService.makeWorkout(
                input: input(steps: 49_120, seconds: 2_400),
                details: LoggedClimbDetails(),
                now: Self.now
            ) == nil
        )
        #expect(
            LoggedClimbService.makeWorkout(
                input: LoggedClimbInput(date: Self.now),
                details: LoggedClimbDetails(),
                now: Self.now
            ) == nil
        )
    }

    // MARK: - What it counts toward

    @Test
    func aClimbThatClearsTheCheckAddsToTheBoardOverlayAndOneThatDoesNotAddsNothing() throws {
        let context = try makeContext()
        let service = LeaderboardService()
        service.configure(modelContext: context)
        let reference = Self.now

        let clean = try #require(
            LoggedClimbService.makeWorkout(
                input: input(steps: 3_000, seconds: 1_800, date: reference),
                details: LoggedClimbDetails(),
                now: reference
            )
        )
        let overPace = try #require(
            LoggedClimbService.makeWorkout(
                input: input(steps: 7_500, seconds: 1_800, date: reference),
                details: LoggedClimbDetails(),
                now: reference
            )
        )

        let impact = LeaderboardMutationImpact.classify(
            .created([LeaderboardWorkoutSnapshot(workout: clean), LeaderboardWorkoutSnapshot(workout: overPace)])
        )
        try service.rebuildCurrentStats(for: Self.userId, workouts: [], referenceDate: reference)
        _ = try service.applyMutationImpact(impact, for: Self.userId, referenceDate: reference)

        let weekly = try #require(try service.getLocalStats(for: Self.userId, timeFrame: .weekly))
        #expect(weekly.totalSteps == 3_000, "only the climb the check cleared is on the overlay")
        #expect(weekly.totalWorkouts == 1)
    }

    @Test
    func editingTheStepsAcrossTheCeilingPutsAClimbOnAndOffTheBoards() throws {
        let context = try makeContext()
        let service = LeaderboardService()
        service.configure(modelContext: context)
        let reference = Self.now

        let workout = try #require(
            LoggedClimbService.makeWorkout(
                input: input(steps: 6_000, seconds: 1_800, date: reference),
                details: LoggedClimbDetails(),
                now: reference
            )
        )
        try service.rebuildCurrentStats(for: Self.userId, workouts: [], referenceDate: reference)
        _ = try service.applyMutationImpact(
            LeaderboardMutationImpact.classify(.created([LeaderboardWorkoutSnapshot(workout: workout)])),
            for: Self.userId,
            referenceDate: reference
        )
        var weekly = try #require(try service.getLocalStats(for: Self.userId, timeFrame: .weekly))
        #expect(weekly.totalSteps == 6_000)

        // Edit up past the ceiling: the snapshot before and after differ in whether they count.
        let before = LeaderboardWorkoutSnapshot(workout: workout)
        workout.steps = 6_300
        workout.floors = Workout.stepsToFloors(6_300)
        #expect(workout.refreshLeaderboardStatus())
        let after = LeaderboardWorkoutSnapshot(workout: workout)
        _ = try service.applyMutationImpact(
            LeaderboardMutationImpact.classify(.updated(before: before, after: after)),
            for: Self.userId,
            referenceDate: reference
        )
        weekly = try #require(try service.getLocalStats(for: Self.userId, timeFrame: .weekly))
        #expect(weekly.totalSteps == 0, "over the ceiling, the climb leaves the board")
        #expect(weekly.totalWorkouts == 0)

        // And back under it.
        let beforeFix = LeaderboardWorkoutSnapshot(workout: workout)
        workout.steps = 5_400
        workout.floors = Workout.stepsToFloors(5_400)
        #expect(workout.refreshLeaderboardStatus())
        _ = try service.applyMutationImpact(
            LeaderboardMutationImpact.classify(
                .updated(before: beforeFix, after: LeaderboardWorkoutSnapshot(workout: workout))
            ),
            for: Self.userId,
            referenceDate: reference
        )
        weekly = try #require(try service.getLocalStats(for: Self.userId, timeFrame: .weekly))
        #expect(weekly.totalSteps == 5_400)
        #expect(weekly.totalWorkouts == 1)
    }

    // MARK: - The kill switch

    private func storeWithLoggingOff() -> RemoteFeatureFlagStore {
        RemoteFeatureFlagStore(
            snapshot: RemoteFeatureFlagSnapshot.resolving(
                remoteValues: [RemoteFeatureFlag.climbLogging.key: false]
            )
        )
    }

    @Test
    func withLoggingSwitchedOffLogItIsNotOfferedAndASaveStoresNothing() throws {
        let context = try makeContext()
        let off = storeWithLoggingOff()
        let workout = try #require(
            LoggedClimbService.makeWorkout(
                input: input(steps: 3_000, seconds: 1_800),
                details: LoggedClimbDetails(),
                now: Self.now
            )
        )

        #expect(LoggedClimbService.isOffered(featureFlags: off) == false)
        #expect(LoggedClimbService.isOffered(featureFlags: RemoteFeatureFlagStore()))
        #expect(throws: LoggedClimbService.LoggingPaused.self) {
            try LoggedClimbService.save(workout, modelContext: context, featureFlags: off)
        }
        #expect(try context.fetch(FetchDescriptor<Workout>()).isEmpty)

        try LoggedClimbService.save(workout, modelContext: context, featureFlags: RemoteFeatureFlagStore())
        #expect(try context.fetch(FetchDescriptor<Workout>()).count == 1)
    }

    @Test
    func withLoggingSwitchedOffAnEditLeavesTheStoredStatusAsItIs() throws {
        let workout = try #require(
            LoggedClimbService.makeWorkout(
                input: input(steps: 6_000, seconds: 1_800),
                details: LoggedClimbDetails(),
                now: Self.now
            )
        )
        #expect(workout.leaderboardStatus == .eligible)

        workout.steps = 6_300
        #expect(workout.refreshLeaderboardStatus(featureFlags: storeWithLoggingOff()) == false)
        #expect(workout.leaderboardStatus == .eligible)

        #expect(workout.refreshLeaderboardStatus(featureFlags: RemoteFeatureFlagStore()))
        #expect(workout.leaderboardStatus == .excluded)
    }

    @Test
    func aFullRebuildAgreesWithTheIncrementalOverlay() throws {
        let context = try makeContext()
        let service = LeaderboardService()
        service.configure(modelContext: context)
        let reference = Self.now

        let clean = try #require(
            LoggedClimbService.makeWorkout(
                input: input(steps: 3_000, seconds: 1_800, date: reference),
                details: LoggedClimbDetails(),
                now: reference
            )
        )
        let overPace = try #require(
            LoggedClimbService.makeWorkout(
                input: input(steps: 7_500, seconds: 1_800, date: reference),
                details: LoggedClimbDetails(),
                now: reference
            )
        )
        clean.ownerUserId = Self.userId
        overPace.ownerUserId = Self.userId

        try service.rebuildCurrentStats(for: Self.userId, workouts: [clean, overPace], referenceDate: reference)

        let weekly = try #require(try service.getLocalStats(for: Self.userId, timeFrame: .weekly))
        #expect(weekly.totalSteps == 3_000)
        #expect(weekly.totalWorkouts == 1)
    }

    @Test
    func aClimbAboveTheCeilingKeepsNoRecordsAndOneUnderItKeepsTheProratedOne() throws {
        let context = try makeContext()

        let under = Workout(
            name: "Stair Stepper",
            date: Self.now,
            duration: 2_400,
            steps: 4_000,
            floors: 250,
            source: .manual
        )
        under.ownerUserId = Self.userId
        let over = Workout(
            name: "Stair Stepper",
            date: Self.now.addingTimeInterval(-86_400),
            duration: 1_800,
            steps: 7_500,
            floors: 469,
            source: .manual
        )
        over.ownerUserId = Self.userId
        over.refreshLeaderboardStatus()
        context.insert(under)
        context.insert(over)
        try context.save()

        let mostSteps = BestEffortRankingBuilder.rankedEfforts(
            for: .mostSteps,
            from: [under, over],
            referenceDate: Self.now
        )
        #expect(
            mostSteps.map(\.workout.id) == [under.id],
            "a climb the pace check kept off the leaderboards holds no record"
        )

        // 4,000 steps in 40:00; a 1,000-step record is 1,000/4,000 of the time: 10:00.
        let thousand = BestEffortRankingBuilder.rankedEfforts(
            for: .fastestStepTarget(steps: 1_000),
            from: [under, over],
            referenceDate: Self.now
        )
        let record = try #require(thousand.first, "a typed climb with enough steps sets a prorated record")
        #expect(thousand.count == 1)
        #expect(record.workout.id == under.id)
        #expect(abs(record.performance.value - 600) < 0.001)
        #expect(record.origin == .manual, "the record carries how it was set")

        // A climb without 5,000 steps cannot claim a 5,000-step record, and the one with them is
        // off the boards.
        let five = BestEffortRankingBuilder.rankedEfforts(
            for: .fastestStepTarget(steps: 5_000),
            from: [under, over],
            referenceDate: Self.now
        )
        #expect(five.isEmpty)
    }

    // MARK: - Syncing

    @Test
    func everyClimbTheAppSavesIsOneTheCloudAccepts() throws {
        // 250 a minute: past the 220 live gate, under the 300 line, so it saves and has to sync.
        let saved = try #require(
            LoggedClimbService.makeWorkout(
                input: input(steps: 7_500, seconds: 1_800),
                details: LoggedClimbDetails(),
                now: Self.now
            )
        )
        saved.ownerUserId = Self.userId

        let snapshot = try WorkoutRemoteSyncMapper.snapshot(from: saved)
        #expect(snapshot.document.source == "manual")
        #expect(snapshot.document.steps == 7_500)

        // Past the line, the mapper refuses it the way the rules would.
        let absurd = Workout(
            name: "Stair Stepper",
            date: Self.now,
            duration: 1_800,
            steps: 9_000,
            floors: 563,
            source: .manual
        )
        absurd.ownerUserId = Self.userId
        #expect(throws: WorkoutSyncError.self) {
            _ = try WorkoutRemoteSyncMapper.snapshot(from: absurd)
        }
    }

    @Test
    func aLiveClimbKeepsTheSensorGateOnTheSyncPath() throws {
        let live = Workout(
            name: "Live Climb",
            date: Self.now,
            duration: 1_800,
            steps: 7_500,
            floors: 469,
            source: .headphoneMotion
        )
        live.ownerUserId = Self.userId

        #expect(throws: WorkoutSyncError.self) {
            _ = try WorkoutRemoteSyncMapper.snapshot(from: live)
        }
    }

    // MARK: - Missing steps

    @Test
    func aClimbWithNoStepsReadsAsMissingNotAsZero() {
        let imported = Workout(
            name: "Stair Stepper",
            duration: 2_472,
            steps: 0,
            floors: 0,
            source: .appleHealth
        )
        #expect(imported.isMissingSteps)
        #expect(imported.recordedSteps == nil)

        let live = Workout(name: "Live Climb", duration: 30, steps: 0, floors: 0, source: .headphoneMotion)
        #expect(!live.isMissingSteps, "a live climb's zero is a finished measurement")
        #expect(live.recordedSteps == 0)
    }
}
