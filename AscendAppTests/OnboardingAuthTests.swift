import FirebaseFirestore
import Foundation
import Testing
@testable import AscendApp

/// The sign-in screen and what happens when the climber signs in at the end of the flow: the list
/// of what saves, the two modes, the profile fill, and every route's hand-off.
@MainActor
struct OnboardingAuthTests {
    private static let now = Date(timeIntervalSince1970: 1_793_793_600) // Wed 2026-11-04 12:00 UTC

    private func defaults() -> UserDefaults {
        let suite = "onboarding-auth-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: - What saves

    private func items(_ answers: PreAuthOnboardingAnswers, photoURL: URL? = nil) -> [OnboardingSavedItem] {
        OnboardingSavedItems.make(from: answers, photoURL: photoURL, now: Self.now, calendar: Calendar(identifier: .gregorian))
    }

    @Test
    func aClimberWhoSkippedEverythingSeesTheTwoThingsEveryAccountGets() {
        let items = items(PreAuthOnboardingAnswers())

        #expect(items.map(\.kind) == [.climbs, .boards])
        #expect(items[0].title == "Every climb from today")
        #expect(items[0].subtitle == "Steps, time, streak and new bests")
        #expect(items[1].title == "Your spot on the boards")
        #expect(items[1].subtitle == "Leaderboards and live climbs")
    }

    @Test
    func everythingTheClimberGaveFillsTheListInTheDesignsOrder() {
        var answers = fullAnswers()
        answers.weeklyTargetDays = 4
        answers.recordFoundHealthHistory(.reportedByEveryWorkout(workoutIDs: (0..<214).map { "w\($0)" }, knownSteps: 698_240))
        answers.gender = .man
        answers.birthday = PreAuthOnboardingBirthday(year: 1996, month: 3, day: 9)

        let items = items(answers)

        #expect(items.map(\.kind) == [.climbs, .healthHistory, .profile, .boards])
        #expect(items[0].subtitle == "Steps, time, streak and new bests \u{00B7} 4 days a week")
        #expect(items[1].title == "214 past climbs \u{00B7} 698,240 steps")
        #expect(items[1].subtitle == "From Apple Health, with past bests")
        #expect(items[2].title == "M \u{00B7} 30")
        #expect(items[2].subtitle == "Your profile \u{00B7} Denver")
    }

    @Test
    func theHistoryRowCountsOneClimbAndLeavesStepsOutWhenNoneWereReported() {
        var answers = PreAuthOnboardingAnswers()
        answers.recordFoundHealthHistory(.reportedByEveryWorkout(workoutIDs: ["w1"], knownSteps: 0))

        let history = items(answers).first { $0.kind == .healthHistory }
        #expect(history?.title == "1 past climb")
        #expect(answers.foundHealthKnownSteps == nil)
    }

    @Test
    func aHistoryTheClimberTookBackHasNoRow() {
        var answers = PreAuthOnboardingAnswers()
        answers.recordFoundHealthHistory(.reportedByEveryWorkout(workoutIDs: ["w1", "w2"], knownSteps: 5_000))
        answers.clearFoundHealthHistory()

        #expect(answers.foundHealthKnownSteps == nil)
        #expect(!items(answers).contains { $0.kind == .healthHistory })
    }

    @Test
    func theProfileRowSaysOnlyWhatTheProfileHolds() {
        var woman = PreAuthOnboardingAnswers()
        woman.gender = .woman
        #expect(items(woman).first { $0.kind == .profile }?.title == "F")
        #expect(items(woman).first { $0.kind == .profile }?.subtitle == "Your profile")

        var quiet = PreAuthOnboardingAnswers()
        quiet.gender = .preferNotToSay
        quiet.heightCm = 170
        #expect(items(quiet).first { $0.kind == .profile }?.title == "Your details")

        var cityOnly = PreAuthOnboardingAnswers()
        cityOnly.city = PreAuthOnboardingCity(city: "Denver", region: "CO", countryCode: "US", countryName: "United States")
        let city = items(cityOnly).first { $0.kind == .profile }
        #expect(city?.title == "Your details")
        #expect(city?.subtitle == "Your profile \u{00B7} Denver")

        var tooYoung = PreAuthOnboardingAnswers()
        tooYoung.birthday = PreAuthOnboardingBirthday(year: 2020, month: 1, day: 1)
        #expect(items(tooYoung).first { $0.kind == .profile }?.title == "Your details", "an age the screen refuses is not said back")
    }

    @Test
    func aTypedNameLeadsTheProfileRowAndItsInitialsTakeTheMark() throws {
        var answers = PreAuthOnboardingAnswers()
        answers.firstName = "Sam"
        answers.lastName = "Rivera"
        answers.gender = .man
        answers.birthday = PreAuthOnboardingBirthday(year: 1996, month: 3, day: 9)

        let row = try #require(items(answers).first { $0.kind == .profile })

        #expect(row.title == "Sam Rivera \u{00B7} M \u{00B7} 30")
        #expect(row.initials == "SR")
    }

    @Test
    func aNameOrPhotoAloneEarnsTheProfileRow() throws {
        var firstNameOnly = PreAuthOnboardingAnswers()
        firstNameOnly.firstName = "Sam"
        let first = try #require(items(firstNameOnly).first { $0.kind == .profile })
        #expect(first.title == "Sam")
        #expect(first.initials == "S")

        var lastNameOnly = PreAuthOnboardingAnswers()
        lastNameOnly.lastName = "Rivera"
        let last = try #require(items(lastNameOnly).first { $0.kind == .profile })
        #expect(last.title == "Rivera")
        #expect(last.initials == "R")

        var photoOnly = PreAuthOnboardingAnswers()
        photoOnly.profilePhotoFileName = "photo.jpg"
        let photo = try #require(items(photoOnly).first { $0.kind == .profile })
        #expect(photo.title == "Your details")
        #expect(photo.initials == nil)

        #expect(!items(PreAuthOnboardingAnswers()).contains { $0.kind == .profile })
    }

    @Test
    func aPickedPhotoTakesTheProfileRowsMarkWhileItIsOnTheDevice() throws {
        let onDevice = URL(filePath: "/photos/photo-1.jpg")

        var picked = PreAuthOnboardingAnswers()
        picked.firstName = "Sam"
        picked.lastName = "Rivera"
        picked.profilePhotoFileName = "photo-1.jpg"
        let row = try #require(items(picked, photoURL: onDevice).first { $0.kind == .profile })
        #expect(row.photoURL == onDevice)
        #expect(row.initials == "SR", "the initials stay behind the photo for a load that fails")

        // The file named by the answers is gone from the device: the initials draw instead.
        let gone = try #require(items(picked, photoURL: nil).first { $0.kind == .profile })
        #expect(gone.photoURL == nil)
        #expect(gone.initials == "SR")

        // No photo was picked, so a picture the device happens to hold is not this climber's.
        var unpicked = PreAuthOnboardingAnswers()
        unpicked.firstName = "Sam"
        let withoutPhoto = try #require(items(unpicked, photoURL: onDevice).first { $0.kind == .profile })
        #expect(withoutPhoto.photoURL == nil)
    }

    @Test
    func aNameThePolicyRefusesIsNeverSaidBackOnTheProfileRow() throws {
        var refused = PreAuthOnboardingAnswers()
        refused.firstName = "Fuck"
        refused.gender = .woman
        let withGender = try #require(items(refused).first { $0.kind == .profile })
        #expect(withGender.title == "F")
        #expect(withGender.initials == nil)

        refused.gender = nil
        #expect(!items(refused).contains { $0.kind == .profile }, "nothing of theirs will be saved")
        #expect(refused.carriesProfileAnswers, "the hand-off still clears it from the device")
    }

    @Test
    func aTargetTheRulesRefuseIsNotSaidBack() {
        var answers = PreAuthOnboardingAnswers()
        answers.weeklyTargetDays = 9
        #expect(items(answers)[0].subtitle == "Steps, time, streak and new bests")

        answers.weeklyTargetDays = 1
        #expect(items(answers)[0].subtitle == "Steps, time, streak and new bests \u{00B7} 1 day a week")
    }

    // MARK: - Modes

    @Test
    func theSignInOpensInReturningModeFromTheFirstScreenAndTheSaveEveryClimbModeFromTheSetupScreens() {
        #expect(OnboardingAuthMode(arrivedFrom: .welcome) == .returning)
        #expect(OnboardingAuthMode(arrivedFrom: .notificationPrimer) == .saveEveryClimb)
        #expect(OnboardingAuthMode(arrivedFrom: nil) == .saveEveryClimb)
    }

    @Test
    func walkingTheFlowEndsInSaveEveryClimbAndTheFirstScreensLinkEndsInReturning() {
        let store = PreAuthOnboardingStore(userDefaults: defaults())

        let walked = OnboardingV3Coordinator(store: store, startingAt: .notificationPrimer)
        walked.advance()
        #expect(walked.step == .auth)
        #expect(OnboardingAuthMode(arrivedFrom: walked.previousStep) == .saveEveryClimb)

        let linked = OnboardingV3Coordinator(store: store)
        linked.go(to: .auth)
        #expect(OnboardingAuthMode(arrivedFrom: linked.previousStep) == .returning)

        linked.back()
        #expect(linked.step == .welcome)
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
        /// The account's copy on this device, which `deviceWeeklyTarget` answers with.
        var deviceTarget: Int?
        var reconciledReminders: [Int?] = []
        var savedTargets: [Int] = []
        var healthImportLands = true
        let emailPreferences = HandOffEmailPreferences()

        struct Refused: Error {}

        func seams() -> OnboardingV3SignInHandOff.Seams {
            .init(
                isProfileWriteEnabled: { [self] in profileWriteEnabled },
                signInNameSettled: {},
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
                    return healthImportLands
                },
                markPostSignInOnboardingComplete: { [self] in events.append("markComplete") },
                deviceWeeklyTarget: { [self] _ in deviceTarget },
                saveWeeklyTarget: { [self] _, days in
                    events.append("saveTarget")
                    savedTargets.append(days)
                    accountTarget = days
                    deviceTarget = days
                },
                reconcileWeeklyTarget: { [self] _ in
                    events.append("reconcileTarget")
                    reconciledReminders.append(accountTarget)
                },
                emailPreferences: emailPreferences
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
    func signInClosesTheFlowThenWritesTheAnswers() async {
        var answers = fullAnswers()
        answers.completedAt = Self.now
        let harness = Harness(defaults: defaults(), answers: answers)
        harness.intent.set()

        let outcome = await harness.handOff.runAfterSignIn(userId: "u1", email: nil)

        #expect(outcome == .complete)
        // The flow closes first, so the route never shows the old questions while the answers land.
        #expect(harness.recorder.events == ["markComplete", "read", "write", "health", "reconcileTarget"])
        #expect(harness.recorder.writtenFills.count == 1)
        #expect(!harness.store.answers().carriesHandOffWork)
        #expect(harness.store.answers().completedAt == Self.now, "the flow stays finished")
        #expect(!harness.intent.isSet)
    }

    @Test
    func returningModeNeverClosesPostSignInOnboarding() async {
        let harness = Harness(defaults: defaults(), answers: PreAuthOnboardingAnswers())
        // No intent: returning mode never sets one.

        let outcome = await harness.handOff.runAfterSignIn(userId: "u1", email: nil)

        #expect(outcome == .complete)
        #expect(harness.recorder.events == ["reconcileTarget"])
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
        answers.recordFoundHealthHistory(.reportedByEveryWorkout(workoutIDs: ["w1", "w2"], knownSteps: 8_000))
        let harness = Harness(defaults: defaults(), answers: answers)

        #expect(await harness.handOff.retryPendingAnswers(userId: "u1", email: nil) == .complete)
        #expect(harness.recorder.events == ["health"])
        #expect(harness.recorder.importedAnswers.first?.foundHealthWorkoutIDs == ["w1", "w2"])
        #expect(harness.store.answers().foundHealthWorkoutIDs.isEmpty)
        #expect(harness.store.answers().foundHealthKnownSteps == nil, "the steps leave with the workouts")
    }

    @Test
    func healthWorkoutsNoImportLandedStayOnTheDeviceWhileTheOtherAnswersLeave() async {
        var answers = fullAnswers()
        answers.foundHealthWorkoutIDs = ["w1", "w2"]
        let harness = Harness(defaults: defaults(), answers: answers)
        harness.recorder.healthImportLands = false

        #expect(await harness.handOff.retryPendingAnswers(userId: "u1", email: nil) == .complete)
        #expect(harness.store.answers().foundHealthWorkoutIDs == ["w1", "w2"])
        #expect(!harness.store.answers().carriesProfileAnswers)

        harness.recorder.events.removeAll()
        harness.recorder.healthImportLands = true
        #expect(await harness.handOff.retryPendingAnswers(userId: "u1", email: nil) == .complete)
        #expect(harness.recorder.events == ["health"], "holding the workouts costs no profile read")
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
        #expect(harness.store.answers().weeklyTargetDays == 4, "the nudge reads it here")
        let events = harness.recorder.events
        #expect(events.firstIndex(of: "saveTarget")! < events.firstIndex(of: "reconcileTarget")!, "the reminder reads what was just saved")
    }

    @Test
    func aDeliveredTargetIsNeverDeliveredAgain() async {
        var answers = PreAuthOnboardingAnswers()
        answers.weeklyTargetDays = 4
        let harness = Harness(defaults: defaults(), answers: answers)

        await harness.handOff.runAfterSignIn(userId: "u1", email: nil)
        harness.recorder.events.removeAll()

        #expect(await harness.handOff.retryPendingAnswers(userId: "u1", email: nil) == .complete)
        #expect(harness.recorder.events.isEmpty)
    }

    @Test
    func aTargetTheAccountAlreadyHoldsWinsOverTheAnswer() async {
        var answers = PreAuthOnboardingAnswers()
        answers.weeklyTargetDays = 4
        let harness = Harness(defaults: defaults(), answers: answers)
        harness.recorder.profile = UserDisplayNameData(["weekly_target_days": 2])
        harness.recorder.accountTarget = 2

        await harness.handOff.runAfterSignIn(userId: "u1", email: nil)

        #expect(harness.recorder.savedTargets.isEmpty)
        #expect(harness.recorder.reconciledReminders == [2])
    }

    @Test
    func anUnreadableProfileHoldsAnUndeliveredTarget() async {
        var answers = PreAuthOnboardingAnswers()
        answers.weeklyTargetDays = 4
        let harness = Harness(defaults: defaults(), answers: answers)
        harness.recorder.readFails = true

        #expect(await harness.handOff.retryPendingAnswers(userId: "u1", email: nil) == .deferred)
        #expect(harness.recorder.savedTargets.isEmpty)
        #expect(harness.store.answers().weeklyTargetDays == 4)
    }

    @Test
    func aTargetWithADeviceCopyIsTheServicesToDeliverAndCostsNoRead() async {
        var answers = PreAuthOnboardingAnswers()
        answers.weeklyTargetDays = 3
        let harness = Harness(defaults: defaults(), answers: answers)
        harness.recorder.deviceTarget = 3

        #expect(await harness.handOff.retryPendingAnswers(userId: "u1", email: nil) == .complete)
        #expect(harness.recorder.events.isEmpty)
        #expect(harness.store.answers().weeklyTargetDays == 3)
    }

    // MARK: - Signing out

    @Test
    func theNextAccountOnThePhoneNeverReceivesAnotherClimbersDeferredAnswers() async {
        var answers = fullAnswers()
        answers.weeklyTargetDays = 4
        answers.recordFoundHealthHistory(.reportedByEveryWorkout(workoutIDs: ["w1"], knownSteps: 2_000))
        answers.usualClimbSteps = 1_800
        answers.completedAt = Self.now
        let harness = Harness(defaults: defaults(), answers: answers)
        let flow = OnboardingV3Coordinator(store: harness.store, startingAt: .welcome)
        harness.recorder.profileWriteEnabled = false

        #expect(await harness.handOff.runAfterSignIn(userId: "a", email: nil) == .deferred)

        flow.sessionEnded()
        harness.recorder.profileWriteEnabled = true
        harness.recorder.events.removeAll()

        #expect(await harness.handOff.runAfterSignIn(userId: "b", email: nil) == .complete)
        #expect(harness.recorder.writtenFills.isEmpty)
        #expect(harness.recorder.savedTargets.isEmpty)
        #expect(harness.recorder.importedAnswers.isEmpty)
        #expect(harness.recorder.events == ["reconcileTarget"])
        #expect(flow.answers.gender == nil, "no setup screen prefills the last climber's answers")
        #expect(flow.answers.foundHealthWorkoutIDs.isEmpty)
        #expect(flow.answers.foundHealthKnownSteps == nil)
        #expect(!flow.isFinished, "the finished pass was the last climber's, and left with them")
        #expect(harness.store.answers() == PreAuthOnboardingAnswers(), "nothing of theirs stays on the device")
    }

    @Test
    func aReturningClimberWhoSignsOutIsNotClosedOutAndABrandNewAccountIsNotEither() async throws {
        let harness = Harness(defaults: defaults(), answers: PreAuthOnboardingAnswers())
        let flow = OnboardingV3Coordinator(store: harness.store)
        flow.go(to: .auth)

        await harness.handOff.runAfterSignIn(userId: "a", email: nil)
        flow.sessionBegan()
        flow.sessionEnded()

        #expect(flow.step == .welcome)
        #expect(!flow.canGoBack)
        #expect(!flow.isFinished)
        #expect(!harness.intent.isSet)

        // Signing back in is the first screen's "Already have an account? Sign in", in returning mode.
        let signIn = try #require(OnboardingV3Step.welcome.alternateExits.first)
        flow.go(to: signIn.destination)
        #expect(flow.step == .auth)
        #expect(OnboardingAuthMode(arrivedFrom: flow.previousStep) == .returning)

        harness.recorder.events.removeAll()
        await harness.handOff.runAfterSignIn(userId: "b", email: nil)
        #expect(!harness.recorder.events.contains("markComplete"))
    }

    @Test
    func signingOutAndBackInRestoresTheReminderFromTheAccount() async {
        // The first sign-in saves the target. Sign-out then erases the answer the nudge reads; the
        // second sign-in has nothing to write and must still bring the reminder back.
        var answers = PreAuthOnboardingAnswers()
        answers.weeklyTargetDays = 3
        let harness = Harness(defaults: defaults(), answers: answers)
        await harness.handOff.runAfterSignIn(userId: "u1", email: nil)
        #expect(harness.recorder.reconciledReminders == [3])

        // Sign-out: reminders cleared, answers gone. The account still holds 3.
        harness.store.clear()
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

extension HealthHistorySummary {
    /// A history whose every workout reports its steps, or none does when the total is zero.
    static func reportedByEveryWorkout(workoutIDs: [String], knownSteps: Int) -> HealthHistorySummary {
        HealthHistorySummary(
            workoutIDs: workoutIDs,
            totalDuration: 0,
            workoutsWithSteps: knownSteps > 0 ? workoutIDs.count : 0,
            knownSteps: knownSteps,
            bestHourSteps: nil,
            usualClimb: nil
        )
    }
}
