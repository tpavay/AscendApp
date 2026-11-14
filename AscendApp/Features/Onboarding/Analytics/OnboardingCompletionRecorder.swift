import Foundation

/// What is recorded the moment a climber signs in at the end of the onboarding: the user property
/// the analytics read, and the lifecycle event the backend keeps as the account's onboarding state.
///
/// The step names are the v3 funnel's own (``OnboardingV3Step``), so the lifecycle record names the
/// screens a climber actually walked.
@MainActor
enum OnboardingCompletionRecorder {
    static func recordCompleted() {
        OnboardingAnalyticsUserProperties.setOnboardingCompleted()
        LifecycleEventRecorder.shared.recordOnboardingCompleted(
            currentStage: OnboardingV3Step.auth.analyticsID,
            completedStages: OnboardingV3Step.allCases.map(\.analyticsID)
        )
    }
}
