import Foundation

/// Which of its two modes the sign-in screen opens in.
enum OnboardingAuthMode: Equatable {
    /// The step after the last setup screen: what saves to the account, as the flow collected it,
    /// and two buttons.
    case saveEveryClimb
    /// "Already have an account? Sign in", from the first screen: no list, then normal routing.
    case returning

    /// A climber who reached the sign-in screen from the first screen is a returning one.
    init(arrivedFrom previous: OnboardingV3Step?) {
        self = previous == .welcome ? .returning : .saveEveryClimb
    }
}
