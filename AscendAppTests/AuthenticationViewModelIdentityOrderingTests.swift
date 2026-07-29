import Testing
@testable import AscendApp

@MainActor
struct AuthenticationViewModelIdentityOrderingTests {
    @Test
    func authenticatedStateCannotPublishBeforeIdentityPreparation() {
        let monetizationManager = MonetizationIdentityManagerSpy()
        let viewModel = AuthenticationViewModel(
            monetizationIdentityManager: monetizationManager,
            authenticationStateObserver: AuthenticationStateObserverStub()
        )
        monetizationManager.authenticationState = {
            viewModel.authenticationState
        }

        _ = viewModel.beginAuthenticatedSession(
            userID: "returning-subscriber",
            initialState: .authenticated
        )

        #expect(monetizationManager.stateObservedDuringPreparation == .unauthenticated)
        #expect(monetizationManager.preparedUserID == "returning-subscriber")
        #expect(viewModel.authenticatedUserID == "returning-subscriber")
        #expect(viewModel.authenticationState == .authenticated)
    }
}

@MainActor
private final class AuthenticationStateObserverStub: AuthenticationStateObserving {
    var currentUser: AuthenticatedUser? {
        nil
    }

    func observe(
        _ listener: @escaping @MainActor (AuthenticatedUser?) -> Void
    ) -> AuthenticationStateObservation {
        AuthenticationStateObservation {}
    }
}

@MainActor
private final class MonetizationIdentityManagerSpy: MonetizationIdentityManaging {
    var authenticationState: (() -> AuthenticationState)?
    private(set) var stateObservedDuringPreparation: AuthenticationState?
    private(set) var preparedUserID: String?
    private var revision: UInt = 0

    func prepareIdentity(userId: String) -> MonetizationIdentityTransition {
        stateObservedDuringPreparation = authenticationState?()
        preparedUserID = userId
        revision &+= 1
        return MonetizationIdentityTransition(
            revision: revision,
            userID: userId
        )
    }

    func identify(
        userId: String,
        transition: MonetizationIdentityTransition
    ) async {}

    func prepareIdentityReset() -> MonetizationIdentityTransition {
        revision &+= 1
        return MonetizationIdentityTransition(
            revision: revision,
            userID: nil
        )
    }

    func resetIdentity(transition: MonetizationIdentityTransition) async {}
}
