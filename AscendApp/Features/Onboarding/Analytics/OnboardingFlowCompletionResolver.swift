import Foundation

enum OnboardingFlowCompletionResolver {
    static func completionReason(
        rootRoute: AppRootRoute,
        postAuthPhase: PostAuthOnboardingPhase,
        confirmedAccessReason: OnboardingFlowCompletionReason?
    ) -> OnboardingFlowCompletionReason? {
        guard rootRoute == .mainApp,
              postAuthPhase == .complete else {
            return nil
        }

        return confirmedAccessReason
    }
}
