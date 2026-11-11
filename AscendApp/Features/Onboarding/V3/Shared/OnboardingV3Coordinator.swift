import Observation
import SwiftUI

/// Drives the onboarding flow: which step is showing, where back goes, and the answers collected so
/// far. The selling and setup screens and sign-in run before an account exists. The flow ends at
/// sign-in: a climber who then holds no access meets the app-access paywall, which the root routes
/// to like any other signed-in climber without access.
///
/// Screens never decide the next step themselves. A primary action calls ``advance()``, an
/// alternate exit calls ``go(to:)``, and the coordinator keeps the trail so back returns to the
/// screen the climber came from rather than to the previous number - the Health branch and the
/// usual-climb branch both land on the profile screen, and back from there has to remember which.
@MainActor
@Observable
final class OnboardingV3Coordinator {
    /// The analytics flow every context of this pass reports under.
    static let segmentID = "onboarding_v3"

    /// How long one screen takes to fade into the next, in seconds.
    fileprivate static let transitionSeconds = 0.25

    private(set) var step: OnboardingV3Step
    private(set) var answers: PreAuthOnboardingAnswers

    /// The bar value the screen just left was showing, which the next bar animates from.
    private var lastShownProgress: Double?
    private var trail: [OnboardingV3Step] = []

    @ObservationIgnored private let store: PreAuthOnboardingStore
    @ObservationIgnored private let photos: OnboardingProfilePhotoStore
    @ObservationIgnored private let now: () -> ContinuousClock.Instant
    @ObservationIgnored private var transitionEnd: ContinuousClock.Instant?

    init(
        store: PreAuthOnboardingStore = PreAuthOnboardingStore(),
        photos: OnboardingProfilePhotoStore = OnboardingProfilePhotoStore(),
        startingAt step: OnboardingV3Step = .welcome,
        now: @escaping () -> ContinuousClock.Instant = { .now }
    ) {
        self.store = store
        self.photos = photos
        self.now = now
        self.step = step
        answers = store.answers()
    }

    /// Whether the answers on this device were carried into an account: the climber signed in at the
    /// end of the flow. It says whose the answers are, and never which screen a signed-out climber
    /// sees. That is the switch's alone (``OnboardingV3RouteLatch``): a finished pass that hid this
    /// flow sent every climber who signed out to the onboarding it replaced, on that launch and on
    /// every one after it.
    var isFinished: Bool { answers.completedAt != nil }

    var canGoBack: Bool { !trail.isEmpty }

    /// The screen back would return to. The sign-in screen reads it to tell a climber who walked
    /// the whole flow from one who tapped "Already have an account? Sign in" on the first screen.
    var previousStep: OnboardingV3Step? { trail.last }

    var analyticsContext: OnboardingAnalyticsContext {
        OnboardingAnalyticsContext(
            segmentID: Self.segmentID,
            flowVersion: OnboardingAnalyticsContext.currentFlowVersion,
            stepID: step.analyticsID
        )
    }

    // MARK: - Navigation

    /// The value the bar on `step` animates from: the bar the previous screen showed, or the entry
    /// value when the previous screen had none.
    func progressOrigin(for step: OnboardingV3Step) -> Double? {
        lastShownProgress ?? OnboardingProgressTable.value(for: step)
    }

    /// Follows the current screen's primary action. Sign-in has no destination: the root moves past
    /// it when the account appears, so no tap on the screen is the way out.
    ///
    /// Ignored while a transition runs: the outgoing screen's button still takes taps during the
    /// fade, so a double tap would otherwise skip the screen it just opened. A move the app makes on
    /// its own is not a tap, and uses ``go(to:)``.
    func advance() {
        if let transitionEnd, now() < transitionEnd { return }

        guard let destination = step.primaryDestination else { return }

        go(to: destination)
    }

    /// Moves to `destination` and remembers where it came from, so back retraces the real path.
    func go(to destination: OnboardingV3Step) {
        guard destination != step else { return }

        trail.append(step)
        show(destination, from: step)
    }

    /// Returns to the screen the climber came from. Does nothing on the first screen.
    func back() {
        guard let previous = trail.popLast() else { return }
        show(previous, from: step)
    }

    private func show(_ destination: OnboardingV3Step, from origin: OnboardingV3Step) {
        lastShownProgress = OnboardingProgressTable.value(for: origin) ?? OnboardingProgressTable.entryValue
        step = destination
        transitionEnd = now() + .seconds(Self.transitionSeconds)
    }

    // MARK: - Answers

    /// The photo picked on the profile screen, while it is still on the device. The answers name
    /// the file; the picture itself lives in ``OnboardingProfilePhotoStore``.
    var profilePhotoURL: URL? { photos.url(for: answers.profilePhotoFileName) }

    /// Changes the answers and persists them. Nothing here is sent anywhere; see
    /// ``PreAuthOnboardingAnswers``.
    func update(_ change: (inout PreAuthOnboardingAnswers) -> Void) {
        answers = store.update(change)
    }

    /// An account appeared. The signed-out screens are behind the app's own routes from here, so the
    /// flow goes back to its first screen now, while nothing shows it: whoever is signed out next
    /// starts at Welcome, never on the sign-in screen the last climber left by.
    func sessionBegan() {
        returnToWelcome()
    }

    /// The climber signed out, or their account was deleted or revoked. Everything the flow holds
    /// leaves the device and this copy - the answers, the photo and the mark that it was finished -
    /// so the next person on this phone starts clean at Welcome. A climber coming back signs in from
    /// there, through "Already have an account? Sign in".
    func sessionEnded() {
        store.clear()
        photos.remove()
        answers = store.answers()
        returnToWelcome()
    }

    /// The app launched with nobody signed in. A finished pass still on the device belongs to a
    /// session that ended where this app could not see it - revoked while the app was closed, or
    /// ended by a build that kept the pass - so it goes the way a sign-out sends it. An unfinished
    /// pass is a climber partway through the flow, and stays.
    func launchedSignedOut() {
        guard isFinished else { return }
        sessionEnded()
    }

    private func returnToWelcome() {
        trail = []
        lastShownProgress = nil
        transitionEnd = nil
        step = .welcome
    }

    /// The climber signed in at the end of the flow: the answers are that account's from here.
    func finish() {
        guard !isFinished else { return }
        update { $0.completedAt = Date() }
    }
}

/// The screen for each step. Every screen takes only the coordinator: what it shows comes from the
/// answers so far, and where it goes is the coordinator's to decide, so this switch is the whole
/// map of the flow.
struct OnboardingV3FlowView: View {
    let coordinator: OnboardingV3Coordinator

    var body: some View {
        ZStack {
            OnboardingV3Palette.background.ignoresSafeArea()

            screen(for: coordinator.step)
                .id(coordinator.step)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: OnboardingV3Coordinator.transitionSeconds), value: coordinator.step)
        .environment(\.onboardingV3Coordinator, coordinator)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .trackOnboardingScreenView(coordinator.analyticsContext)
        // Screen 11 reads this month's event from the hosted catalogue, and a fresh install has
        // only the bundled copy, so the refresh starts the moment the flow opens.
        .task { OnboardingMonthlyEventModel.shared.prefetch() }
    }

    @ViewBuilder
    private func screen(for step: OnboardingV3Step) -> some View {
        switch step {
        case .welcome: OnboardingWelcomeScreen(coordinator: coordinator)
        case .goHarder: OnboardingGoHarderScreen(coordinator: coordinator)
        case .getBetter: OnboardingGetBetterScreen(coordinator: coordinator)
        case .somethingToChase: OnboardingSomethingToChaseScreen(coordinator: coordinator)
        case .countMethods: OnboardingCountMethodsScreen(coordinator: coordinator)
        case .healthConnect: OnboardingHealthConnectScreen(coordinator: coordinator)
        case .healthPermission: OnboardingHealthPermissionScreen(coordinator: coordinator)
        case .healthHistory: OnboardingHealthHistoryScreen(coordinator: coordinator)
        case .usualClimb: OnboardingUsualClimbScreen(coordinator: coordinator)
        case .profileSetup: OnboardingProfileSetupScreen(coordinator: coordinator)
        case .claimCity: OnboardingClaimCityScreen(coordinator: coordinator)
        case .weeklyTarget: OnboardingWeeklyTargetScreen(coordinator: coordinator)
        case .thisMonthEvent: OnboardingThisMonthEventScreen(coordinator: coordinator)
        case .notificationPrimer: OnboardingNotificationPrimerScreen(coordinator: coordinator)
        case .auth: OnboardingAuthScreen(coordinator: coordinator)
        }
    }
}
