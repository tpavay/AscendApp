import Foundation
import Testing
import UserNotifications
@testable import AscendApp

/// The email box on the v3 notification primer and what becomes of it.
///
/// The primer runs before sign-in, so the box cannot be recorded where it is ticked: the answer
/// waits in the pre-sign-in answers and the sign-in hand-off records it. These suites hold both
/// halves: that the box leaves the step in the state the climber left it, whichever button they
/// press, and that the hand-off turns that into a recorded `onboarding` decision.

/// The account's email preferences as the hand-off sees them, recording what it is asked to write.
actor HandOffEmailPreferences: EmailPreferencesProviding {
    private(set) var storedConsent: LifecycleEmailConsent
    private(set) var recorded: [StubEmailConsentDecision] = []
    private var loadError: (any Error)?
    private var recordError: (any Error)?

    init(storedConsent: LifecycleEmailConsent = .undecided) {
        self.storedConsent = storedConsent
    }

    func failLoad(with error: (any Error)?) {
        loadError = error
    }

    func failRecord(with error: (any Error)?) {
        recordError = error
    }

    func loadConsent() async throws -> LifecycleEmailConsent {
        if let loadError { throw loadError }
        return storedConsent
    }

    func recordConsent(isGranted: Bool, source: LifecycleEmailConsentSource) async throws {
        if let recordError { throw recordError }
        recorded.append(StubEmailConsentDecision(isGranted: isGranted, source: source))
        storedConsent = LifecycleEmailConsent(isGranted: isGranted)
    }
}

// MARK: - The box on the step

@MainActor
struct NotificationPrimerEmailOptInTests {
    private func coordinator(emailOptIn: Bool? = nil) -> OnboardingV3Coordinator {
        let suite = "primer-email-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let coordinator = OnboardingV3Coordinator(
            store: PreAuthOnboardingStore(userDefaults: defaults),
            startingAt: .notificationPrimer
        )
        if let emailOptIn {
            coordinator.update { $0.emailOptIn = emailOptIn }
        }
        return coordinator
    }

    private func viewModel(
        _ coordinator: OnboardingV3Coordinator,
        answer: UNAuthorizationStatus = .authorized
    ) -> NotificationPrimerViewModel {
        NotificationPrimerViewModel(
            coordinator: coordinator,
            loadCatalog: { .empty },
            requestAuthorization: { answer },
            declineNotifications: {},
            track: { _ in }
        )
    }

    @Test
    func theBoxShipsTicked() {
        let model = viewModel(coordinator())

        #expect(model.emailOptIn)
    }

    @Test
    func theBoxRecordsNothingUntilTheClimberLeavesTheStep() {
        let coordinator = coordinator()
        let model = viewModel(coordinator)

        model.toggleEmailOptIn()

        #expect(coordinator.answers.emailOptIn == nil)
    }

    @Test
    func turnOnLeavesATickedBoxAsAYes() async {
        let coordinator = coordinator()

        await viewModel(coordinator).turnOn()

        #expect(coordinator.answers.emailOptIn == true)
        #expect(coordinator.step == .auth)
    }

    @Test
    func untickingTheBoxRecordsAnExplicitNoOnTurnOn() async {
        let coordinator = coordinator()
        let model = viewModel(coordinator)

        model.toggleEmailOptIn()
        #expect(!model.emailOptIn)
        await model.turnOn()

        #expect(coordinator.answers.emailOptIn == false)
        #expect(coordinator.answers.notificationChoice == .allowed, "email never changes the push answer")
    }

    @Test
    func aDeniedPromptStillRecordsTheBox() async {
        let coordinator = coordinator()

        await viewModel(coordinator, answer: .denied).turnOn()

        #expect(coordinator.answers.notificationChoice == .denied)
        #expect(coordinator.answers.emailOptIn == true, "declining push is not declining email")
    }

    @Test
    func notNowKeepsATickedBox() async {
        let coordinator = coordinator()

        await viewModel(coordinator).notNow()

        #expect(coordinator.answers.notificationChoice == .skipped)
        #expect(coordinator.answers.emailOptIn == true, "Not now declines push, it does not discard the box")
        #expect(coordinator.step == .auth)
    }

    @Test
    func notNowKeepsAnUntickedBox() async {
        let coordinator = coordinator()
        let model = viewModel(coordinator)

        model.toggleEmailOptIn()
        await model.notNow()

        #expect(coordinator.answers.notificationChoice == .skipped)
        #expect(coordinator.answers.emailOptIn == false)
    }

    @Test
    func tickingTheBoxBackOnRecordsAYes() async {
        let coordinator = coordinator()
        let model = viewModel(coordinator)

        model.toggleEmailOptIn()
        model.toggleEmailOptIn()
        await model.notNow()

        #expect(coordinator.answers.emailOptIn == true)
    }

    @Test
    func comingBackToTheStepFindsTheBoxAsTheClimberLeftIt() {
        #expect(viewModel(coordinator(emailOptIn: false)).emailOptIn == false)
        #expect(viewModel(coordinator(emailOptIn: true)).emailOptIn == true)
    }

    @Test
    func theLabelNamesWhatTheEmailsAre() {
        #expect(NotificationPrimerContent.emailOptInLabel == "Send weekly climb recaps and milestone emails")
        #expect(!NotificationPrimerContent.emailOptInLabel.contains("\u{2014}"))
    }
}

// MARK: - The step on screen

@Suite(.serialized, .hostsAWindow)
@MainActor
struct NotificationPrimerEmailOptInScreenTests {
    private func coordinator() -> OnboardingV3Coordinator {
        let suite = "primer-email-screen-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return OnboardingV3Coordinator(
            store: PreAuthOnboardingStore(userDefaults: defaults),
            startingAt: .notificationPrimer
        )
    }

    @Test
    func theStepShowsTheBoxTickedAboveTurnOn() async throws {
        let coordinator = coordinator()
        let size = RenderedScreen.iPhone16ProSize

        try await RenderedScreen.host(
            OnboardingNotificationPrimerScreen(coordinator: coordinator).frame(width: size.width, height: size.height),
            size: size,
            settle: .turns(40)
        ) { screen in
            let copy = try await screen.copy()
            #expect(copy.contains(NotificationPrimerContent.emailOptInLabel.lowercased()))
            #expect(copy.contains("turn on"))
            #expect(copy.contains("not now"))

            let box = try #require(await screen.frame(ofElementLabelled: NotificationPrimerContent.emailOptInLabel))
            let turnOn = try #require(await screen.frame(ofElementLabelled: "Turn on"))
            #expect(box.maxY <= turnOn.minY, "the box sits above the primary button")

            try screen.photograph(named: "onboarding-v3-primer-email-box-ticked")
        }
    }

    @Test
    func untickingTheBoxThenPressingNotNowRecordsTheNo() async throws {
        // Not now writes the device-local push preference, which the rest of the suite shares.
        let pushPreference = ClimbDropNotificationPreferenceStore.isEnabled
        defer { ClimbDropNotificationPreferenceStore.isEnabled = pushPreference }

        let coordinator = coordinator()
        let size = RenderedScreen.iPhone16ProSize

        try await RenderedScreen.host(
            OnboardingNotificationPrimerScreen(coordinator: coordinator).frame(width: size.width, height: size.height),
            size: size,
            settle: .turns(40)
        ) { screen in
            try activateAccessibilityElement(labelled: NotificationPrimerContent.emailOptInLabel, in: screen.root)
            try await screen.settle(.turns(4))
            try screen.photograph(named: "onboarding-v3-primer-email-box-unticked")

            try activateAccessibilityElement(labelled: "Not now", in: screen.root)
            try await screen.settle(.turns(12))
        }

        #expect(coordinator.answers.emailOptIn == false)
        #expect(coordinator.answers.notificationChoice == .skipped)
        #expect(coordinator.step == .auth)
    }
}

// MARK: - The hand-off

@MainActor
struct OnboardingV3EmailConsentHandOffTests {
    private struct Offline: Error {}

    private func harness(
        emailOptIn: Bool?,
        preferences: HandOffEmailPreferences = HandOffEmailPreferences()
    ) -> (handOff: OnboardingV3SignInHandOff, store: PreAuthOnboardingStore, preferences: HandOffEmailPreferences) {
        let suite = "email-consent-handoff-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let store = PreAuthOnboardingStore(userDefaults: defaults)
        store.update { $0.emailOptIn = emailOptIn }

        let seams = OnboardingV3SignInHandOff.Seams(
            isProfileWriteEnabled: { true },
            signInNameSettled: {},
            readProfile: { _ in nil },
            writeProfile: { _, _, _ in },
            recordProfileStepFailure: { _ in },
            importHealthHistory: { _ in true },
            markPostSignInOnboardingComplete: {},
            deviceWeeklyTarget: { _ in nil },
            saveWeeklyTarget: { _, _ in },
            reconcileWeeklyTarget: { _ in },
            emailPreferences: preferences
        )
        let handOff = OnboardingV3SignInHandOff(
            seams: seams,
            store: store,
            intent: OnboardingV3HandOffIntent(userDefaults: defaults)
        )
        return (handOff, store, preferences)
    }

    @Test
    func aTickedBoxIsRecordedAsAnOnboardingYesAndLeavesTheDevice() async {
        let run = harness(emailOptIn: true)

        await run.handOff.runAfterSignIn(userId: "u1", email: nil)

        #expect(await run.preferences.recorded == [StubEmailConsentDecision(isGranted: true, source: .onboarding)])
        #expect(run.store.answers().emailOptIn == nil)
    }

    @Test
    func anUntickedBoxIsRecordedAsAnExplicitNo() async {
        let run = harness(emailOptIn: false)

        await run.handOff.runAfterSignIn(userId: "u1", email: nil)

        #expect(await run.preferences.recorded == [StubEmailConsentDecision(isGranted: false, source: .onboarding)])
        #expect(run.store.answers().emailOptIn == nil)
    }

    @Test
    func aClimberWhoNeverReachedTheStepRecordsNothing() async {
        let run = harness(emailOptIn: nil)

        await run.handOff.runAfterSignIn(userId: "u1", email: nil)

        #expect(await run.preferences.recorded.isEmpty)
    }

    @Test
    func anAnswerTheAccountAlreadyHoldsWinsOverThePreTick() async {
        // A climber who unsubscribed and signs back in on a new phone has answered already.
        let run = harness(emailOptIn: true, preferences: HandOffEmailPreferences(storedConsent: .declined))

        await run.handOff.runAfterSignIn(userId: "u1", email: nil)

        #expect(await run.preferences.recorded.isEmpty)
        #expect(await run.preferences.storedConsent == .declined)
        #expect(run.store.answers().emailOptIn == nil, "the stale answer does not wait for another run")
    }

    @Test
    func aFailedWriteKeepsTheAnswerAndTheNextRunLandsIt() async {
        let run = harness(emailOptIn: true)
        await run.preferences.failRecord(with: Offline())

        await run.handOff.runAfterSignIn(userId: "u1", email: nil)

        #expect(await run.preferences.recorded.isEmpty)
        #expect(run.store.answers().emailOptIn == true)

        await run.preferences.failRecord(with: nil)
        await run.handOff.retryPendingAnswers(userId: "u1", email: nil)

        #expect(await run.preferences.recorded == [StubEmailConsentDecision(isGranted: true, source: .onboarding)])
        #expect(run.store.answers().emailOptIn == nil)
    }

    @Test
    func anUnreadableAccountNeverGetsAGuessWrittenOverIt() async {
        let run = harness(emailOptIn: true)
        await run.preferences.failLoad(with: Offline())

        await run.handOff.runAfterSignIn(userId: "u1", email: nil)

        #expect(await run.preferences.recorded.isEmpty)
        #expect(run.store.answers().emailOptIn == true)
    }

    @Test
    func aRecordedAnswerIsNeverWrittenTwice() async {
        let run = harness(emailOptIn: true)

        await run.handOff.runAfterSignIn(userId: "u1", email: nil)
        await run.handOff.retryPendingAnswers(userId: "u1", email: nil)

        #expect(await run.preferences.recorded.count == 1)
    }

    @Test
    func theProfileSwitchBeingOffDoesNotHoldBackTheEmailAnswer() async {
        let suite = "email-consent-switch-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = PreAuthOnboardingStore(userDefaults: defaults)
        store.update {
            $0.emailOptIn = true
            $0.city = PreAuthOnboardingCity(city: "Denver", region: "CO", countryCode: "US", countryName: "United States")
        }
        let preferences = HandOffEmailPreferences()
        let handOff = OnboardingV3SignInHandOff(
            seams: .init(
                isProfileWriteEnabled: { false },
                signInNameSettled: {},
                readProfile: { _ in nil },
                writeProfile: { _, _, _ in },
                recordProfileStepFailure: { _ in },
                importHealthHistory: { _ in true },
                markPostSignInOnboardingComplete: {},
                deviceWeeklyTarget: { _ in nil },
                saveWeeklyTarget: { _, _ in },
                reconcileWeeklyTarget: { _ in },
                emailPreferences: preferences
            ),
            store: store,
            intent: OnboardingV3HandOffIntent(userDefaults: defaults)
        )

        let outcome = await handOff.runAfterSignIn(userId: "u1", email: nil)

        #expect(outcome == .deferred, "the profile answers still wait")
        #expect(await preferences.recorded == [StubEmailConsentDecision(isGranted: true, source: .onboarding)])
        #expect(store.answers().city != nil)
    }

    @Test
    func answersFromBeforeTheBoxExistedStillDecode() throws {
        let legacy = Data(#"{"notificationChoice":"skipped","foundHealthWorkoutIDs":[]}"#.utf8)

        let answers = try JSONDecoder().decode(PreAuthOnboardingAnswers.self, from: legacy)

        #expect(answers.emailOptIn == nil)
        #expect(answers.notificationChoice == .skipped)
    }
}
