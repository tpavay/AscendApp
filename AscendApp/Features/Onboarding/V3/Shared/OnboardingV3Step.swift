import Foundation

/// Every screen of the onboarding flow, in the order the funnel counts them: the selling and setup
/// screens, then sign-in, which ends the flow. What a climber without access sees next is the
/// app-access paywall, a Superwall paywall configured in the dashboard, not a step of this flow.
///
/// The raw value is the analytics `step_id`; it must match
/// ``OnboardingAnalyticsContext/orderedStepIDs`` exactly, which
/// `OnboardingV3KitTests.theHandWrittenFunnelOrderMatchesTheStepEnum` holds.
/// Funnels read a branch by `step_id`, so a branch is never a different step list.
enum OnboardingV3Step: String, CaseIterable, Sendable, Hashable {
    case welcome
    case goHarder = "go_harder"
    case getBetter = "get_better"
    case somethingToChase = "something_to_chase"
    case countMethods = "count_methods"
    case healthConnect = "health_connect"
    case healthPermission = "health_permission"
    case healthHistory = "health_history"
    case usualClimb = "usual_climb"
    /// 08. The raw value is the analytics `step_id` and keeps its first name: the screen was the
    /// climber card before it was the profile screen, and a funnel reads a step by this id.
    case profileSetup = "climber_card"
    case claimCity = "claim_city"
    case weeklyTarget = "weekly_target"
    case thisMonthEvent = "this_month_event"
    case notificationPrimer = "notification_primer"
    case auth

    var analyticsID: String { rawValue }

    /// What the screen is, for the stub, accessibility and debugging. Never shown by a real screen,
    /// which owns its own copy.
    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .goHarder: "Go harder than you would alone"
        case .getBetter: "See yourself get better"
        case .somethingToChase: "Always something to chase next"
        case .countMethods: "Climb with what you've got"
        case .healthConnect: "Your workouts, counted for you"
        case .healthPermission: "Two taps and you're set"
        case .healthHistory: "We found your climbs"
        case .usualClimb: "How long is a usual climb?"
        case .profileSetup: "Set up your profile"
        case .claimCity: "Claim your city"
        case .weeklyTarget: "How many days a week?"
        case .thisMonthEvent: "This month's live event"
        case .notificationPrimer: "We'll keep you on track"
        case .auth: "Save every climb"
        }
    }

    /// Where the screen's primary action leads. `nil` for sign-in, which ends the flow on its own:
    /// the root moves on when the account appears, and no tap on the screen is the way out.
    ///
    /// The two Health steps and the usual-climb step form one branch: connecting walks
    /// `healthConnect -> healthPermission -> healthHistory`, and everything that leaves Health
    /// behind lands on `usualClimb`. Both ends meet again at `profileSetup`.
    var primaryDestination: OnboardingV3Step? {
        switch self {
        case .welcome: .goHarder
        case .goHarder: .getBetter
        case .getBetter: .somethingToChase
        case .somethingToChase: .countMethods
        case .countMethods: .healthConnect
        case .healthConnect: .healthPermission
        case .healthPermission: .healthHistory
        case .healthHistory: .profileSetup
        case .usualClimb: .profileSetup
        case .profileSetup: .claimCity
        case .claimCity: .weeklyTarget
        case .weeklyTarget: .thisMonthEvent
        case .thisMonthEvent: .notificationPrimer
        case .notificationPrimer: .auth
        case .auth: nil
        }
    }

    /// The screen's other exits, in the order the design offers them.
    var alternateExits: [OnboardingV3Exit] {
        switch self {
        case .welcome:
            [OnboardingV3Exit(prompt: "Already have an account? ", action: "Sign in", destination: .auth)]
        case .healthConnect:
            [OnboardingV3Exit(action: "Skip", destination: .usualClimb)]
        case .healthPermission:
            [OnboardingV3Exit(action: "No stair stepper workouts found", destination: .usualClimb)]
        default:
            []
        }
    }
}

struct OnboardingV3Exit: Equatable, Sendable {
    /// The words leading into the action, which a screen may draw quieter than the action.
    var prompt = ""
    let action: String
    let destination: OnboardingV3Step

    var title: String { prompt + action }
}
