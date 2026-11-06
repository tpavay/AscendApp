import Observation
import SwiftUI

/// Drives the onboarding flow: which step is showing, where back goes, and the answers collected so
/// far. The selling and setup screens and sign-in run before an account exists; the paywall and the
/// welcome gift run after it, for a climber who signed in at the end of the flow and holds no access.
///
/// Screens never decide the next step themselves. A primary action calls ``advance()``, an
/// alternate exit calls ``go(to:)``, and the coordinator keeps the trail so back returns to the
/// screen the climber came from rather than to the previous number - the Health branch and the
/// usual-climb branch both land on the climber card, and back from there has to remember which.
@MainActor
@Observable
final class OnboardingV3Coordinator {
    /// The analytics flow every context of this pass reports under.
    static let segmentID = "onboarding_v3"

    /// How long one screen takes to fade into the next, in seconds.
    fileprivate static let transitionSeconds = 0.25

    private(set) var step: OnboardingV3Step
    private(set) var answers: PreAuthOnboardingAnswers

    /// The account that signed in at the end of the flow and has not yet reached access. Persisted
    /// in the answers, so a relaunch before buying returns to the paywall and the gift rather than
    /// to the app-access gate. The paywall carries the gate's delete-account and sign-out routes.
    private(set) var paywallStageUserID: String?

    /// The bar value the screen just left was showing, which the next bar animates from.
    private var lastShownProgress: Double?
    private var trail: [OnboardingV3Step] = []

    @ObservationIgnored private let store: PreAuthOnboardingStore
    @ObservationIgnored private let now: () -> ContinuousClock.Instant
    @ObservationIgnored private var transitionEnd: ContinuousClock.Instant?

    init(
        store: PreAuthOnboardingStore = PreAuthOnboardingStore(),
        startingAt step: OnboardingV3Step = .welcome,
        now: @escaping () -> ContinuousClock.Instant = { .now }
    ) {
        self.store = store
        self.now = now
        let answers = store.answers()
        self.answers = answers
        paywallStageUserID = answers.paywallStageUserID
        self.step = answers.paywallStageUserID == nil ? step : .paywall
    }

    /// Whether `userID` is the account the paywall stage belongs to.
    func presentsPaywall(for userID: String?) -> Bool {
        guard let userID else { return false }

        return paywallStageUserID == userID
    }

    /// Whether the climber has signed in at the end of the flow, after which the signed-out screens
    /// never show again.
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

    /// Follows the current screen's primary action. A step with no destination - sign-in, the paywall
    /// and the gift, which the root moves past - does nothing.
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

    /// Changes the answers and persists them. Nothing here is sent anywhere; see
    /// ``PreAuthOnboardingAnswers``.
    func update(_ change: (inout PreAuthOnboardingAnswers) -> Void) {
        answers = store.update(change)
    }

    /// The climber signed out. Their answers leave the device and this copy, so neither the next
    /// account nor a prefilled setup screen receives them. The flow stays finished if it was.
    func sessionEnded() {
        answers = store.update { $0 = $0.droppingSessionAnswers }
        paywallStageUserID = nil
    }

    /// The climber signed in at the end of the flow. The signed-out screens are done for good, and
    /// when `showsPaywall` is set the paywall opens for them if they turn out to hold no access -
    /// the root decides that from the entitlement, so a climber who already pays never sees it.
    func completeSignIn(userID: String, showsPaywall: Bool) {
        update {
            if $0.completedAt == nil { $0.completedAt = Date() }
            if showsPaywall { $0.paywallStageUserID = userID }
        }

        guard showsPaywall else { return }
        trail = []
        paywallStageUserID = userID
        show(.paywall, from: step)
    }

    /// The climber holds access, so the paywall has nothing left to sell. A lapse later meets the
    /// app-access gate, not this flow.
    func paywallStageEnded() {
        guard paywallStageUserID != nil else { return }

        paywallStageUserID = nil
        update { $0.paywallStageUserID = nil }
    }
}

/// The screen for each step. Every case names the view a chunk replaces; a replacement keeps the
/// type name and the `init(coordinator:)` signature, so this switch never changes and six chunks
/// can land without touching one another.
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
        case .climberCard: OnboardingClimberCardScreen(coordinator: coordinator)
        case .claimCity: OnboardingClaimCityScreen(coordinator: coordinator)
        case .weeklyTarget: OnboardingWeeklyTargetScreen(coordinator: coordinator)
        case .thisMonthEvent: OnboardingThisMonthEventScreen(coordinator: coordinator)
        case .notificationPrimer: OnboardingNotificationPrimerScreen(coordinator: coordinator)
        case .paywall: OnboardingPaywallScreen(coordinator: coordinator)
        case .exitGift: OnboardingExitGiftScreen(coordinator: coordinator)
        case .auth: OnboardingAuthScreen(coordinator: coordinator)
        }
    }
}
