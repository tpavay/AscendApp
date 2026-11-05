import Foundation
import Testing
@testable import AscendApp

/// Screen 15 and what happens when the climber signs in at the end of the flow: the public weekly
/// board, the two modes, the profile fill, and every route's hand-off.
@MainActor
struct OnboardingAuthTests {
    private static let now = Date(timeIntervalSince1970: 1_793_793_600) // Wed 2026-11-04 12:00 UTC

    private var weekKey: String { LeaderboardTimeFrame.weekly.currentPeriod(referenceDate: Self.now).key }

    private func defaults() -> UserDefaults {
        let suite = "onboarding-auth-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func document(
        schemaVersion: Int = 1,
        periodKey: String? = nil,
        rows: [[String: Any]]
    ) -> [String: Any] {
        ["schemaVersion": schemaVersion, "periodKey": periodKey ?? weekKey, "rows": rows]
    }

    private func row(_ rank: Int, _ name: String, _ steps: Int, photo: String = "") -> [String: Any] {
        ["rank": rank, "displayName": name, "photoURL": photo, "totalSteps": steps]
    }

    // MARK: - The public board

    @Test
    func theBoardReadsTheTopThreeInOrderWithTheirNamesAndSteps() throws {
        let board = try #require(PublicWeeklyBoard.parse(
            document(rows: [row(1, "Maya R.", 38_891), row(2, "Jordan T.", 12_335), row(3, "Sam K.", 9_720)]),
            now: Self.now
        ))

        let entries = board.moderatedEntries()
        #expect(entries.map(\.rank) == [1, 2, 3])
        #expect(entries.map(\.identity.displayName) == ["Maya R.", "Jordan T.", "Sam K."])
        #expect(entries.map(\.formattedValue) == [38_891, 12_335, 9_720].map { $0.formatted() })
    }

    @Test
    func fewerThanThreeClimbersIsFewerRowsAndNeverAPlaceholder() throws {
        let board = try #require(PublicWeeklyBoard.parse(
            document(rows: [row(1, "Maya R.", 500)]), now: Self.now
        ))
        #expect(board.rows.count == 1)

        let empty = try #require(PublicWeeklyBoard.parse(document(rows: []), now: Self.now))
        #expect(empty.moderatedEntries().isEmpty)
    }

    @Test
    func lastWeeksDocumentIsNeverShownUnderThisWeeksCountdown() {
        let stale = document(periodKey: "2026-W44", rows: [row(1, "Maya R.", 38_891)])
        #expect(PublicWeeklyBoard.parse(stale, now: Self.now) == nil)
    }

    @Test
    func anUnknownSchemaOrAMalformedRowIsNotShown() throws {
        #expect(PublicWeeklyBoard.parse(document(schemaVersion: 2, rows: [row(1, "A", 5)]), now: Self.now) == nil)

        let board = try #require(PublicWeeklyBoard.parse(
            document(rows: [
                row(1, "  ", 100),
                row(0, "Zero rank", 100),
                row(2, "No steps", 0),
                row(3, "Sam K.", 9_720)
            ]),
            now: Self.now
        ))
        #expect(board.rows.map(\.displayName) == ["Sam K."])
    }

    @Test
    func atMostThreeRowsAreKept() throws {
        let board = try #require(PublicWeeklyBoard.parse(
            document(rows: (1...5).map { row($0, "Climber \($0)", 1_000 - $0) }),
            now: Self.now
        ))
        #expect(board.rows.count == 3)
    }

    @Test
    func aMissingOrEmptyDocumentIsAnAbsentBoardNotAnError() async {
        let viewModel = OnboardingAuthViewModel(mode: .claimSpot, repository: .init { _ in nil }, now: { Self.now })
        await viewModel.loadBoard()
        #expect(viewModel.board == nil)
        #expect(viewModel.entries.isEmpty)
        #expect(viewModel.hasLoadedBoard)
    }

    private final class ReadCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func increment() { lock.withLock { value += 1 } }
        var count: Int { lock.withLock { value } }
    }

    // MARK: - Modes

    @Test
    func theSignInOpensInReturningModeFromTheFirstScreenAndTheClaimSpotModeFromThePaywall() {
        let request = OnboardingAuthReturningRequest(userDefaults: defaults())

        #expect(OnboardingAuthViewModel.mode(arrivedFrom: .welcome, returningRequest: request) == .returning)
        #expect(OnboardingAuthViewModel.mode(arrivedFrom: .paywall, returningRequest: request) == .claimSpot)
        #expect(OnboardingAuthViewModel.mode(arrivedFrom: .exitGift, returningRequest: request) == .claimSpot)
        #expect(OnboardingAuthViewModel.mode(arrivedFrom: nil, returningRequest: request) == .claimSpot)
    }

    @Test
    func aReturningRequestFromThePaywallWinsOverTheStepItCameFrom() {
        let request = OnboardingAuthReturningRequest(userDefaults: defaults())
        request.set()

        #expect(OnboardingAuthViewModel.mode(arrivedFrom: .paywall, returningRequest: request) == .returning)

        request.clear()
        #expect(OnboardingAuthViewModel.mode(arrivedFrom: .paywall, returningRequest: request) == .claimSpot)
    }

    @Test
    func returningModeShowsNoBoardAndNeverReadsOne() async {
        let reads = ReadCounter()
        let viewModel = OnboardingAuthViewModel(
            mode: .returning,
            repository: .init { _ in reads.increment(); return nil },
            now: { Self.now }
        )
        await viewModel.loadBoard()

        #expect(!viewModel.showsBoard)
        #expect(reads.count == 0)
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

    // MARK: - Hand-off routes

    /// A recording stand-in for every seam, in the order they are reached.
    @MainActor
    private final class Recorder {
        var events: [String] = []
        var profile: UserDisplayNameData? = UserDisplayNameData(nil)
        var writeFails = false
        var readFails = false
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
                    if readFails { throw Refused() }
                    return profile
                },
                writeProfile: { [self] _, _, fill in
                    events.append("write")
                    if writeFails { throw Refused() }
                    writtenFills.append(fill)
                },
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
        #expect(OnboardingAuthViewModel.mode(arrivedFrom: coordinator.previousStep) == .returning)
    }
}
