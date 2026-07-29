import Observation

@MainActor
@Observable
final class LandingScreenNavigationState {
    enum Destination: Hashable {
        case valueCarousel
        case signIn
    }

    var destination: Destination?

    func openValueCarousel() {
        destination = .valueCarousel
    }

    func openSignIn() {
        destination = .signIn
    }
}
