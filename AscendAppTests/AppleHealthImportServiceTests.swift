import Foundation
import SwiftData
import Testing
@testable import AscendApp

/// Apple Health import, end to end through the real service against a fake Health database and an
/// in-memory store: what a workout becomes, what never imports twice, what skipping and removing
/// mean, what the badge counts, and what each mode does when a new workout arrives.
@MainActor
@Suite(.serialized)
struct AppleHealthImportServiceTests {
    // MARK: - What a workout becomes

    @Test
    func anImportedWorkoutCarriesEverythingHealthRecordedExactly() async throws {
        let harness = try AppleHealthImportHarness()
        harness.addWorkout(daysAgo: 1, steps: 4_912, minutes: 62.8333, averageHeartRate: 127, maxHeartRate: 158, energy: 411)
        await harness.service.setAutoImportEnabled(false)
        await harness.service.syncNow()

        let record = try #require(try harness.records().first)
        let batch = await harness.service.importRecords(withUUIDs: [record.workoutUUID])
        #expect(batch.count == 1)

        let climb = try #require(try harness.climbs().first)
        #expect(climb.source == .appleHealth)
        #expect(climb.origin == .healthImport)
        #expect(climb.steps == 4_912, "Health's number is kept exactly, never rounded or prefixed with a tilde")
        #expect(climb.recordedSteps == 4_912)
        #expect(climb.floors == Workout.stepsToFloors(4_912))
        #expect(climb.avgHeartRate == 127)
        #expect(climb.maxHeartRate == 158)
        #expect(climb.caloriesBurned == 411)
        #expect(climb.duration == record.durationSeconds)
        #expect(climb.date == record.startDate)
        #expect(climb.healthKitUUID == record.workoutUUID)
        #expect(climb.leaderboardStatus == .eligible)
        #expect(record.state == .imported)
        #expect(record.importedWorkoutID == climb.id)
    }

    @Test
    func aWorkoutWithNoStepsImportsAsAMissingNumberNotAZeroClaim() async throws {
        let harness = try AppleHealthImportHarness()
        harness.addWorkout(daysAgo: 1, steps: nil)
        await harness.service.syncNow()

        let climb = try #require(try harness.climbs().first)
        #expect(climb.steps == 0)
        #expect(climb.isMissingSteps, "the climb asks for its steps instead of claiming none")
        #expect(climb.recordedSteps == nil)
        #expect(ImportsRowFormat.stepsText(climb.recordedSteps) == "Add steps")
        #expect(climb.leaderboardStatus == .excluded, "a climb with no steps has nothing to rank on")
    }

    @Test
    func theAutomaticPlausibilityCheckJudgesAnImportOnItsPace() async throws {
        let harness = try AppleHealthImportHarness()
        let withinCeiling = harness.addWorkout(daysAgo: 1, steps: 6_000, minutes: 30)      // 200 a minute
        let aboveCeiling = harness.addWorkout(daysAgo: 2, steps: 7_500, minutes: 30)       // 250 a minute
        let absurd = harness.addWorkout(daysAgo: 3, steps: 12_000, minutes: 30)            // 400 a minute
        await harness.service.syncNow()

        let byUUID = Dictionary(uniqueKeysWithValues: try harness.climbs().compactMap { climb in
            climb.healthKitUUID.map { ($0, climb) }
        })
        #expect(byUUID[withinCeiling.uuid.uuidString]?.leaderboardStatus == .eligible)
        #expect(byUUID[aboveCeiling.uuid.uuidString]?.leaderboardStatus == .excluded)
        #expect(byUUID[aboveCeiling.uuid.uuidString]?.steps == 7_500, "kept, only off the boards")
        // An import cannot be refused the way a typed save is, so the one number no stair stepper
        // produces is dropped and the climb arrives asking for its steps.
        #expect(byUUID[absurd.uuid.uuidString]?.steps == 0)
        #expect(byUUID[absurd.uuid.uuidString]?.isMissingSteps == true)
    }

    @Test
    func editingTheStepsOfAnImportRunsTheCheckAgain() async throws {
        let harness = try AppleHealthImportHarness()
        harness.addWorkout(daysAgo: 1, steps: 7_500, minutes: 30)
        await harness.service.syncNow()
        let climb = try #require(try harness.climbs().first)
        #expect(climb.leaderboardStatus == .excluded)

        let viewModel = ImportedClimbQuickEditViewModel(workout: climb, applyUpdate: { _, _, _ in })
        viewModel.stepsText = "5400"
        #expect(viewModel.stepsChanged)
        #expect(try await viewModel.finish(modelContext: harness.context))

        #expect(climb.steps == 5_400)
        #expect(climb.floors == Workout.stepsToFloors(5_400))
        #expect(climb.leaderboardStatus == .eligible, "matching the console brings it back inside the ceiling")
    }

    @Test
    func aNoteOrEffortNeverReRunsThePaceCheck() async throws {
        let harness = try AppleHealthImportHarness()
        harness.addWorkout(daysAgo: 1, steps: 7_500, minutes: 30)
        await harness.service.syncNow()
        let climb = try #require(try harness.climbs().first)
        climb.leaderboardStatus = .eligible   // a verdict a note must not disturb

        let viewModel = ImportedClimbQuickEditViewModel(workout: climb, applyUpdate: { _, _, _ in })
        viewModel.note = "Felt strong"
        viewModel.effortRating = 4
        #expect(!viewModel.stepsChanged)
        #expect(try await viewModel.finish(modelContext: harness.context))

        #expect(climb.notes == "Felt strong")
        #expect(climb.effortRating == 4)
        #expect(climb.leaderboardStatus == .eligible)
    }

    @Test
    func theQuickEditRefusesStepsNoStairStepperProduces() async throws {
        let harness = try AppleHealthImportHarness()
        harness.addWorkout(daysAgo: 1, steps: 3_000, minutes: 30)
        await harness.service.syncNow()
        let climb = try #require(try harness.climbs().first)

        let viewModel = ImportedClimbQuickEditViewModel(workout: climb, applyUpdate: { _, _, _ in })
        viewModel.stepsText = "20000"
        #expect(viewModel.refusalMessage != nil)
        #expect(!viewModel.canFinish)
        #expect(try await viewModel.finish(modelContext: harness.context) == false)
        #expect(climb.steps == 3_000)
    }

    // MARK: - Never twice

    @Test
    func aWorkoutNeverImportsTwiceAcrossPasses() async throws {
        let harness = try AppleHealthImportHarness()
        harness.addWorkout(daysAgo: 1)
        await harness.service.syncNow()
        await harness.service.syncNow()
        // A reader that hands back the same workout again, as a lost anchor would.
        harness.settings.setAnchorData(nil, for: AppleHealthImportHarness.userID)
        await harness.service.syncNow()

        #expect(try harness.climbs().count == 1)
        #expect(try harness.records().count == 1)
    }

    @Test
    func aClimbRestoredFromTheCloudStopsItsWorkoutImportingAgain() async throws {
        let harness = try AppleHealthImportHarness()
        let snapshot = harness.addWorkout(daysAgo: 1)
        let restored = Workout(
            name: "Stair Stepper", date: snapshot.startDate, duration: snapshot.duration,
            steps: 3_000, floors: 187, source: .appleHealth, healthKitUUID: snapshot.uuid.uuidString
        )
        harness.context.insert(restored)
        try harness.context.save()

        await harness.service.syncNow()

        #expect(try harness.climbs().count == 1, "a ledger lost with the old phone does not import it a second time")
        let record = try #require(try harness.record(snapshot))
        #expect(record.state == .imported)
        #expect(record.importedWorkoutID == restored.id)
    }

    @Test
    func aWorkoutDeletedInHealthKeepsItsClimb() async throws {
        let harness = try AppleHealthImportHarness()
        harness.addWorkout(daysAgo: 1)
        await harness.service.syncNow()
        #expect(try harness.climbs().count == 1)

        harness.reader.workouts.removeAll()
        await harness.service.syncNow()

        #expect(try harness.climbs().count == 1, "the climb is the climber's data")
        #expect(try harness.records().first?.state == .imported)
    }

    // MARK: - Skip and remove

    @Test(arguments: [true, false])
    func aSkippedWorkoutNeverComesBackInEitherMode(autoImport: Bool) async throws {
        let harness = try AppleHealthImportHarness()
        await harness.service.setAutoImportEnabled(false)
        let snapshot = harness.addWorkout(daysAgo: 1)
        await harness.service.syncNow()
        harness.service.skip(recordUUID: snapshot.uuid.uuidString)
        #expect(try harness.record(snapshot)?.state == .skipped)

        await harness.service.setAutoImportEnabled(autoImport)
        harness.settings.setAnchorData(nil, for: AppleHealthImportHarness.userID)
        await harness.service.syncNow()
        _ = await harness.service.importRecords(withUUIDs: [snapshot.uuid.uuidString])

        #expect(try harness.climbs().isEmpty)
        #expect(try harness.record(snapshot)?.state == .skipped)
        #expect(try harness.service.entry == .viewImports(badge: 0))
    }

    @Test(arguments: [true, false])
    func removingAnImportedClimbMarksItsWorkoutSkippedForever(autoImport: Bool) async throws {
        let harness = try AppleHealthImportHarness()
        let snapshot = harness.addWorkout(daysAgo: 1)
        await harness.service.syncNow()
        let climb = try #require(try harness.climbs().first)

        await harness.service.setAutoImportEnabled(autoImport)
        await harness.service.removeImportedClimb(workoutID: climb.id)

        #expect(try harness.climbs().isEmpty)
        #expect(try harness.record(snapshot)?.state == .skipped)

        harness.settings.setAnchorData(nil, for: AppleHealthImportHarness.userID)
        await harness.service.syncNow()
        #expect(try harness.climbs().isEmpty, "removed means removed, in either mode")
    }

    @Test
    func deletingAnImportedClimbFromItsSummaryAlsoMarksItSkipped() async throws {
        let harness = try AppleHealthImportHarness()
        let snapshot = harness.addWorkout(daysAgo: 1)
        await harness.service.syncNow()
        let climb = try #require(try harness.climbs().first)

        // The path WorkoutDetailView and the climbs list take: the ledger row changes in the same
        // save that deletes the climb.
        HealthWorkoutLedger(modelContext: harness.context).markSkippedForDeletedClimbs([climb])
        harness.context.delete(climb)
        try harness.context.save()

        #expect(try harness.record(snapshot)?.state == .skipped)
        harness.settings.setAnchorData(nil, for: AppleHealthImportHarness.userID)
        await harness.service.syncNow()
        #expect(try harness.climbs().isEmpty)
    }

    @Test
    func undoDeletesTheClimbsAndReturnsTheWorkoutsToNotImported() async throws {
        let harness = try AppleHealthImportHarness()
        await harness.service.setAutoImportEnabled(false)
        let first = harness.addWorkout(daysAgo: 1)
        let second = harness.addWorkout(daysAgo: 2)
        await harness.service.syncNow()

        let batch = await harness.service.importRecords(
            withUUIDs: [first.uuid.uuidString, second.uuid.uuidString]
        )
        #expect(batch.count == 2)
        #expect(try harness.climbs().count == 2)

        await harness.service.undo(batch)

        #expect(try harness.climbs().isEmpty)
        #expect(try harness.record(first)?.state == .notImported)
        #expect(try harness.record(second)?.state == .notImported)
        #expect(try harness.record(first)?.importedWorkoutID == nil)

        // Undone is not skipped: the workouts are still on offer.
        let again = await harness.service.importRecords(withUUIDs: [first.uuid.uuidString])
        #expect(again.count == 1)
    }

    // MARK: - The badge

    @Test
    func theBadgeCountsOnlyWaitingWorkoutsFromTheLastSevenDaysAndOnlyWithAutoImportOff() async throws {
        let harness = try AppleHealthImportHarness()
        harness.addWorkout(daysAgo: 1)
        harness.addWorkout(daysAgo: 6)
        harness.addWorkout(daysAgo: 9)   // too old for the badge, still waiting in Imports

        await harness.service.setAutoImportEnabled(true)
        await harness.service.syncNow()
        #expect(harness.service.badgeCount == 0, "with auto-import on nothing ever waits, so there is no badge")
        #expect(try harness.service.entry == .viewImports(badge: 0))

        let harnessOff = try AppleHealthImportHarness()
        await harnessOff.service.setAutoImportEnabled(false)
        harnessOff.addWorkout(daysAgo: 1)
        harnessOff.addWorkout(daysAgo: 6)
        harnessOff.addWorkout(daysAgo: 9)
        await harnessOff.service.syncNow()

        #expect(harnessOff.service.badgeCount == 2)
        #expect(try harnessOff.records().count == 3)
        #expect(harnessOff.service.entry == .viewImports(badge: 2))
    }

    @Test
    func theBadgeClearsWhenImportsOpensEvenIfNothingIsImported() async throws {
        let harness = try AppleHealthImportHarness()
        await harness.service.setAutoImportEnabled(false)
        harness.addWorkout(daysAgo: 1)
        harness.addWorkout(daysAgo: 2)
        await harness.service.syncNow()
        #expect(harness.service.badgeCount == 2)

        harness.clock = AppleHealthImportHarness.now.addingTimeInterval(60)
        harness.service.markImportsViewed()

        #expect(harness.service.badgeCount == 0)
        #expect(try harness.records().filter { $0.state == .notImported }.count == 2, "still waiting, just not news")
    }

    @Test
    func aWorkoutFoundAfterImportsWasLastOpenedRaisesTheBadgeAgain() async throws {
        let harness = try AppleHealthImportHarness()
        await harness.service.setAutoImportEnabled(false)
        harness.addWorkout(daysAgo: 2)
        await harness.service.syncNow()
        harness.service.markImportsViewed()
        #expect(harness.service.badgeCount == 0)

        // Nothing new arrived, so a later pass does not raise it.
        harness.clock = AppleHealthImportHarness.now.addingTimeInterval(1_800)
        await harness.service.syncNow()
        #expect(harness.service.badgeCount == 0)

        // The watch hands over a workout that started before the last visit and only reaches the
        // phone after it: the first time Ascend sees it, it is news.
        harness.clock = AppleHealthImportHarness.now.addingTimeInterval(3_600)
        let lateStart = AppleHealthImportHarness.now.addingTimeInterval(-1_800)
        harness.reader.workouts.append(
            HealthWorkoutSnapshot(uuid: UUID(), startDate: lateStart, endDate: lateStart.addingTimeInterval(1_500), steps: 2_500)
        )
        await harness.service.syncNow()
        #expect(harness.service.badgeCount == 1)

        // Opening Imports clears it again.
        harness.clock = AppleHealthImportHarness.now.addingTimeInterval(3_660)
        harness.service.markImportsViewed()
        #expect(harness.service.badgeCount == 0)

        // A workout found late that started more than a week ago waits in Imports without a badge.
        harness.clock = AppleHealthImportHarness.now.addingTimeInterval(7_200)
        harness.addWorkout(daysAgo: 9)
        await harness.service.syncNow()
        #expect(harness.service.badgeCount == 0)
        #expect(try harness.records().filter { $0.state == .notImported }.count == 3)
    }

    // MARK: - Auto-import on and off

    @Test
    func withAutoImportOnANewWorkoutImportsAnnouncesAndSetsTheHomeStrip() async throws {
        let harness = try AppleHealthImportHarness()
        await harness.service.syncNow()   // the first pass: nothing there, but the anchor now exists
        let snapshot = harness.addWorkout(daysAgo: 0.02, steps: 4_912, minutes: 62)
        await harness.service.syncNow()

        let climb = try #require(try harness.climbs().first)
        #expect(climb.steps == 4_912)
        #expect(harness.notifier.imported.count == 1)
        #expect(harness.notifier.imported.first?.workoutID == climb.id)
        #expect(harness.notifier.imported.first?.steps == 4_912)

        let notice = try #require(harness.service.homeNotice)
        #expect(notice.workoutID == climb.id)
        #expect(notice.steps == 4_912)
        #expect(try harness.record(snapshot)?.homeNoticePending == true)
    }

    @Test
    func theHomeStripAndTheWaitingRowAskForStepsOnACountTheClimbWouldDrop() async throws {
        let harness = try AppleHealthImportHarness()
        await harness.service.syncNow()
        harness.addWorkout(daysAgo: 0.02, steps: 50_000, minutes: 1)
        await harness.service.syncNow()

        let climb = try #require(try harness.climbs().first)
        #expect(climb.isMissingSteps)
        #expect(try #require(harness.service.homeNotice).steps == nil, "the strip names what the climb holds")

        let waiting = HealthWorkoutRecord(
            snapshot: HealthWorkoutSnapshot(
                uuid: UUID(),
                startDate: AppleHealthImportHarness.now,
                endDate: AppleHealthImportHarness.now.addingTimeInterval(60),
                duration: 60,
                steps: 50_000,
                averageHeartRate: nil,
                maxHeartRate: nil,
                activeEnergyKilocalories: nil,
                sourceName: nil
            )
        )
        let sections = ImportsSections.make(records: [waiting], climbs: [:], now: AppleHealthImportHarness.now)
        #expect(sections.notImported.first?.steps == nil)
    }

    @Test
    func theHomeStripStopsAskingForStepsOnceTheClimbHasThem() async throws {
        let harness = try AppleHealthImportHarness()
        await harness.service.syncNow()
        harness.addWorkout(daysAgo: 0.02, steps: nil, minutes: 25)
        await harness.service.syncNow()

        let climb = try #require(try harness.climbs().first)
        #expect(try #require(harness.service.homeNotice).steps == nil)

        climb.steps = 3_300
        climb.duration = 1_800
        try harness.context.save()
        harness.service.refreshDerivedState()

        let notice = try #require(harness.service.homeNotice)
        #expect(notice.steps == 3_300)
        #expect(notice.duration == 1_800)
    }

    @Test
    func addStepsOnAWaitingRowImportsItAndResolvesTheClimbOnTheSameTurn() async throws {
        let harness = try AppleHealthImportHarness()
        await harness.service.setAutoImportEnabled(false)
        harness.addWorkout(daysAgo: 1, steps: nil)
        await harness.service.syncNow()
        let viewModel = AppleHealthImportsViewModel(service: harness.service)
        await viewModel.onAppear(modelContext: harness.context)
        let waiting = try #require(viewModel.sections.notImported.first)
        #expect(waiting.steps == nil && waiting.climbID == nil)

        let climb = try #require(await viewModel.climbToAddSteps(to: waiting))

        #expect(climb.isMissingSteps)
        #expect(climb.healthKitUUID == waiting.id)
        #expect(viewModel.sections.notImported.isEmpty, "the row has moved")

        let imported = try #require((viewModel.sections.thisWeek + viewModel.sections.earlier).first)
        let again = await viewModel.climbToAddSteps(to: imported)
        #expect(again?.id == climb.id, "an imported row opens its own climb")
        #expect(try harness.climbs().count == 1, "and imports nothing a second time")
        #expect(viewModel.toast?.batch.count == 1)
    }

    @Test
    func theFirstPassAfterConnectingImportsHistoryWithoutAnnouncingIt() async throws {
        let harness = try AppleHealthImportHarness()
        harness.addWorkout(daysAgo: 3)
        harness.addWorkout(daysAgo: 5)
        await harness.service.syncNow()

        #expect(try harness.climbs().count == 2)
        #expect(harness.notifier.imported.isEmpty, "history is not news")
        #expect(harness.service.homeNotice == nil)
    }

    @Test
    func withAutoImportOffANewWorkoutOnlyWaitsAndNothingIsSent() async throws {
        let harness = try AppleHealthImportHarness()
        await harness.service.setAutoImportEnabled(false)
        await harness.service.syncNow()
        harness.addWorkout(daysAgo: 0.02)
        await harness.service.syncNow()

        #expect(try harness.climbs().isEmpty)
        #expect(try harness.records().first?.state == .notImported)
        #expect(harness.notifier.imported.isEmpty, "no push; the badge is the signal")
        #expect(harness.service.homeNotice == nil)
        #expect(harness.service.badgeCount == 1)
    }

    @Test
    func turningAutoImportOnImportsWhatWasWaitingWithoutAnnouncingIt() async throws {
        let harness = try AppleHealthImportHarness()
        await harness.service.setAutoImportEnabled(false)
        harness.addWorkout(daysAgo: 1)
        harness.addWorkout(daysAgo: 2)
        await harness.service.syncNow()
        #expect(try harness.climbs().isEmpty)

        await harness.service.setAutoImportEnabled(true)

        #expect(try harness.climbs().count == 2)
        #expect(harness.notifier.imported.isEmpty)
        #expect(harness.service.badgeCount == 0)
    }

    @Test
    func connectingAfterOnboardingFindsWorkoutsWithoutImportingUntilTheClimberChooses() async throws {
        let harness = try AppleHealthImportHarness()
        harness.addWorkout(daysAgo: 1)
        harness.addWorkout(daysAgo: 4)

        let found = await harness.service.discoverWithoutImporting()
        #expect(found == 2)
        #expect(try harness.climbs().isEmpty)

        let letMeChoose = AppleHealthConnectViewModel(authorization: harness.authorization, importService: harness.service)
        letMeChoose.choosesAutomatic = false
        await letMeChoose.confirmChoice()
        #expect(try harness.climbs().isEmpty)
        #expect(harness.service.isAutoImportEnabled == false)

        let automatic = AppleHealthConnectViewModel(authorization: harness.authorization, importService: harness.service)
        automatic.choosesAutomatic = true
        await automatic.confirmChoice()
        #expect(try harness.climbs().count == 2)
        #expect(harness.service.isAutoImportEnabled)
    }

    @Test
    func autoImportDefaultsOnAndIsPerClimber() throws {
        let harness = try AppleHealthImportHarness()
        #expect(harness.service.isAutoImportEnabled, "onboarding never shows the choice, so on is what it lives with")

        harness.settings.setAutoImportEnabled(false, for: "someone-else")
        #expect(harness.settings.isAutoImportEnabled(for: AppleHealthImportHarness.userID))
        #expect(harness.settings.isAutoImportEnabled(for: "someone-else") == false)
    }

    // MARK: - Who and what counts

    @Test
    func onlyWorkoutsOnOrAfterTheJoinDateAreEverFiled() async throws {
        let harness = try AppleHealthImportHarness()
        let before = harness.addWorkout(daysAgo: 45)   // joined 30 days ago
        let after = harness.addWorkout(daysAgo: 10)
        await harness.service.syncNow()

        #expect(try harness.record(before) == nil, "history before the join date never reaches Imports")
        #expect(try harness.record(after) != nil)
        #expect(harness.reader.changeReads.first?.earliest == AppleHealthImportHarness.joinDate)
    }

    @Test
    func aWorkoutThatOverlapsALiveClimbIsNotASecondClimb() async throws {
        let harness = try AppleHealthImportHarness()
        let snapshot = harness.addWorkout(daysAgo: 1, minutes: 30)
        let live = Workout(
            name: "Live", date: snapshot.startDate.addingTimeInterval(120), duration: 1_500,
            steps: 2_400, floors: 150, source: .headphoneMotion
        )
        harness.context.insert(live)
        try harness.context.save()

        await harness.service.syncNow()

        #expect(try harness.climbs().count == 1, "the live climb is the climb")
        #expect(try harness.record(snapshot)?.state == .overlapsLiveClimb, "kept for the overlap merge")
        let imports = ImportsSections.make(records: try harness.records(), climbs: [:], now: AppleHealthImportHarness.now)
        #expect(imports.isEmpty, "and it is never offered in Imports")
    }

    @Test
    func aLiveClimbThatOnlyTouchesTheWorkoutImportsNormally() async throws {
        let harness = try AppleHealthImportHarness()
        let snapshot = harness.addWorkout(daysAgo: 1, minutes: 30)
        let live = Workout(
            name: "Live", date: snapshot.endDate.addingTimeInterval(-30), duration: 1_500,
            steps: 2_400, floors: 150, source: .headphoneMotion
        )
        harness.context.insert(live)
        try harness.context.save()

        await harness.service.syncNow()

        #expect(try harness.climbs().count == 2, "thirty seconds of overlap is under the minute")
        #expect(try harness.record(snapshot)?.state == .imported)
    }

    @Test
    func aWorkoutDuringALiveSessionThatHasNotSavedWaitsForIt() async throws {
        let harness = try AppleHealthImportHarness()
        let snapshot = harness.addWorkout(daysAgo: 0.1, minutes: 30)
        let draft = ActiveHeadphoneWorkoutDraft(
            sessionID: "live-session",
            kind: .liveClimb,
            startedAt: snapshot.startDate.addingTimeInterval(60),
            title: "Live",
            subtitle: "",
            workoutName: "Live",
            targetStepCount: nil,
            targetDurationSeconds: nil
        )
        draft.lastCheckpointAt = snapshot.endDate.addingTimeInterval(60)
        harness.context.insert(draft)
        try harness.context.save()

        await harness.service.syncNow()
        #expect(try harness.climbs().isEmpty, "the session will save the climb that covers it")
        #expect(try harness.record(snapshot)?.state == .notImported, "it waits to be checked again")

        // The session saves its climb and its draft goes.
        harness.context.delete(draft)
        harness.context.insert(
            Workout(
                name: "Live", date: snapshot.startDate.addingTimeInterval(60), duration: 1_800,
                steps: 2_400, floors: 150, source: .headphoneMotion
            )
        )
        try harness.context.save()

        await harness.service.syncNow()
        #expect(try harness.climbs().count == 1, "the live climb is the climb")
        #expect(try harness.record(snapshot)?.state == .overlapsLiveClimb)
    }

    @Test
    func aDraftThatEndedBeforeTheWorkoutDoesNotHoldItBack() async throws {
        let harness = try AppleHealthImportHarness()
        let snapshot = harness.addWorkout(daysAgo: 0.1, minutes: 30)
        let draft = ActiveHeadphoneWorkoutDraft(
            sessionID: "earlier-session",
            kind: .justClimb,
            startedAt: snapshot.startDate.addingTimeInterval(-3_600),
            title: "Earlier",
            subtitle: "",
            workoutName: "Earlier",
            targetStepCount: nil,
            targetDurationSeconds: nil
        )
        draft.lastCheckpointAt = snapshot.startDate.addingTimeInterval(-600)
        harness.context.insert(draft)
        try harness.context.save()

        await harness.service.syncNow()
        #expect(try harness.record(snapshot)?.state == .imported)
    }

    // MARK: - The first pass on a device

    @Test
    func theFirstPassWaitsForTheClimbersClimbsToComeBackFromTheCloud() async throws {
        let harness = try AppleHealthImportHarness()
        // Signing out clears the confirmation the bootstrap gave, so this is a fresh session.
        harness.service.cancelInFlightWork()
        let snapshot = harness.addWorkout(daysAgo: 3)

        await harness.service.syncNow()
        #expect(harness.reader.changeReads.isEmpty, "nothing is read while the restore is outstanding")
        #expect(try harness.records().isEmpty)
        #expect(harness.settings.anchorData(for: AppleHealthImportHarness.userID) == nil)

        // The restore lands the climb this workout already became on the old phone.
        let restored = Workout(
            name: "Stair Stepper", date: snapshot.startDate, duration: snapshot.duration,
            steps: 3_000, floors: 187, source: .appleHealth, healthKitUUID: snapshot.uuid.uuidString
        )
        harness.context.insert(restored)
        try harness.context.save()

        // Another climber's restore does not vouch for this one.
        harness.service.confirmCloudClimbsRestored(for: "someone-else")
        await harness.service.syncNow()
        #expect(harness.reader.changeReads.isEmpty)

        harness.service.confirmCloudClimbsRestored(for: AppleHealthImportHarness.userID)

        await harness.service.syncNow()
        #expect(try harness.climbs().count == 1, "the restored climb, and no second one")
        #expect(try harness.record(snapshot)?.importedWorkoutID == restored.id)
    }

    @Test
    func aPassWithAnAnchorDoesNotWaitForTheRestore() async throws {
        let harness = try AppleHealthImportHarness()
        harness.addWorkout(daysAgo: 3)
        await harness.service.syncNow()
        #expect(try harness.climbs().count == 1)

        // A relaunch in the background: the restore has not run in this process, but this device
        // has already read Health, so what arrives now is new.
        harness.service.cancelInFlightWork()
        harness.addWorkout(daysAgo: 0.01)
        await harness.service.syncNow()
        #expect(try harness.climbs().count == 2)
    }

    // MARK: - Gates

    @Test
    func theKillSwitchStopsImportWithoutAdvancingTheAnchor() async throws {
        let off = RemoteFeatureFlagStore(snapshot: .resolving(remoteValues: [RemoteFeatureFlag.appleHealthImport.key: false]))
        let harness = try AppleHealthImportHarness(featureFlags: off)
        harness.addWorkout(daysAgo: 1)

        await harness.service.syncNow()
        #expect(harness.reader.changeReads.isEmpty)
        #expect(try harness.records().isEmpty)
        #expect(harness.settings.anchorData(for: AppleHealthImportHarness.userID) == nil)
        #expect(harness.service.entry == nil, "the entry points go away with the feature")

        off.apply(.shippedDefaults)
        await harness.service.syncNow()
        #expect(try harness.climbs().count == 1, "turned back on, it resumes from the same anchor")
    }

    @Test
    func turningAutoImportOnWithTheKillSwitchOffImportsNothing() async throws {
        let flags = RemoteFeatureFlagStore()
        let harness = try AppleHealthImportHarness(featureFlags: flags)
        await harness.service.setAutoImportEnabled(false)
        let snapshot = harness.addWorkout(daysAgo: 1)
        await harness.service.syncNow()
        #expect(try harness.record(snapshot)?.state == .notImported)

        flags.apply(.resolving(remoteValues: [RemoteFeatureFlag.appleHealthImport.key: false]))
        await harness.service.setAutoImportEnabled(true)
        #expect(try harness.climbs().isEmpty, "the switch stops every way a climb is created")
        let tapped = await harness.service.importRecords(withUUIDs: [snapshot.uuid.uuidString])
        #expect(tapped.isEmpty)
        #expect(try harness.record(snapshot)?.state == .notImported)
    }

    @Test
    func connectingRegistersForBackgroundDelivery() async throws {
        let harness = try AppleHealthImportHarness()
        harness.authorization.importConnectionState = .neverConnected
        harness.service.startObservingIfPossible()
        #expect(!harness.reader.isObserving, "nothing to listen for before the climber connects")

        let connect = AppleHealthConnectViewModel(authorization: harness.authorization, importService: harness.service)
        await connect.requestAccess()

        #expect(harness.reader.isObserving, "a watch workout wakes the app from now on, not from the next launch")
    }

    @Test
    func nothingReadsHealthUntilTheClimberHasConnected() async throws {
        let harness = try AppleHealthImportHarness()
        harness.authorization.importConnectionState = .neverConnected
        harness.addWorkout(daysAgo: 1)

        await harness.service.syncNow()
        #expect(harness.reader.changeReads.isEmpty)
        #expect(harness.service.entry == .connect)

        harness.authorization.importConnectionState = .unavailable
        #expect(harness.service.entry == nil)
    }

    @Test
    func aRetiredBuildAndASignedOutSessionDoNotImport() async throws {
        let harness = try AppleHealthImportHarness()
        harness.addWorkout(daysAgo: 1)

        harness.isUpdateRequired = true
        await harness.service.syncNow()
        #expect(harness.reader.changeReads.isEmpty)

        harness.isUpdateRequired = false
        harness.userID = nil
        await harness.service.syncNow()
        #expect(harness.reader.changeReads.isEmpty)
    }

    @Test
    func aFailedReadLeavesTheAnchorAndTheLedgerAlone() async throws {
        let harness = try AppleHealthImportHarness()
        harness.addWorkout(daysAgo: 1)
        harness.reader.readError = NSError(domain: "HKErrorDomain", code: 5)

        await harness.service.syncNow()
        #expect(try harness.records().isEmpty)
        #expect(harness.settings.anchorData(for: AppleHealthImportHarness.userID) == nil)

        harness.reader.readError = nil
        await harness.service.syncNow()
        #expect(try harness.climbs().count == 1)
    }

    // MARK: - The observer

    @Test
    func theObserverCompletionHandlerIsAlwaysCalled() async throws {
        let harness = try AppleHealthImportHarness()
        harness.service.startObservingIfPossible()
        #expect(harness.reader.isObserving)

        harness.addWorkout(daysAgo: 0.01)
        let completed = LockedFlag()
        harness.reader.deliverObserverNotification { completed.set() }
        try await waitUntil { completed.isSet }
        #expect(try harness.climbs().count == 1, "the pass ran before HealthKit was released")

        // And when the pass fails, HealthKit is still released.
        harness.reader.readError = NSError(domain: "HKErrorDomain", code: 5)
        let completedAfterFailure = LockedFlag()
        harness.reader.deliverObserverNotification { completedAfterFailure.set() }
        try await waitUntil { completedAfterFailure.isSet }
    }

    @Test
    func aPassThatNeverFinishesStillReleasesHealthKitWithinTheBound() async throws {
        let harness = try AppleHealthImportHarness(observerCompletionBound: .milliseconds(50))
        harness.service.startObservingIfPossible()
        harness.reader.readDelay = .seconds(5)

        let completed = LockedFlag()
        harness.reader.deliverObserverNotification { completed.set() }
        try await waitUntil { completed.isSet }
        #expect(completed.isSet)
        harness.service.cancelInFlightWork()
    }

    @Test
    func signingOutStopsListening() async throws {
        let harness = try AppleHealthImportHarness()
        harness.service.startObservingIfPossible()
        #expect(harness.reader.isObserving)

        harness.service.cancelInFlightWork()
        #expect(!harness.reader.isObserving)
        #expect(harness.service.badgeCount == 0)
        #expect(harness.service.homeNotice == nil)
    }

    // MARK: - Helpers

    private func waitUntil(timeout: Duration = .seconds(3), _ condition: @escaping @Sendable () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("condition never became true")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock(); defer { lock.unlock() }
        value = true
    }
}
