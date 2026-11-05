import Foundation

/// Every screen of the pre-sign-in onboarding flow, in the order the funnel counts them.
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
    case climberCard = "climber_card"
    case claimCity = "claim_city"
    case weeklyTarget = "weekly_target"
    case thisMonthEvent = "this_month_event"
    case notificationPrimer = "notification_primer"
    case paywall
    case exitGift = "exit_gift"
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
        case .climberCard: "Set up your climber card"
        case .claimCity: "Claim your city"
        case .weeklyTarget: "How many days a week?"
        case .thisMonthEvent: "This month's live event"
        case .notificationPrimer: "We'll keep you on track"
        case .paywall: "Never climb a boring minute again"
        case .exitGift: "Open your welcome gift"
        case .auth: "Claim your spot on the board"
        }
    }

    /// Where the screen's primary action leads. `nil` for the last step, which ends the flow.
    ///
    /// The two Health steps and the usual-climb step form one branch: connecting walks
    /// `healthConnect -> healthPermission -> healthHistory`, and everything that leaves Health
    /// behind lands on `usualClimb`. Both ends meet again at `climberCard`.
    var primaryDestination: OnboardingV3Step? {
        switch self {
        case .welcome: .goHarder
        case .goHarder: .getBetter
        case .getBetter: .somethingToChase
        case .somethingToChase: .countMethods
        case .countMethods: .healthConnect
        case .healthConnect: .healthPermission
        case .healthPermission: .healthHistory
        case .healthHistory: .climberCard
        case .usualClimb: .climberCard
        case .climberCard: .claimCity
        case .claimCity: .weeklyTarget
        case .weeklyTarget: .thisMonthEvent
        case .thisMonthEvent: .notificationPrimer
        case .notificationPrimer: .paywall
        case .paywall: .auth
        case .exitGift: .auth
        case .auth: nil
        }
    }

    /// The screen's other exits, in the order the design offers them.
    var alternateExits: [OnboardingV3Exit] {
        switch self {
        case .welcome:
            [OnboardingV3Exit(prompt: "Already have an account? ", action: "Sign in", destination: .auth)]
        case .healthConnect:
            [OnboardingV3Exit(action: "I don't track workouts", destination: .usualClimb)]
        case .healthPermission:
            [OnboardingV3Exit(action: "No stair stepper workouts found", destination: .usualClimb)]
        case .paywall:
            [OnboardingV3Exit(action: "Close", destination: .exitGift)]
        case .exitGift:
            [OnboardingV3Exit(action: "No thanks", destination: .paywall)]
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
