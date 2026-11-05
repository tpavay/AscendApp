import FirebaseFirestore
import Foundation
import Testing
import UIKit
@testable import AscendApp

/// Screen 15 and what happens when the climber signs in at the end of the flow: the example board,
/// the two modes, the profile fill, and every route's hand-off.
@MainActor
struct OnboardingAuthTests {
    private static let now = Date(timeIntervalSince1970: 1_793_793_600) // Wed 2026-11-04 12:00 UTC

    private func defaults() -> UserDefaults {
        let suite = "onboarding-auth-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: - The example board

    @Test
    func theBoardIsThreeFixedExampleClimbersInOrder() {
        let climbers = OnboardingAuthExampleClimber.weeklyTopThree

        #expect(climbers.map(\.rank) == [1, 2, 3])
        #expect(climbers.map(\.name) == ["Maya D.", "Noah R.", "Ava M."])
        #expect(climbers.map(\.steps) == ["38,891", "12,335", "9,720"])
    }

    @Test
    func everyExampleClimberHasAnAvatarTheAppAlreadyShips() {
        for climber in OnboardingAuthExampleClimber.weeklyTopThree {
            #expect(UIImage(named: climber.avatarImageName) != nil, "\(climber.avatarImageName)")
        }
    }

    // MARK: - Modes

    @Test
    func theSignInOpensInReturningModeFromTheFirstScreenAndTheClaimSpotModeFromThePaywall() {
        let request = OnboardingAuthReturningRequest(userDefaults: defaults())

        #expect(OnboardingAuthMode(arrivedFrom: .welcome, returningRequest: request) == .returning)
        #expect(OnboardingAuthMode(arrivedFrom: .paywall, returningRequest: request) == .claimSpot)
        #expect(OnboardingAuthMode(arrivedFrom: .exitGift, returningRequest: request) == .claimSpot)
        #expect(OnboardingAuthMode(arrivedFrom: nil, returningRequest: request) == .claimSpot)
    }

    @Test
    func aReturningRequestFromThePaywallWinsOverTheStepItCameFrom() {
        let request = OnboardingAuthReturningRequest(userDefaults: defaults())
        request.set()

        #expect(OnboardingAuthMode(arrivedFrom: .paywall, returningRequest: request) == .returning)

        request.clear()
        #expect(OnboardingAuthMode(arrivedFrom: .paywall, returningRequest: request) == .claimSpot)
    }

    // MARK: - Profile fill

    private func fullAnswers() -> PreAuthOnboardingAnswers {
        var answers = PreAuthOnboardingAnswers()
        answers.gender = .woman
        answers.birthday = PreAuthOnboardingBirthday(year: 1992, month: 3, day: 9)
        answers.heightCm = 170
        answers.weightKg = 64
        answers.city = PreAuthOnboardingCity(city: "Denver", region: "CO", countryCode: "US", countryName: "United States")
        return answers
    }

    @Test
    func everyAnswerFillsABlankProfile() {
        let fill = OnboardingProfileFill.plan(answers: fullAnswers(), existing: nil, now: Self.now)

        #expect(fill.gender == .woman)
        #expect(fill.birthday?.rawValue == "1992-03-09")
        #expect(fill.heightCm == 170)
        #expect(fill.weightKg == 64)
        #expect(fill.city?.city == "Denver")
    }

    @Test
    func anAccountThatAlreadyHasAValueKeepsIt() {
        let existing = UserDisplayNameData([
            "birth_date": "1980-01-01",
            "gender": "man",
            "weight_kg": 90.0,
            "height_cm": 185.0,
            "location_city": "Austin",
            "location_country": "US"
        ])

        let fill = OnboardingProfileFill.plan(answers: fullAnswers(), existing: existing, now: Self.now)
        #expect(fill.isEmpty)
    }

    @Test
    func aLegacyAgeCountsAsABirthdayAlreadyOnTheProfile() {
        let existing = UserDisplayNameData(["age": 41])
        let fill = OnboardingProfileFill.plan(answers: fullAnswers(), existing: existing, now: Self.now)

        #expect(fill.birthday == nil)
        #expect(fill.gender == .woman)
    }

    @Test
    func aValueTheRulesWouldRefuseIsNeverWritten() {
        var answers = fullAnswers()
        answers.birthday = PreAuthOnboardingBirthday(year: 2020, month: 1, day: 1)
        answers.weightKg = 500
        answers.heightCm = 60
        answers.city = PreAuthOnboardingCity(city: " ", region: nil, countryCode: "US", countryName: "United States")

        let fill = OnboardingProfileFill.plan(answers: answers, existing: nil, now: Self.now)
        #expect(fill.birthday == nil)
        #expect(fill.weightKg == nil)
        #expect(fill.heightCm == nil)
        #expect(fill.city == nil)
        #expect(fill.gender == .woman)
    }

    private func plannedCity(
        city: String = "Denver",
        region: String?,
        countryCode: String = "US"
    ) -> PreAuthOnboardingCity? {
        var answers = PreAuthOnboardingAnswers()
        answers.city = PreAuthOnboardingCity(city: city, region: region, countryCode: countryCode, countryName: "Anywhere")
        return OnboardingProfileFill.plan(answers: answers, existing: nil, now: Self.now).city
    }

    @Test(arguments: ["", "  ", String(repeating: "r", count: 121)])
    func aRegionTheRulesWouldRefuseIsLeftOffAndTheCityStays(region: String) {
        let city = plannedCity(region: region)

        #expect(city?.city == "Denver")
        #expect(city?.region == nil)
    }

    @Test
    func aRegionAtTheRulesLimitIsKept() {
        let longest = String(repeating: "r", count: 120)

        #expect(plannedCity(region: longest)?.region == longest)
        #expect(plannedCity(region: nil)?.region == nil)
    }

    @Test
    func theCityIsMeasuredAsItWillBeWritten() {
        let city = plannedCity(city: "  Denver \n", region: " CO ", countryCode: " us ")

        #expect(city?.city == "Denver")
        #expect(city?.region == "CO")
        #expect(city?.countryCode == "US")
        #expect(plannedCity(city: String(repeating: "c", count: 121), region: nil) == nil)
    }

    @Test(arguments: ["", "U", "USA", "1A", "U."])
    func aCountryTheRulesWouldRefuseKeepsTheWholeCityOffTheProfile(countryCode: String) {
        #expect(plannedCity(region: "CO", countryCode: countryCode) == nil)
    }

    // MARK: - Hand-off routes

    /// A recording stand-in for every seam, in the order they are reached.
    @MainActor
    private final class Recorder {
        var events: [String] = []
        var profile: UserDisplayNameData? = UserDisplayNameData(nil)
        var writeFails = false
        var readFails = false
        var failure: any Error = Refused()
        var reportedFailures = 0
        var profileWriteEnabled = true
        var writtenFills: [OnboardingProfileFill] = []
        var importedAnswers: [PreAuthOnboardingAnswers] = []
        /// The target the account holds, which `readWeeklyTarget` answers with.
        var accountTarget: Int?
        var reconciledReminders: [Int?] = []
        var savedTargets: [Int] = []

        struct Refused: Error {}

        func seams() -> OnboardingV3SignInHandOff.Seams {
            .init(
                completePurchaseTransfer: { [self] in events.append("transfer") },
                clearPurchaseLedger: { [self] in events.append("clearLedger") },
                isProfileWriteEnabled: { [self] in profileWriteEnabled },
                readProfile: { [self] _ in
                    events.append("read")
                    if readFails { throw failure }
                    return profile
                },
                writeProfile: { [self] _, _, fill in
                    events.append("write")
                    if writeFails { throw failure }
                    writtenFills.append(fill)
                },
                recordProfileStepFailure: { [self] _ in reportedFailures += 1 },
                importHealthHistory: { [self] answers in
                    events.append("health")
                    importedAnswers.append(answers)
                },
                markPostSignInOnboardingComplete: { [self] in events.append("markComplete") },
                saveWeeklyTarget: { [self] _, days in
                    events.append("saveTarget")
                    savedTargets.append(days)
                    accountTarget = days
                },
                readWeeklyTarget: { [self] _ in
                    events.append("readTarget")
                    return accountTarget
                },
                reconcileWeeklyReminder: { [self] days in
                    events.append("reminder")
                    reconciledReminders.append(days)
                }
            )
        }
    }

    private struct Harness {
        let store: PreAuthOnboardingStore
        let intent: OnboardingV3HandOffIntent
        let recorder = Recorder()
        let handOff: OnboardingV3SignInHandOff

        @MainActor
        init(defaults: UserDefaults, answers: PreAuthOnboardingAnswers) {
            store = PreAuthOnboardingStore(userDefaults: defaults)
            intent = OnboardingV3HandOffIntent(userDefaults: defaults)
            store.save(answers)
            handOff = OnboardingV3SignInHandOff(seams: recorder.seams(), store: store, intent: intent)
        }
    }

    @Test
    func purchaseThenSignInClosesTheFlowMovesThePurchaseWritesTheAnswersAndClearsTheLedger() async {
        var answers = fullAnswers()
        answers.completedAt = Self.now
        let harness = Harness(defaults: defaults(), answers: answers)
        harness.intent.set()

        let outcome = await harness.handOff.runAfterSignIn(userId: "u1", email: nil)

        #expect(outcome == .complete)
        // The flow closes first, so the route never shows the old questions while the purchase moves.
        #expect(harness.recorder.events == [
            "markComplete", "transfer", "clearLedger", "read", "write", "health", "readTarget", "reminder"
        ])
        #expect(harness.recorder.writtenFills.count == 1)
        #expect(!harness.store.answers().carriesHandOffWork)
        #expect(harness.store.answers().completedAt == Self.now, "the flow stays finished")
        #expect(!harness.intent.isSet)
    }

    @Test
    func theGiftPathIsTheSameRouteOut() async {
        // The gift's CLAIM goes straight to sign-in with a purchase in the ledger: same intent, same hand-off.
        var answers = fullAnswers()
        answers.completedAt = Self.now
        let harness = Harness(defaults: defaults(), answers: answers)
        harness.intent.set()

        await harness.handOff.runAfterSignIn(userId: "u1", email: nil)

        #expect(harness.recorder.events.prefix(3) == ["markComplete", "transfer", "clearLedger"])
    }

    @Test
    func returningModeMovesTheStoredPurchaseButNeverClosesPostSignInOnboarding() async {
        let harness = Harness(defaults: defaults(), answers: PreAuthOnboardingAnswers())
        // No intent: returning mode never sets one.

        let outcome = await harness.handOff.runAfterSignIn(userId: "u1", email: nil)

        #expect(outcome == .complete)
        #expect(harness.recorder.events == ["transfer", "clearLedger", "readTarget", "reminder"])
    }

    @Test
    func everyRouteCallsTheTransferAndClearsTheLedgerAfterIt() async {
        for intended in [true, false] {
            let harness = Harness(defaults: defaults(), answers: PreAuthOnboardingAnswers())
            if intended { harness.intent.set() }

            await harness.handOff.runAfterSignIn(userId: "u1", email: nil)

            let events = harness.recorder.events
            let transfer = events.firstIndex(of: "transfer")
            let cleared = events.firstIndex(of: "clearLedger")
            #expect(transfer != nil && cleared != nil && transfer! < cleared!)
        }
    }

    @Test
    func theSwitchOffKeepsTheAnswersOnTheDeviceAndTheNextRunWritesThem() async {
        var answers = fullAnswers()
        answers.completedAt = Self.now
        let harness = Harness(defaults: defaults(), answers: answers)
        harness.recorder.profileWriteEnabled = false

        let first = await harness.handOff.runAfterSignIn(userId: "u1", email: nil)
        #expect(first == .deferred)
        #expect(!harness.recorder.events.contains("write"))
        #expect(harness.store.answers().carriesHandOffWork)

        harness.recorder.profileWriteEnabled = true
        let retry = await harness.handOff.retryPendingAnswers(userId: "u1", email: nil)
        #expect(retry == .complete)
        #expect(harness.recorder.writtenFills.count == 1)
        #expect(!harness.store.answers().carriesHandOffWork)
    }

    @Test
    func aRefusedWriteLeavesTheAnswersAndTheHealthImportForTheNextRun() async {
        let harness = Harness(defaults: defaults(), answers: fullAnswers())
        harness.recorder.writeFails = true

        let outcome = await harness.handOff.retryPendingAnswers(userId: "u1", email: nil)

        #expect(outcome == .deferred)
        #expect(!harness.recorder.events.contains("health"))
        #expect(harness.store.answers().carriesHandOffWork)

        harness.recorder.writeFails = false
        #expect(await harness.handOff.retryPendingAnswers(userId: "u1", email: nil) == .complete)
        #expect(harness.recorder.events.filter { $0 == "health" }.count == 1)
    }

    @Test
    func anUnreadableProfileNeverGetsAGuessWrittenOverIt() async {
        let harness = Harness(defaults: defaults(), answers: fullAnswers())
        harness.recorder.readFails = true

        #expect(await harness.handOff.retryPendingAnswers(userId: "u1", email: nil) == .deferred)
        #expect(!harness.recorder.events.contains("write"))
    }

    @Test
    func aFailureNoRetryWillClearIsReportedAndTheAnswersAreHeld() async {
        let denied = NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.permissionDenied.rawValue)
        for failsOnRead in [true, false] {
            let harness = Harness(defaults: defaults(), answers: fullAnswers())
            harness.recorder.failure = denied
            harness.recorder.readFails = failsOnRead
            harness.recorder.writeFails = !failsOnRead

            #expect(await harness.handOff.retryPendingAnswers(userId: "u1", email: nil) == .deferred)
            #expect(harness.recorder.reportedFailures == 1)
            #expect(harness.store.answers().carriesHandOffWork)
        }
    }

    @Test(arguments: [
        ProfilePublicationError.requiresConnection,
        ProfilePublicationError.publishingPaused,
        NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.unavailable.rawValue),
        URLError(.notConnectedToInternet)
    ] as [any Error])
    func aFailureThatClearsOnItsOwnStaysQuietAndTheAnswersAreHeld(failure: any Error) async {
        let harness = Harness(defaults: defaults(), answers: fullAnswers())
        harness.recorder.failure = failure
        harness.recorder.writeFails = true

        #expect(await harness.handOff.retryPendingAnswers(userId: "u1", email: nil) == .deferred)
        #expect(harness.recorder.reportedFailures == 0)
        #expect(harness.store.answers().carriesHandOffWork)
    }

    @Test
    func theUsualClimbLeavesTheDeviceWithTheOtherAnswers() async {
        var answers = fullAnswers()
        answers.usualClimbSteps = 1_800
        answers.usualClimbMinutes = 22
        let harness = Harness(defaults: defaults(), answers: answers)

        #expect(await harness.handOff.retryPendingAnswers(userId: "u1", email: nil) == .complete)
        #expect(harness.store.answers().usualClimbSteps == nil)
        #expect(harness.store.answers().usualClimbMinutes == nil)
    }

    @Test
    func aClimberWhoGaveOnlyAUsualClimbStillHasItCleared() async {
        var answers = PreAuthOnboardingAnswers()
        answers.usualClimbSteps = 1_800
        answers.usualClimbMinutes = 22
        let harness = Harness(defaults: defaults(), answers: answers)

        #expect(harness.store.answers().carriesHandOffWork)
        #expect(await harness.handOff.retryPendingAnswers(userId: "u1", email: nil) == .complete)
        #expect(harness.recorder.writtenFills.isEmpty)
        #expect(harness.store.answers().usualClimbSteps == nil)
        #expect(harness.store.answers().usualClimbMinutes == nil)
    }

    @Test
    func healthHistoryAloneIsStillImportedWhenThereAreNoProfileAnswers() async {
        var answers = PreAuthOnboardingAnswers()
        answers.foundHealthWorkoutIDs = ["w1", "w2"]
        let harness = Harness(defaults: defaults(), answers: answers)

        #expect(await harness.handOff.retryPendingAnswers(userId: "u1", email: nil) == .complete)
        #expect(harness.recorder.events == ["read", "health"])
        #expect(harness.recorder.importedAnswers.first?.foundHealthWorkoutIDs == ["w1", "w2"])
        #expect(harness.store.answers().foundHealthWorkoutIDs.isEmpty)
    }

    @Test
    func anAccountThatAlreadyHasEverythingGetsNoWriteButStillClearsTheAnswers() async {
        let harness = Harness(defaults: defaults(), answers: fullAnswers())
        harness.recorder.profile = UserDisplayNameData([
            "birth_date": "1980-01-01", "gender": "man", "weight_kg": 90.0, "height_cm": 185.0,
            "location_city": "Austin", "location_country": "US"
        ])

        #expect(await harness.handOff.retryPendingAnswers(userId: "u1", email: nil) == .complete)
        #expect(harness.recorder.writtenFills.isEmpty)
        #expect(!harness.store.answers().carriesHandOffWork)
    }

    @Test
    func aSignInWithNothingToCarryDoesNoProfileWork() async {
        let harness = Harness(defaults: defaults(), answers: PreAuthOnboardingAnswers())

        #expect(await harness.handOff.retryPendingAnswers(userId: "u1", email: nil) == .complete)
        #expect(harness.recorder.events.isEmpty)
    }

    // MARK: - Weekly reminder

    @Test
    func theChosenTargetIsSavedToTheAccountAndTheReminderIsSetFromIt() async {
        var answers = PreAuthOnboardingAnswers()
        answers.weeklyTargetDays = 4
        answers.completedAt = Self.now
        let harness = Harness(defaults: defaults(), answers: answers)
        harness.intent.set()

        await harness.handOff.runAfterSignIn(userId: "u1", email: nil)

        #expect(harness.recorder.savedTargets == [4])
        #expect(harness.recorder.reconciledReminders == [4])
        #expect(!harness.store.answers().carriesHandOffWork)
        let events = harness.recorder.events
        #expect(events.firstIndex(of: "saveTarget")! < events.firstIndex(of: "readTarget")!, "the reminder reads what was just saved")
    }

    @Test
    func signingOutAndBackInRestoresTheReminderFromTheAccount() async {
        // The first sign-in saves the target. Sign-out then erases the device's copy and the
        // answers; the second sign-in has nothing to write and must still bring the reminder back.
        var answers = PreAuthOnboardingAnswers()
        answers.weeklyTargetDays = 3
        let harness = Harness(defaults: defaults(), answers: answers)
        await harness.handOff.runAfterSignIn(userId: "u1", email: nil)
        #expect(harness.recorder.reconciledReminders == [3])

        // Sign-out: reminders cleared, answers long gone. The account still holds 3.
        harness.recorder.reconciledReminders.removeAll()
        harness.recorder.events.removeAll()

        await harness.handOff.runAfterSignIn(userId: "u1", email: nil)

        #expect(harness.recorder.reconciledReminders == [3])
        #expect(!harness.recorder.events.contains("saveTarget"), "nothing is re-saved")
    }

    @Test
    func aTargetThatOnlyReachedTheAccountOnARetryStillSetsTheReminder() async {
        var answers = PreAuthOnboardingAnswers()
        answers.weeklyTargetDays = 2
        let harness = Harness(defaults: defaults(), answers: answers)
        harness.recorder.profileWriteEnabled = false

        #expect(await harness.handOff.retryPendingAnswers(userId: "u1", email: nil) == .deferred)
        #expect(harness.recorder.reconciledReminders.isEmpty)

        harness.recorder.profileWriteEnabled = true
        #expect(await harness.handOff.retryPendingAnswers(userId: "u1", email: nil) == .complete)
        #expect(harness.recorder.reconciledReminders == [2])
    }

    @Test
    func aReturningSignInAlsoRestoresTheReminder() async {
        let harness = Harness(defaults: defaults(), answers: PreAuthOnboardingAnswers())
        harness.recorder.accountTarget = 5

        await harness.handOff.runAfterSignIn(userId: "u1", email: nil) // no intent: returning mode

        #expect(harness.recorder.reconciledReminders == [5])
        #expect(!harness.recorder.events.contains("markComplete"))
    }

    @Test
    func anAccountWithNoTargetClearsTheReminderRatherThanLeavingAStaleOne() async {
        let harness = Harness(defaults: defaults(), answers: PreAuthOnboardingAnswers())

        await harness.handOff.runAfterSignIn(userId: "u1", email: nil)

        #expect(harness.recorder.reconciledReminders.count == 1)
        #expect(harness.recorder.reconciledReminders.first! == nil)
    }

    @Test
    func theFlagIsAKillSwitchThatShipsOn() {
        #expect(RemoteFeatureFlag.onboardingAnswersProfileWrite.shippedDefault)
        #expect(RemoteFeatureFlag.onboardingAnswersProfileWrite.key == "onboarding_answers_profile_write_enabled")
    }

    // MARK: - The coordinator hint

    @Test
    func theCoordinatorSaysWhichScreenTheSignInCameFrom() {
        let coordinator = OnboardingV3Coordinator(
            store: PreAuthOnboardingStore(userDefaults: defaults()),
            startingAt: .welcome
        )
        #expect(coordinator.previousStep == nil)

        coordinator.go(to: .auth)
        #expect(coordinator.previousStep == .welcome)
        #expect(OnboardingAuthMode(arrivedFrom: coordinator.previousStep) == .returning)
    }
}
