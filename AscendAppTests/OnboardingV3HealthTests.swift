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
        store.update { $0.foundHealthWorkoutIDs = ["a", "b"] }
        let flow = coordinator(at: .healthConnect, store: store)

        OnboardingHealthConnectScreen.declineHealth(flow)

        #expect(store.answers().foundHealthWorkoutIDs.isEmpty, "a no is a no")
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

    private func historyViewModel(_ reader: FakeHealthWorkoutReader, climbs: [Climb] = []) -> OnboardingHealthHistoryViewModel {
        OnboardingHealthHistoryViewModel(reader: reader, loadClimbs: { climbs })
    }

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
        #expect(answers.usualClimbSteps == 4_000)
        #expect(answers.usualClimbMinutes == 45)
        #expect(flow.step == .climberCard)
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

        #expect(viewModel.comparison?.timesOver == 12, "600,000 over 48,664, floored")
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

        #expect(flow.step == .climberCard)
        #expect(store.answers().foundHealthWorkoutIDs == [first.uuid.uuidString])
        #expect(OnboardingV3Step.healthConnect.primaryDestination == .healthPermission)
        #expect(OnboardingV3Step.healthHistory.primaryDestination == .climberCard)
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
            "We found your climbs", "Add to my history", OnboardingHealthHistoryScreen.footnote,
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
