import Foundation

/// Which of its two modes the sign-in screen opens in.
enum OnboardingAuthMode: Equatable {
    /// The step after the last setup screen: the example weekly board, the climber's empty row, two
    /// buttons.
    case claimSpot
    /// "Already have an account? Sign in", from the first screen: no board, then normal routing.
    case returning

    /// A climber who reached the sign-in screen from the first screen is a returning one.
    init(arrivedFrom previous: OnboardingV3Step?) {
        self = previous == .welcome ? .returning : .claimSpot
    }
}
