import Foundation
@testable import AscendApp

extension OnboardingAnalyticsContext {
    /// A step of the post-sign-in questions 1.2 and earlier shipped. No build draws those screens
    /// now, but a pass persisted by one still reports under this segment and `flow_version=v1`.
    static func legacyPostAuth(_ stepID: String) -> OnboardingAnalyticsContext {
        OnboardingAnalyticsContext(segmentID: "post_auth_onboarding", stepID: stepID)
    }
}
