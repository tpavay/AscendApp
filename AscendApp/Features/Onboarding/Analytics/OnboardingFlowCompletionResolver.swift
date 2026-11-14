import Foundation

enum OnboardingFlowCompletionResolver {
    static func completionReason(
        rootRoute: AppRootRoute,
        confirmedAccessReason: OnboardingFlowCompletionReason?
    ) -> OnboardingFlowCompletionReason? {
        guard rootRoute == .mainApp else {
            return nil
        }

        return confirmedAccessReason
    }
}
