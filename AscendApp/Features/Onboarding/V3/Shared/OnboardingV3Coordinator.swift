import Observation
import SwiftUI

/// Drives the pre-sign-in onboarding flow: which step is showing, where back goes, and the answers
/// collected so far.
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
    /// Counts every move between steps. Each one is a new arrival, including a return to a step
    /// whose screen is still fading out.
    private(set) var arrival = 0
    private(set) var answers: PreAuthOnboardingAnswers

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
        self.step = step
        answers = store.answers()
    }

    /// Whether the flow has reached its end, and the app moves on to what follows it.
    var isFinished: Bool { answers.completedAt != nil }

    var canGoBack: Bool { !trail.isEmpty }

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

    /// Follows the current screen's primary action. On the last screen it finishes the flow.
    ///
    /// Ignored while a transition runs: the outgoing screen's button still takes taps during the
    /// fade, so a double tap would otherwise skip the screen it just opened.
    func advance() {
        if let transitionEnd, now() < transitionEnd { return }

        guard let destination = step.primaryDestination else {
            finish()
            return
        }

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
        arrival += 1
    }

    // MARK: - Answers

    /// Changes the answers and persists them. Nothing here is sent anywhere; see
    /// ``PreAuthOnboardingAnswers``.
    func update(_ change: (inout PreAuthOnboardingAnswers) -> Void) {
        answers = store.update(change)
    }

    /// Ends the flow. The app resolves its route from ``isFinished`` after this.
    func finish() {
        guard !isFinished else { return }
        update { $0.completedAt = Date() }
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
                // Per arrival, not per step: an id that returns while its view is still fading out
                // revives that view, whose `.task` does not run again. A screen's arrival check - a
                // climber holding access has nothing left to buy here - would then never run.
                .id(coordinator.arrival)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: OnboardingV3Coordinator.transitionSeconds), value: coordinator.step)
        .environment(\.onboardingV3Coordinator, coordinator)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .trackOnboardingScreenView(coordinator.analyticsContext)
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
