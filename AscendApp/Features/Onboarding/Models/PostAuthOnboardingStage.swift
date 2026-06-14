import Foundation

enum PostAuthOnboardingStage: String, CaseIterable, Codable, Identifiable {
    case displayName
    case stairStepperBaseline = "stair_stepper_baseline"
    case exerciseLevel = "exercise_level"
    case goal
    case motivation
    case plan
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
            .stairStepperBaseline,
            .exerciseLevel,
            .goal,
            .motivation,
            .plan,
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

    var analyticsEventName: String {
        switch self {
        case .displayName:
            return "name_inputted"
        case .stairStepperBaseline:
            return "stair_stepper_baseline_answered"
        case .exerciseLevel:
            return "exercise_level_answered"
        case .goal:
            return "goal_answered"
        case .motivation:
            return "motivation_answered"
        case .plan:
            return "plan_answered"
        case .gender:
            return "division_inputted"
        case .age:
            return "age_inputted"
        case .weight:
            return "body_metrics_inputted"
        case .location:
            return "location_inputted"
        case .notifications:
            return "notifications_inputted"
        case .planLoading:
            return "plan_loaded"
        case .firstClimb:
            return "first_climb_selected"
        }
    }

    var analyticsInputType: String {
        switch self {
        case .displayName:
            return "text"
        case .stairStepperBaseline, .exerciseLevel, .motivation, .plan:
            return "single_select"
        case .goal:
            return "multi_select"
        case .gender:
            return "single_select"
        case .age:
            return "number"
        case .weight:
            return "measurement"
        case .location:
            return "location"
        case .notifications:
            return "permission_prompt"
        case .planLoading:
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
        case .displayName, .age, .weight, .location, .planLoading:
            return nil
        }
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
