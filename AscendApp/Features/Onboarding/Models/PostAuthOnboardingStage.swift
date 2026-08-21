import Foundation

/// The post-auth onboarding stages, in order.
///
/// There is deliberately no name stage. App Review rejected 1.0 under Guideline 4
/// for asking a Sign in with Apple climber to type a name the framework already
/// supplies, and the answer is not a better-prefilled screen: the name is
/// resolved without asking (`SuppliedNameAdoption`), so the question has nothing
/// left to ask. The case is removed rather than the screen hidden behind a
/// condition, so no reachable state renders it.
///
/// `PostAuthOnboardingSnapshot` decodes stage identifiers it no longer knows by
/// dropping them, so removing a case here does not strand or reset a climber who
/// already stored one.
enum PostAuthOnboardingStage: String, CaseIterable, Codable, Identifiable {
    case stairStepperBaseline = "stair_stepper_baseline"
    case exerciseLevel = "exercise_level"
    case goal
    case motivation
    case plan
    case features
    case gender
    case age
    case weight
    case location
    case notifications
    case planLoading = "loading"
    case firstClimb = "first_climb"

    static let segmentID = "post_auth_onboarding"
    static let plannedStepCount = allCases.count

    static var allCases: [PostAuthOnboardingStage] {
        [
            .stairStepperBaseline,
            .exerciseLevel,
            .goal,
            .motivation,
            .plan,
            .features,
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
        .stairStepperBaseline
    }

    static var last: PostAuthOnboardingStage {
        allCases.last ?? first
    }

    var analyticsContext: OnboardingAnalyticsContext {
        OnboardingAnalyticsContext(
            segmentID: Self.segmentID,
            stepID: analyticsStepID
        )
    }

    /// `nil` for stages that render no screen of their own. `.features` is a container that hosts
    /// its own guide sub-screens, each of which reports its own view, so counting the container too
    /// would inflate the funnel with a screen the user never sees.
    var visibleScreenAnalyticsContext: OnboardingAnalyticsContext? {
        self == .features ? nil : analyticsContext
    }

    /// The opening stage has nothing behind it, so its leading control signs out
    /// instead of navigating - post-auth onboarding's only route back to the
    /// sign-in screen for a climber who signed into the wrong account.
    var leadingControl: OnboardingLeadingControl {
        self == Self.first ? .signOut : .back
    }

    var analyticsInputType: String {
        switch self {
        case .stairStepperBaseline, .exerciseLevel, .motivation, .plan:
            return "single_select"
        case .goal:
            return "multi_select"
        case .gender:
            return "single_select"
        case .age:
            return "date"
        case .weight:
            return "measurement"
        case .location:
            return "location"
        case .notifications:
            return "permission_prompt"
        case .features, .planLoading:
            return "automatic"
        case .firstClimb:
            return "single_select"
        }
    }

    var analyticsSelectionType: String? {
        switch self {
        case .stairStepperBaseline, .exerciseLevel, .motivation, .plan:
            return "single_select"
        case .goal:
            return "multi_select"
        case .gender, .notifications, .firstClimb:
            return "single_select"
        case .features, .age, .weight, .location, .planLoading:
            return nil
        }
    }

    private var analyticsStepID: String {
        self == .features ? "summit_landmarks" : rawValue
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
