import Foundation
@preconcurrency import FirebaseAuth

@MainActor
final class AuthenticationStateObservation {
    private var cancellation: (() -> Void)?

    init(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        cancellation?()
        cancellation = nil
    }
}

@MainActor
protocol AuthenticationStateObserving: AnyObject {
    var currentUser: AuthenticatedUser? { get }

    func observe(
        _ listener: @escaping @MainActor (AuthenticatedUser?) -> Void
    ) -> AuthenticationStateObservation
}

@MainActor
final class FirebaseAuthenticationStateObserver: AuthenticationStateObserving {
    var currentUser: AuthenticatedUser? {
        Auth.auth().currentUser.map(AuthenticatedUser.init(firebaseUser:))
    }

    func observe(
        _ listener: @escaping @MainActor (AuthenticatedUser?) -> Void
    ) -> AuthenticationStateObservation {
        let handle = Auth.auth().addStateDidChangeListener { _, user in
            let authenticatedUser = user.map(AuthenticatedUser.init(firebaseUser:))
            Task { @MainActor in
                listener(authenticatedUser)
            }
        }

        return AuthenticationStateObservation {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
}
