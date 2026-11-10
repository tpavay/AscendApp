import Foundation
import SwiftUI
import Testing
@testable import AscendApp

/// Onboarding's Apple Health branch (06, 06b, 07a): what each screen asks of Health, where it routes,
/// what it leaves on the device, and that nothing reaches an account before there is one.
@MainActor
@Suite(.serialized)
struct OnboardingV3HealthTests {
    private func makeStore() -> PreAuthOnboardingStore {
        let suite = "onboarding-v3-health-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return PreAuthOnboardingStore(userDefaults: defaults)
    }

    private func coordinator(at step: OnboardingV3Step, store: PreAuthOnboardingStore? = nil) -> OnboardingV3Coordinator {
        OnboardingV3Coordinator(store: store ?? makeStore(), startingAt: step, now: everyTapAfterTheTransition())
    }

    private func workout(daysAgo: Double, steps: Int?, minutes: Double = 40) -> HealthWorkoutSnapshot {
        let start = Date().addingTimeInterval(-daysAgo * 86_400)
        return HealthWorkoutSnapshot(
            uuid: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(minutes * 60),
            duration: minutes * 60,
            steps: steps
        )
    }

    // MARK: - 06 and its two exits

    @Test
    func connectGoesToTheTwoTapsScreenAndTheNoGoesToTheUsualClimbQuestion() {
        let connect = coordinator(at: .healthConnect)
        connect.advance()
        #expect(connect.step == .healthPermission)

        let decline = coordinator(at: .healthConnect)
        OnboardingHealthConnectScreen.declineHealth(decline)
        #expect(decline.step == .usualClimb)
        #expect(decline.canGoBack)
    }

    @Test
    func aNoClearsWhateverTheClimberAskedToBringInOnTheWayHere() {
        let store = makeStore()
        store.update { $0.recordFoundHealthHistory(.reportedByEveryWorkout(workoutIDs: ["a", "b"], knownSteps: 6_000)) }
        let flow = coordinator(at: .healthConnect, store: store)

        OnboardingHealthConnectScreen.declineHealth(flow)

        #expect(store.answers().foundHealthWorkoutIDs.isEmpty, "a no is a no")
        #expect(store.answers().foundHealthKnownSteps == nil)
    }

    // MARK: - 06b

    private struct PermissionRig {
        let harness: AppleHealthImportHarness
        let viewModel: OnboardingHealthPermissionViewModel
    }

    private func permissionRig(grants: Bool = true) throws -> PermissionRig {
        let harness = try AppleHealthImportHarness()
        harness.authorization.grantsAuthorization = grants
        if !grants { harness.authorization.lastPermissionErrorMessage = "Health said no." }
        let connect = AppleHealthConnectViewModel(authorization: harness.authorization, importService: harness.service)
        let viewModel = OnboardingHealthPermissionViewModel(connect: connect, reader: harness.reader)
        return PermissionRig(harness: harness, viewModel: viewModel)
    }

    @Test
    func workoutsFoundAfterTheSheetRouteToWeFoundYourClimbs() async throws {
        let rig = try permissionRig()
        rig.harness.addWorkout(daysAgo: 100, steps: 3_000)
        let flow = coordinator(at: .healthPermission)

        await rig.viewModel.gotIt(coordinator: flow)

        #expect(flow.step == .healthHistory)
        #expect(rig.harness.authorization.authorizationRequests == 1, "one request, through the Connect flow's own client")
    }

    @Test
    func noWorkoutsRouteToTheUsualClimbQuestionAndLeaveNothingToImport() async throws {
        let rig = try permissionRig()
        let store = makeStore()
        store.update { $0.foundHealthWorkoutIDs = ["stale"] }
        let flow = coordinator(at: .healthPermission, store: store)

        await rig.viewModel.gotIt(coordinator: flow)

        #expect(flow.step == .usualClimb)
        #expect(store.answers().foundHealthWorkoutIDs.isEmpty)
    }

    @Test
    func aReadThatFailsIsNeverReportedAsAHistory() async throws {
        let rig = try permissionRig()
        rig.harness.addWorkout(daysAgo: 100, steps: 3_000)
        rig.harness.reader.readError = NSError(domain: "HealthKit", code: 5)
        let flow = coordinator(at: .healthPermission)

        await rig.viewModel.gotIt(coordinator: flow)

        #expect(flow.step == .usualClimb)
    }

    /// 06b only asks whether there is a history. Counting its steps is 07a's job, and doing it
    /// twice would be a few hundred Health reads for an answer of yes or no.
    @Test
    func theTwoTapsScreenAsksOnlyWhetherThereIsAHistoryAndReadsNoSteps() async throws {
        let rig = try permissionRig()
        rig.harness.addWorkout(daysAgo: 100, steps: nil, windowSteps: 3_000)
        let flow = coordinator(at: .healthPermission)

        await rig.viewModel.gotIt(coordinator: flow)

        #expect(flow.step == .healthHistory)
        #expect(rig.harness.reader.windowReads.isEmpty)
    }

    @Test
    func aRefusedRequestStaysOnTheScreenWithTheMessageAndReadsNothing() async throws {
        let rig = try permissionRig(grants: false)
        rig.harness.addWorkout(daysAgo: 100, steps: 3_000)
        let flow = coordinator(at: .healthPermission)

        await rig.viewModel.gotIt(coordinator: flow)

        #expect(flow.step == .healthPermission)
        #expect(rig.viewModel.errorMessage == "Health said no.")
        #expect(rig.harness.reader.changeReads.isEmpty, "no read without the access it asked for")
        #expect(!rig.viewModel.isWorking, "the button comes back so the climber can try again")
    }

    @Test
    func theAskIsReadOnlyAndFilesNothingBeforeThereIsAnAccount() async throws {
        let rig = try permissionRig()
        rig.harness.userID = nil
        rig.harness.addWorkout(daysAgo: 100, steps: 3_000)
        let flow = coordinator(at: .healthPermission)

        await rig.viewModel.gotIt(coordinator: flow)

        #expect(try rig.harness.records().isEmpty, "the ledger is an account's record")
        #expect(try rig.harness.climbs().isEmpty)
        #expect(rig.harness.settings.anchorData(for: AppleHealthImportHarness.userID) == nil)
        let read = try #require(rig.harness.reader.changeReads.first)
        #expect(read.anchor == nil, "a look, not a pass")
        #expect(read.earliest == .distantPast, "no join-date floor: the history the pass would never reach")
    }

    @Test
    func theConnectFlowsOwnAskStillDiscoversAfterTheSheet() async throws {
        // The later flow (Climb sheet, Settings) is unchanged by onboarding's split.
        let harness = try AppleHealthImportHarness()
        harness.addWorkout(daysAgo: 2, steps: 3_000)
        let connect = AppleHealthConnectViewModel(authorization: harness.authorization, importService: harness.service)

        await connect.requestAccess()

        #expect(connect.step == .choose)
        #expect(connect.foundCount == 1)
    }

    // MARK: - 07a

    /// The events a history screen reported, so a test reads them without the app's telemetry.
    private final class Tracked {
        var records: [TelemetryRecord] = []
    }

    private func historyViewModel(
        _ reader: FakeHealthWorkoutReader,
        climbs: [Climb] = [],
        tracked: Tracked = Tracked()
    ) -> OnboardingHealthHistoryViewModel {
        OnboardingHealthHistoryViewModel(
            reader: reader,
            skipReporter: RecordingHealthWorkoutSkipReporter(),
            loadClimbs: { climbs },
            track: { tracked.records.append($0.record) }
        )
    }

    private func choice(_ viewModel: OnboardingHealthHistoryViewModel) throws -> HealthHistoryChoice {
        guard case .found(let choice) = viewModel.state else {
            throw HealthHistoryNotFound()
        }
        return choice
    }

    private struct HealthHistoryNotFound: Error {}

    @Test
    func addToMyHistoryLeavesTheFoundWorkoutsAndTheUsualClimbOnTheDeviceAndMovesOn() async throws {
        let reader = FakeHealthWorkoutReader()
        let first = workout(daysAgo: 100, steps: 3_000, minutes: 40)
        let second = workout(daysAgo: 120, steps: 5_000, minutes: 50)
        reader.workouts = [first, second]
        let store = makeStore()
        let flow = coordinator(at: .healthHistory, store: store)
        let viewModel = historyViewModel(reader)

        await viewModel.load(coordinator: flow)
        #expect(flow.step == .healthHistory, "found workouts keep the screen")
        viewModel.addToHistory(coordinator: flow)

        let answers = store.answers()
        #expect(Set(answers.foundHealthWorkoutIDs) == [first.uuid.uuidString, second.uuid.uuidString])
        #expect(answers.foundHealthKnownSteps == 8_000, "the sign-in screen says the total back")
        #expect(answers.usualClimbSteps == 4_000)
        #expect(answers.usualClimbMinutes == 45)
        #expect(flow.step == .profileSetup)
    }

    @Test
    func usualMinutesAreKeptAndStepsLeftEmptyWhenNoWorkoutReportedAny() async throws {
        let reader = FakeHealthWorkoutReader()
        reader.workouts = [workout(daysAgo: 3, steps: nil, minutes: 41)]
        let store = makeStore()
        store.update { $0.usualClimbSteps = 9_999 }
        let flow = coordinator(at: .healthHistory, store: store)
        let viewModel = historyViewModel(reader)

        await viewModel.load(coordinator: flow)
        viewModel.addToHistory(coordinator: flow)

        #expect(store.answers().usualClimbSteps == nil)
        #expect(store.answers().usualClimbMinutes == 41)
        #expect(store.answers().foundHealthKnownSteps == nil)
    }

    @Test
    func theSignInRowLeavesOutAStepsTotalOnlyAMinorityOfTheWorkoutsReported() async throws {
        let reader = FakeHealthWorkoutReader()
        reader.workouts = [
            workout(daysAgo: 100, steps: 3_000),
            workout(daysAgo: 110, steps: nil),
            workout(daysAgo: 120, steps: nil)
        ]
        let store = makeStore()
        let flow = coordinator(at: .healthHistory, store: store)
        let viewModel = historyViewModel(reader)

        await viewModel.load(coordinator: flow)
        viewModel.addToHistory(coordinator: flow)

        let answers = store.answers()
        #expect(answers.foundHealthWorkoutIDs.count == 3, "every workout still imports")
        #expect(answers.foundHealthKnownSteps == nil)
        let history = OnboardingSavedItems.make(from: answers).first { $0.kind == .healthHistory }
        #expect(history?.title == "3 past climbs")
    }

    @Test
    func noWorkoutsHandsTheClimberToTheUsualClimbQuestionAndLeavesNothingToImport() async {
        let reader = FakeHealthWorkoutReader()
        let store = makeStore()
        store.update { $0.foundHealthWorkoutIDs = ["stale"] }
        let flow = coordinator(at: .healthHistory, store: store)
        let viewModel = historyViewModel(reader)

        await viewModel.load(coordinator: flow)

        #expect(flow.step == .usualClimb)
        #expect(store.answers().foundHealthWorkoutIDs.isEmpty)
    }

    @Test
    func theButtonDoesNothingUntilTheReadHasFoundSomething() {
        let store = makeStore()
        let flow = coordinator(at: .healthHistory, store: store)
        let viewModel = historyViewModel(FakeHealthWorkoutReader())

        viewModel.addToHistory(coordinator: flow)

        #expect(flow.step == .healthHistory)
        #expect(store.answers().foundHealthWorkoutIDs.isEmpty)
    }

    @Test
    func theComparisonReadsOnlyTheStepsHealthReported() async throws {
        let reader = FakeHealthWorkoutReader()
        // Twenty 20-hour workouts of 30,000 steps each (25 a minute): 600,000 in all.
        reader.workouts = (0..<20).map { workout(daysAgo: Double(10 + $0), steps: 30_000, minutes: 1_200) }
            + [workout(daysAgo: 40, steps: nil, minutes: 40)]
        let viewModel = historyViewModel(reader)

        await viewModel.load(coordinator: coordinator(at: .healthHistory))

        #expect(try choice(viewModel).comparison?.timesOver == 12, "600,000 over 48,664, floored")
    }

    // MARK: - 07a's one choice

    @Test
    func theRangeStartsAtEverythingAndTheButtonCountsEveryWorkout() async throws {
        let reader = FakeHealthWorkoutReader()
        reader.workouts = [workout(daysAgo: 10, steps: 3_000), workout(daysAgo: 200, steps: 3_000), workout(daysAgo: 500, steps: 3_000)]
        let viewModel = historyViewModel(reader)

        await viewModel.load(coordinator: coordinator(at: .healthHistory))

        let choice = try choice(viewModel)
        #expect(choice.range == .everything)
        #expect(choice.primaryTitle == "Add 3 to my history")
        #expect(choice.rangeLabel.hasPrefix("Everything since "), "\(choice.rangeLabel)")
    }

    @Test
    func aNarrowerRangeLeavesOnlyTheWorkoutsInsideItForTheImportAndSaysSoEverywhere() async throws {
        let reader = FakeHealthWorkoutReader()
        let recent = workout(daysAgo: 10, steps: 3_000, minutes: 40)
        let lastSpring = workout(daysAgo: 200, steps: 5_000, minutes: 50)
        let old = workout(daysAgo: 500, steps: 9_000, minutes: 60)
        reader.workouts = [recent, lastSpring, old]
        let store = makeStore()
        let flow = coordinator(at: .healthHistory, store: store)
        let tracked = Tracked()
        let viewModel = historyViewModel(reader, tracked: tracked)
        await viewModel.load(coordinator: flow)
        let choice = try choice(viewModel)

        choice.select(.lastYear)
        #expect(choice.summary.workoutCount == 2)
        #expect(choice.summary.knownSteps == 8_000, "the step total follows the range")
        #expect(choice.summary.totalDurationText == "2 hours", "and so do the hours")
        #expect(choice.primaryTitle == "Add 2 to my history")
        #expect(choice.rangeLabel == "Last year")

        choice.select(.last90Days)
        #expect(choice.primaryTitle == "Add 1 to my history")
        viewModel.addToHistory(coordinator: flow)

        let answers = store.answers()
        #expect(answers.foundHealthWorkoutIDs == [recent.uuid.uuidString], "only what is inside the range imports")
        #expect(answers.foundHealthKnownSteps == 3_000)
        #expect(flow.step == .profileSetup)

        let event = try #require(tracked.records.first)
        #expect(tracked.records.count == 1)
        #expect(event.name == "onboarding_question_answered")
        #expect(event.parameters["question_id"] == .string("health_history"))
        #expect(event.parameters["answer_id"] == .string("last_90_days"))
        #expect(event.parameters["workouts_added"] == .int(1))
        #expect(event.parameters["workouts_found"] == .int(3))
        #expect(event.parameters["flow_version"] == .string("v3"))
        #expect(event.parameters["step_id"] == .string("health_history"))
    }

    @Test
    func aPickedDayImportsFromTheStartOfThatDayAndNeverReportsTheDay() async throws {
        let reader = FakeHealthWorkoutReader()
        let inside = workout(daysAgo: 30, steps: 3_000)
        let outside = workout(daysAgo: 60, steps: 3_000)
        reader.workouts = [inside, outside]
        let store = makeStore()
        let flow = coordinator(at: .healthHistory, store: store)
        let tracked = Tracked()
        let viewModel = historyViewModel(reader, tracked: tracked)
        await viewModel.load(coordinator: flow)
        let choice = try choice(viewModel)

        // Later the same day than the workout began: the range still starts at that day's midnight.
        choice.select(.since(inside.startDate.addingTimeInterval(60)))
        viewModel.addToHistory(coordinator: flow)

        #expect(store.answers().foundHealthWorkoutIDs == [inside.uuid.uuidString])
        #expect(choice.rangeLabel.hasPrefix("Since "), "\(choice.rangeLabel)")
        #expect(tracked.records.first?.parameters["answer_id"] == .string("since_date"))
    }

    @Test
    func skippingHistoryLeavesNothingToImportKeepsTheUsualClimbAndMovesOn() async throws {
        let reader = FakeHealthWorkoutReader()
        reader.workouts = [workout(daysAgo: 100, steps: 3_000, minutes: 40), workout(daysAgo: 120, steps: 5_000, minutes: 50)]
        let store = makeStore()
        store.update {
            $0.foundHealthWorkoutIDs = ["from-an-earlier-pass-through-this-screen"]
            $0.foundHealthKnownSteps = 12
        }
        let flow = coordinator(at: .healthHistory, store: store)
        let tracked = Tracked()
        let viewModel = historyViewModel(reader, tracked: tracked)
        await viewModel.load(coordinator: flow)

        viewModel.skipHistory(coordinator: flow)

        let answers = store.answers()
        #expect(answers.foundHealthWorkoutIDs.isEmpty, "nothing is left for the sign-in hand-off to import")
        #expect(answers.foundHealthKnownSteps == nil)
        #expect(answers.usualClimbSteps == 4_000, "the usual climb the screen showed still speaks for the climber")
        #expect(answers.usualClimbMinutes == 45)
        #expect(flow.step == .profileSetup, "Health stays connected and the flow moves on")
        #expect(OnboardingSavedItems.make(from: answers).contains { $0.kind == .healthHistory } == false)

        let event = try #require(tracked.records.first)
        #expect(tracked.records.count == 1)
        #expect(event.parameters["question_id"] == .string("health_history"))
        #expect(event.parameters["answer_id"] == .string("skip_history"))
        #expect(event.parameters["workouts_added"] == .int(0))
        #expect(event.parameters["workouts_found"] == .int(2))
    }

    @Test
    func aSkippedHistoryGivesTheHandOffNothingToRun() async throws {
        let harness = try AppleHealthImportHarness()
        harness.addWorkout(daysAgo: 100, steps: 3_000)
        let store = makeStore()
        let flow = coordinator(at: .healthHistory, store: store)
        let viewModel = historyViewModel(harness.reader)
        await viewModel.load(coordinator: flow)
        viewModel.skipHistory(coordinator: flow)

        let landed = await OnboardingHealthHistoryImport.run(store.answers(), service: harness.service)

        #expect(landed, "nothing to bring in is done")
        #expect(try harness.climbs().isEmpty)
        #expect(harness.settings.isAutoImportEnabled(for: AppleHealthImportHarness.userID), "new workouts still import on their own")
    }

    @Test
    func skipDoesNothingUntilTheReadHasFoundSomething() {
        let store = makeStore()
        store.update { $0.foundHealthWorkoutIDs = ["kept"] }
        let flow = coordinator(at: .healthHistory, store: store)
        let viewModel = historyViewModel(FakeHealthWorkoutReader())

        viewModel.skipHistory(coordinator: flow)

        #expect(flow.step == .healthHistory)
        #expect(store.answers().foundHealthWorkoutIDs == ["kept"])
    }

    @Test
    func theHistoryTotalsCountTheStepsHealthHoldsOverAWorkoutsWindow() async throws {
        let reader = FakeHealthWorkoutReader()
        let carried = workout(daysAgo: 100, steps: 3_000, minutes: 40)
        let windowOnly = workout(daysAgo: 120, steps: nil, minutes: 50)
        let neither = workout(daysAgo: 140, steps: nil, minutes: 30)
        reader.workouts = [carried, windowOnly, neither]
        reader.windowSteps[windowOnly.startDate] = 5_000
        let store = makeStore()
        let flow = coordinator(at: .healthHistory, store: store)
        let viewModel = historyViewModel(reader)

        await viewModel.load(coordinator: flow)
        let summary = try choice(viewModel).summary

        #expect(summary.knownSteps == 8_000, "the screen's total is the total the import lands")
        #expect(summary.workoutsWithSteps == 2)
        #expect(summary.workoutCount == 3)
        #expect(reader.windowReads.count == 2, "only the workouts with no steps of their own are looked up")
    }

    @Test
    func theWholeBranchWalksFromConnectToTheClimberCard() async throws {
        let rig = try permissionRig()
        let first = rig.harness.addWorkout(daysAgo: 100, steps: 3_000)
        let store = makeStore()
        let flow = coordinator(at: .healthConnect, store: store)

        flow.advance()
        await rig.viewModel.gotIt(coordinator: flow)
        #expect(flow.step == .healthHistory)

        let history = historyViewModel(rig.harness.reader)
        await history.load(coordinator: flow)
        history.addToHistory(coordinator: flow)

        #expect(flow.step == .profileSetup)
        #expect(store.answers().foundHealthWorkoutIDs == [first.uuid.uuidString])
        #expect(OnboardingV3Step.healthConnect.primaryDestination == .healthPermission)
        #expect(OnboardingV3Step.healthHistory.primaryDestination == .profileSetup)
    }

    // MARK: - The hand-off

    @Test
    func theHandOffImportsExactlyTheWorkoutsTheClimberWasShownAndReportsThatTheyLanded() async throws {
        let harness = try AppleHealthImportHarness()
        let shown = harness.addWorkout(daysAgo: 100, steps: 3_000)
        harness.addWorkout(daysAgo: 120, steps: 5_000)
        var answers = PreAuthOnboardingAnswers()
        answers.foundHealthWorkoutIDs = [shown.uuid.uuidString]

        let landed = await OnboardingHealthHistoryImport.run(
            answers,
            service: harness.service
        )

        #expect(landed)
        #expect(try harness.climbs().map(\.healthKitUUID) == [shown.uuid.uuidString])
    }

    @Test
    func theHandOffDoesNothingWithoutTheClimbersYes() async throws {
        let harness = try AppleHealthImportHarness()
        harness.addWorkout(daysAgo: 100, steps: 3_000)

        let landed = await OnboardingHealthHistoryImport.run(
            PreAuthOnboardingAnswers(),
            service: harness.service
        )

        #expect(landed, "nothing to bring in is nothing outstanding")
        #expect(try harness.climbs().isEmpty)
        #expect(harness.reader.changeReads.isEmpty)
    }

    @Test
    func theHandOffKeepsTheWorkoutsWhenTheImportIsDeferred() async throws {
        let harness = try AppleHealthImportHarness()
        let shown = harness.addWorkout(daysAgo: 100, steps: 3_000)
        harness.userID = nil
        var answers = PreAuthOnboardingAnswers()
        answers.foundHealthWorkoutIDs = [shown.uuid.uuidString]

        let signedOut = await OnboardingHealthHistoryImport.run(
            answers,
            service: harness.service
        )

        #expect(!signedOut)
        #expect(try harness.climbs().isEmpty)
    }

    @Test
    func aHistoryImportDeferredAtSignInLandsWhenTheCloudRestoreConfirms() async throws {
        let harness = try AppleHealthImportHarness()
        let shown = harness.addWorkout(daysAgo: 100, steps: 3_000)
        let service = harness.relaunchedServiceWithoutCloudRestore()
        let store = makeStore()
        store.update { $0.foundHealthWorkoutIDs = [shown.uuid.uuidString] }
        let suite = "onboarding-v3-health-intent-\(UUID().uuidString)"
        let handOff = OnboardingV3SignInHandOff(
            seams: .init(
                isProfileWriteEnabled: { true },
                signInNameSettled: {},
                readProfile: { _ in nil },
                writeProfile: { _, _, _ in },
                recordProfileStepFailure: { _ in },
                importHealthHistory: { await OnboardingHealthHistoryImport.run($0, service: service) },
                markPostSignInOnboardingComplete: {},
                deviceWeeklyTarget: { _ in nil },
                saveWeeklyTarget: { _, _ in },
                reconcileWeeklyTarget: { _ in }
            ),
            store: store,
            intent: OnboardingV3HandOffIntent(userDefaults: UserDefaults(suiteName: suite)!)
        )

        await handOff.runAfterSignIn(userId: AppleHealthImportHarness.userID, email: nil)

        #expect(try harness.climbs().isEmpty, "the sign-in arrives before the restore")
        #expect(store.answers().foundHealthWorkoutIDs == [shown.uuid.uuidString])

        service.confirmCloudClimbsRestored(for: AppleHealthImportHarness.userID)
        await handOff.retryPendingAnswers(userId: AppleHealthImportHarness.userID, email: nil)

        #expect(try harness.climbs().map(\.healthKitUUID) == [shown.uuid.uuidString])
        #expect(store.answers().foundHealthWorkoutIDs.isEmpty)
    }

    // MARK: - Progress

    @Test
    func theBarHoldsAtEightyOneThroughTheTwoTapsScreenAndMovesToEightySixOnTheHistory() {
        #expect(OnboardingProgressTable.value(for: .healthConnect) == 81)
        #expect(OnboardingProgressTable.value(for: .healthPermission) == 81)
        #expect(OnboardingProgressTable.value(for: .healthHistory) == 86)
    }

    // MARK: - Copy

    @Test
    func noHealthCopyBreaksTheWordingRules() {
        let copy = [
            "Your workouts,", "counted for you.", "Skip", "You can always connect this in Settings.",
            "Two taps and", "you're set.", "Tap Turn On All", "Tap Allow at the bottom",
            "We found your climbs", "Add 214 to my history", OnboardingHealthHistoryScreen.footnote,
            OnboardingHealthHistoryScreen.skipTitle, OnboardingHealthHistoryScreen.primaryPlaceholder,
            "How far back?", "Add the rest any time in Integrations.", "Everything", "Last year", "Last 90 days", "Since",
            AppleHealthOlderWorkoutsView.footnote, AppleHealthOlderWorkoutsView.nothingTitle,
            AppleHealthOlderWorkoutsView.nothingDetail, AppleHealthOlderWorkoutsView.unavailableTitle,
            AppleHealthOlderWorkoutsView.unavailableDetail, AppleHealthOlderWorkoutsViewModel.importFailedMessage,
            "Import automatically", AppleHealthManageSheet.autoImportDetail,
            "Import older workouts", AppleHealthManageSheet.olderWorkoutsDetail,
            HealthPermissionSheetMock.accessibilityDescription
        ] + HealthPermissionSheetMock.categories

        for line in copy.map({ $0.lowercased() }) {
            #expect(!line.contains("race"), "\(line)")
            #expect(!line.contains("live"), "\(line)")
            #expect(!line.contains("field"), "\(line)")
            #expect(!line.contains("\u{2014}"), "no em dash: \(line)")
        }
    }

    @Test
    func theMockListsExactlyTheTypesTheRealRequestAsksFor() {
        // HealthKitAuthorizationClient.readTypes is workouts, steps, heart rate and active energy,
        // so the picture of Apple's sheet has those four rows and no Flights Climbed.
        #expect(Set(HealthPermissionSheetMock.categories) == ["Workouts", "Steps", "Heart Rate", "Active Energy"])
        #expect(HealthKitAuthorizationClient.shared.readTypes.count == HealthPermissionSheetMock.categories.count)
        #expect(!HealthPermissionSheetMock.accessibilityDescription.lowercased().contains("update"), "Ascend only reads")
    }
}
