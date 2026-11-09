import Foundation
import HealthKit
import Testing
@testable import AscendApp

/// The one step rule Apple Health import runs on: a workout's own steps, else the steps Health
/// counted over the workout's window, else none. Checked on the rule itself and then end to end
/// through the pass, the fresh read at import time, and the history backfill, because a number a
/// screen promised is only true if every path lands the same one.
@MainActor
@Suite(.serialized)
struct HealthWorkoutStepRuleTests {
    private static let start = Date(timeIntervalSince1970: 1_780_000_000)

    private func workout(steps: Int?, minutes: Double = 30, offset: TimeInterval = 0) -> HealthWorkoutSnapshot {
        let start = Self.start.addingTimeInterval(offset)
        return HealthWorkoutSnapshot(
            uuid: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(minutes * 60),
            duration: minutes * 60,
            steps: steps
        )
    }

    // MARK: - The rule

    @Test
    func aWorkoutsOwnStepsWinAndTheWindowIsNeverRead() async {
        let reader = FakeHealthWorkoutReader()
        let workout = workout(steps: 3_000)
        reader.windowSteps[workout.startDate] = 9_999

        let resolved = await HealthWorkoutStepRule.resolve(workout, using: reader)

        #expect(resolved.steps == 3_000)
        #expect(reader.windowReads.isEmpty)
    }

    @Test(arguments: [nil, 0] as [Int?])
    func aWorkoutWithNoStepsOrZeroTakesTheStepsHealthCountedOverItsWindow(attached: Int?) async throws {
        let reader = FakeHealthWorkoutReader()
        let workout = workout(steps: attached)
        reader.windowSteps[workout.startDate] = 4_210

        let resolved = await HealthWorkoutStepRule.resolve(workout, using: reader)

        #expect(resolved.steps == 4_210)
        let read = try #require(reader.windowReads.first)
        #expect(reader.windowReads.count == 1, "one query per workout")
        #expect(read.start == workout.startDate, "from the workout's start")
        #expect(read.end == workout.endDate, "to its end")
        #expect(resolved.uuid == workout.uuid)
        #expect(resolved.duration == workout.duration)
    }

    @Test
    func anEmptyWindowLeavesTheStepsUnknown() async {
        let reader = FakeHealthWorkoutReader()
        let resolved = await HealthWorkoutStepRule.resolve(workout(steps: nil), using: reader)

        #expect(resolved.steps == nil, "unknown stays unknown, never zero")
        #expect(reader.windowReads.count == 1)
    }

    @Test
    func aWindowThatSumsToZeroLeavesTheStepsUnknown() async {
        let reader = FakeHealthWorkoutReader()
        let workout = workout(steps: 0)
        reader.windowSteps[workout.startDate] = 0

        let resolved = await HealthWorkoutStepRule.resolve(workout, using: reader)

        #expect(resolved.steps == nil)
    }

    @Test
    func aWindowReadThatFailsLeavesTheStepsUnknown() async {
        let reader = FakeHealthWorkoutReader()
        reader.windowReadError = CocoaError(.fileReadUnknown)

        let resolved = await HealthWorkoutStepRule.resolve(workout(steps: nil), using: reader)

        #expect(resolved.steps == nil)
    }

    @Test
    func aHistoryOfHundredsResolvesInOrderWithABoundedNumberOfReadsInFlight() async {
        let reader = FakeHealthWorkoutReader()
        let workouts = (0..<300).map { index in
            workout(steps: index.isMultiple(of: 3) ? 1_000 + index : nil, offset: TimeInterval(index) * 7_200)
        }
        for (index, workout) in workouts.enumerated() where workout.steps == nil {
            reader.windowSteps[workout.startDate] = 2_000 + index
        }

        let resolved = await HealthWorkoutStepRule.resolve(workouts, using: reader)
        let mostInFlight = reader.mostWindowReadsInFlight

        #expect(mostInFlight > 1, "the reads run together, not one at a time")
        #expect(mostInFlight <= HealthWorkoutStepRule.concurrentWindowReads, "and never more than the bound at once")
        #expect(reader.windowReads.count == 200, "only the workouts with no steps of their own are read")
        #expect(resolved.map(\.uuid) == workouts.map(\.uuid), "in the order they came")
        for (index, workout) in resolved.enumerated() {
            #expect(workout.steps == (index.isMultiple(of: 3) ? 1_000 + index : 2_000 + index))
        }
    }

    // MARK: - The pass

    @Test
    func aWorkoutWithNoStepsImportsWithTheStepsHealthCountedWhileItRan() async throws {
        let harness = try AppleHealthImportHarness()
        let workout = harness.addWorkout(daysAgo: 1, steps: nil, minutes: 30, windowSteps: 3_150)
        await harness.service.syncNow()

        let climb = try #require(try harness.climbs().first)
        #expect(climb.steps == 3_150, "the window's steps are the climb's steps")
        #expect(climb.recordedSteps == 3_150)
        #expect(!climb.isMissingSteps, "nothing asks the climber to add or check a number")
        #expect(climb.floors == Workout.stepsToFloors(3_150))
        #expect(climb.leaderboardStatus == .eligible, "105 a minute ranks like any other import")
        #expect(climb.canHoldRecords)
        #expect(climb.source == .appleHealth)
        #expect(try harness.record(workout)?.steps == 3_150)
    }

    @Test
    func aWindowCountIsIndistinguishableFromAnAttachedOne() async throws {
        let attached = try AppleHealthImportHarness()
        attached.addWorkout(daysAgo: 1, steps: 3_150, minutes: 30)
        let window = try AppleHealthImportHarness()
        window.addWorkout(daysAgo: 1, steps: nil, minutes: 30, windowSteps: 3_150)
        await attached.service.syncNow()
        await window.service.syncNow()

        let first = try #require(try attached.climbs().first)
        let second = try #require(try window.climbs().first)
        #expect(first.steps == second.steps)
        #expect(first.floors == second.floors)
        #expect(first.leaderboardStatus == second.leaderboardStatus)
        #expect(first.canHoldRecords == second.canHoldRecords)
        #expect(first.isMissingSteps == second.isMissingSteps)
        #expect(first.source == second.source)
        #expect(ImportsRowFormat.stepsText(first.recordedSteps) == ImportsRowFormat.stepsText(second.recordedSteps))
    }

    @Test
    func theAnnouncementNamesTheWindowsStepsLikeAnyOtherNumber() async throws {
        let harness = try AppleHealthImportHarness()
        await harness.service.syncNow()
        harness.addWorkout(daysAgo: 0.1, steps: nil, minutes: 30, windowSteps: 3_150)
        await harness.service.syncNow()

        #expect(harness.notifier.imported.map(\.steps) == [3_150])
        let content = AppleHealthImportPolicy.notificationContent(steps: 3_150)
        #expect(content.body == "Your 3,150-step stair stepper workout from Apple Health is in. Tap to add a note or photo.")
        #expect(!content.body.contains("~"))
        #expect(harness.service.homeNotice?.steps == 3_150)
    }

    @Test
    func theSamePaceCheckJudgesAWindowCount() async throws {
        let harness = try AppleHealthImportHarness()
        let ranks = harness.addWorkout(daysAgo: 1, steps: nil, minutes: 30, windowSteps: 6_600)        // 220 a minute
        let offBoards = harness.addWorkout(daysAgo: 2, steps: nil, minutes: 30, windowSteps: 7_500)    // 250 a minute
        let absurd = harness.addWorkout(daysAgo: 3, steps: nil, minutes: 30, windowSteps: 12_000)      // 400 a minute
        await harness.service.syncNow()

        let byUUID = Dictionary(uniqueKeysWithValues: try harness.climbs().compactMap { climb in
            climb.healthKitUUID.map { ($0, climb) }
        })
        #expect(byUUID[ranks.uuid.uuidString]?.leaderboardStatus == .eligible)
        #expect(byUUID[offBoards.uuid.uuidString]?.leaderboardStatus == .excluded)
        #expect(byUUID[offBoards.uuid.uuidString]?.steps == 7_500, "kept, only off the boards")
        #expect(byUUID[offBoards.uuid.uuidString]?.canHoldRecords == false)
        #expect(byUUID[absurd.uuid.uuidString]?.isMissingSteps == true, "a number no stair stepper produces is dropped")
    }

    @Test
    func aWorkoutWithNoStepsAndAnEmptyWindowStillAsksForItsSteps() async throws {
        let harness = try AppleHealthImportHarness()
        harness.addWorkout(daysAgo: 1, steps: nil, windowSteps: nil)
        await harness.service.syncNow()

        let climb = try #require(try harness.climbs().first)
        #expect(climb.steps == 0)
        #expect(climb.isMissingSteps)
        #expect(climb.recordedSteps == nil)
        #expect(ImportsRowFormat.stepsText(climb.recordedSteps) == "Add steps")
        #expect(harness.reader.windowReads.count >= 1, "the window was looked at before giving up")
    }

    @Test
    func stepsThatReachHealthAfterTheWorkoutWasFoundAreReadWhenItImports() async throws {
        let harness = try AppleHealthImportHarness()
        await harness.service.setAutoImportEnabled(false)
        let workout = harness.addWorkout(daysAgo: 1, steps: nil, minutes: 30)
        await harness.service.syncNow()
        #expect(try harness.record(workout)?.steps == nil, "found before the phone had counted anything")

        // The watch hands its steps to Health a few minutes after the workout itself.
        harness.reader.windowSteps[workout.startDate] = 2_880
        await harness.service.importRecords(withUUIDs: [workout.uuid.uuidString])

        #expect(try harness.climbs().first?.steps == 2_880)
        #expect(try harness.record(workout)?.steps == 2_880)
    }

    @Test
    func aWindowReadThatFailsAtImportTimeKeepsTheStepsTheWorkoutWasFoundWith() async throws {
        let harness = try AppleHealthImportHarness()
        await harness.service.setAutoImportEnabled(false)
        let workout = harness.addWorkout(daysAgo: 1, steps: nil, minutes: 30, windowSteps: 3_150)
        await harness.service.syncNow()
        #expect(try harness.record(workout)?.steps == 3_150)

        harness.reader.windowReadError = CocoaError(.fileReadUnknown)
        await harness.service.importRecords(withUUIDs: [workout.uuid.uuidString])

        let climb = try #require(try harness.climbs().first)
        #expect(climb.steps == 3_150, "a number already found is not lost to one failed read")
        #expect(!climb.isMissingSteps)
    }

    @Test
    func aWaitingWorkoutShowsItsWindowStepsInImportsBeforeItIsImported() async throws {
        let harness = try AppleHealthImportHarness()
        await harness.service.setAutoImportEnabled(false)
        let workout = harness.addWorkout(daysAgo: 1, steps: nil, minutes: 30, windowSteps: 3_150)
        await harness.service.syncNow()

        let record = try #require(try harness.record(workout))
        #expect(record.state == .notImported)
        #expect(record.importableSteps == 3_150, "the Not imported row names the number the climb will carry")
    }

    // MARK: - History

    @Test
    func theHistoryBackfillAppliesTheSameRule() async throws {
        let harness = try AppleHealthImportHarness()
        let carried = harness.addWorkout(daysAgo: 60, steps: 3_000, minutes: 40)
        let windowOnly = harness.addWorkout(daysAgo: 90, steps: nil, minutes: 35, windowSteps: 4_025)
        let neither = harness.addWorkout(daysAgo: 120, steps: nil, minutes: 35)

        let landed = await harness.importHistory()

        #expect(landed)
        let byUUID = Dictionary(uniqueKeysWithValues: try harness.climbs().compactMap { climb in
            climb.healthKitUUID.map { ($0, climb) }
        })
        #expect(byUUID[carried.uuid.uuidString]?.steps == 3_000)
        #expect(byUUID[windowOnly.uuid.uuidString]?.steps == 4_025)
        #expect(byUUID[windowOnly.uuid.uuidString]?.canHoldRecords == true, "history with steps fills personal bests")
        #expect(byUUID[windowOnly.uuid.uuidString]?.leaderboardStatus == .excluded, "and never a leaderboard")
        #expect(byUUID[neither.uuid.uuidString]?.isMissingSteps == true)
    }

    @Test
    func theHistoryScreensTotalIsTheTotalTheBackfillLands() async throws {
        let harness = try AppleHealthImportHarness()
        harness.addWorkout(daysAgo: 60, steps: 3_000, minutes: 40)
        harness.addWorkout(daysAgo: 90, steps: nil, minutes: 35, windowSteps: 4_025)
        harness.addWorkout(daysAgo: 120, steps: nil, minutes: 35)

        let history = try await HealthHistory.load(using: harness.reader, skipReporter: harness.skipReporter)
        let promised = history.summary(now: harness.referenceNow)
        await harness.service.importHistory(matching: Set(promised.workoutIDs))

        let landed = try harness.climbs().reduce(0) { $0 + $1.steps }
        #expect(promised.knownSteps == 7_025)
        #expect(landed == promised.knownSteps)
        #expect(try harness.climbs().count == promised.workoutCount)
    }
}
