import SwiftUI

extension View {
    /// Emits `onboarding_screen_viewed` once per distinct `step_id` for the lifetime of the view,
    /// so navigating back to an already-viewed step re-emits nothing and the funnel counts a step
    /// once per pass through the flow rather than once per visit. The dedupe is view-scoped rather
    /// than persisted: a relaunch mid-flow starts a fresh set and re-emits the current step. A
    /// `nil` context emits nothing, which lets callers whose step is index-derived pass an
    /// out-of-bounds state through.
    @MainActor
    func trackOnboardingScreenView(
        _ context: OnboardingAnalyticsContext?,
        lifecycle: OnboardingFlowAnalyticsCoordinator = .shared
    ) -> some View {
        modifier(OnboardingScreenViewTracker(context: context, lifecycle: lifecycle))
    }
}

private struct OnboardingScreenViewTracker: ViewModifier {
    let context: OnboardingAnalyticsContext?
    let lifecycle: OnboardingFlowAnalyticsCoordinator

    @State private var recorder = OnboardingScreenViewRecorder()

    func body(content: Content) -> some View {
        content
            .onAppear {
                recordScreenViewIfNeeded()
            }
            .onChange(of: context) { _, _ in
                recordScreenViewIfNeeded()
            }
    }

    private func recordScreenViewIfNeeded() {
        guard let context else { return }

        // Any onboarding screen can be the first one a pass shows: a reinstall keeps the Keychain
        // session while `UserDefaults` starts empty, so a climber who signed in but never finished
        // resumes mid-flow and never sees welcome.
        lifecycle.recordFlowStartedIfNeeded(context: context)

        recorder.recordIfNeeded(
            context,
            resume: lifecycle.consumeScreenResumeFlag()
        )
    }
}

struct OnboardingScreenViewRecorder {
    private var viewedStepIDs: Set<String> = []

    mutating func recordIfNeeded(
        _ context: OnboardingAnalyticsContext?,
        resume: Bool = false,
        telemetry: TelemetryManager = .shared,
        expectedUserID: String? = nil
    ) {
        guard let context, viewedStepIDs.insert(context.stepID).inserted else { return }

        let event = OnboardingAnalyticsEvent.screenViewed(context: context, resume: resume)
        if let expectedUserID {
            telemetry.track(event, ifIdentifiedAs: expectedUserID)
        } else {
            telemetry.track(event)
        }
    }
}
