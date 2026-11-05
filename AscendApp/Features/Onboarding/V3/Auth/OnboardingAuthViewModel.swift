import Foundation
import Observation

/// What the sign-in screen needs that is not drawing: which of its two modes it is in.
@MainActor
@Observable
final class OnboardingAuthViewModel {
    enum Mode: Equatable {
        /// The last step of the flow: the example weekly board, the climber's empty row, two buttons.
        case claimSpot
        /// "Already climbing? Sign in" from the first screen: no board, then normal routing.
        case returning
    }

    let mode: Mode

    init(mode: Mode) {
        self.mode = mode
    }

    /// The two ways in. A climber who reached the sign-in screen from the first screen is a
    /// returning one, and so is one who asked to be: the paywall's "Already climbing? Sign in" goes
    /// through the same step as a purchase does, so the step it came from cannot tell them apart.
    static func mode(
        arrivedFrom previous: OnboardingV3Step?,
        returningRequest: OnboardingAuthReturningRequest = OnboardingAuthReturningRequest()
    ) -> Mode {
        previous == .welcome || returningRequest.isSet ? .returning : .claimSpot
    }
}
