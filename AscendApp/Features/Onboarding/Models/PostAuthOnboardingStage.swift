import Foundation

enum PostAuthOnboardingStage: String, CaseIterable, Codable, Identifiable {
    case displayName
    case gender
    case age
    case weight
    case location
    case notifications
    case planLoading = "loading"
    case firstClimb = "first_climb"

    static let flowID = "post_auth_onboarding"
    static let plannedStepCount = allCases.count

    static var allCases: [PostAuthOnboardingStage] {
        [
            .displayName,
            .gender,
            .age,
            .weight,
            .location,
            .notifications,
            .planLoading,
            .firstClimb
        ]
    }

    var id: String { rawValue }

    var next: PostAuthOnboardingStage? {
        let stages = Self.allCases
        guard let currentIndex = stages.firstIndex(of: self) else { return nil }
        let nextIndex = stages.index(after: currentIndex)
        return nextIndex < stages.endIndex ? stages[nextIndex] : nil
    }

    var progressIndex: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    static var first: PostAuthOnboardingStage {
        .displayName
    }

    var analyticsContext: OnboardingAnalyticsContext {
        OnboardingAnalyticsContext(
            flowID: Self.flowID,
            stepID: rawValue,
            stepIndex: progressIndex,
            stepCount: Self.plannedStepCount
        )
    }

    var screenViewProperty: String {
        rawValue
    }
}

enum PostAuthOnboardingPhase: Equatable {
    case signedOut
    case resolving
    case onboarding(PostAuthOnboardingStage)
    case complete
}

extension Notification.Name {
    static let postAuthOnboardingStateDidChange = Notification.Name("postAuthOnboardingStateDidChange")
}
