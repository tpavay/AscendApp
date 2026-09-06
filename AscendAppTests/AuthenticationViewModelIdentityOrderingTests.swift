import Testing
@testable import AscendApp

@MainActor
struct AuthenticationViewModelIdentityOrderingTests {
    @Test
    func authenticatedStateCannotPublishBeforeIdentityPreparation() {
        let monetizationManager = MonetizationIdentityManagerSpy()
        let viewModel = AuthenticationViewModel(
            monetizationIdentityManager: monetizationManager,
            observesFirebaseAuth: false
        )
        monetizationManager.authenticationState = {
            viewModel.authenticationState
        }

        viewModel.beginAuthenticatedSession(
            customer: MonetizationCustomerIdentity(
                userID: "returning-subscriber",
                email: "climber@example.com"
            ),
            initialState: .authenticated
        )

        #expect(monetizationManager.stateObservedDuringPreparation == .unauthenticated)
        #expect(monetizationManager.preparedCustomer?.userID == "returning-subscriber")
        #expect(viewModel.authenticationState == .authenticated)
    }

    /// The address the sign-in already supplied has to reach the identity claim, or the RevenueCat
    /// customer stays an opaque id that no support question can be answered against.
    @Test
    func signingInCarriesTheSuppliedEmailIntoTheIdentityClaim() async {
        let monetizationManager = MonetizationIdentityManagerSpy()
        let viewModel = AuthenticationViewModel(
            monetizationIdentityManager: monetizationManager,
            observesFirebaseAuth: false
        )

        viewModel.beginAuthenticatedSession(
            customer: MonetizationCustomerIdentity(
                userID: "returning-subscriber",
                email: "  climber@example.com  "
            ),
            initialState: .authenticated
        )
        await monetizationManager.waitForIdentification()

        #expect(monetizationManager.preparedCustomer?.email == "climber@example.com")
        #expect(monetizationManager.identifiedCustomer?.email == "climber@example.com")
    }

    /// A sign-in that supplied no address must claim the identity anyway. The account id is what
    /// makes the customer resolvable across devices, and it is not held hostage to the email.
    @Test
    func signingInWithoutAnEmailStillClaimsTheAccountIdentifier() async {
        let monetizationManager = MonetizationIdentityManagerSpy()
        let viewModel = AuthenticationViewModel(
            monetizationIdentityManager: monetizationManager,
            observesFirebaseAuth: false
        )

        viewModel.beginAuthenticatedSession(
            customer: MonetizationCustomerIdentity(userID: "no-email-climber", email: nil),
            initialState: .authenticated
        )
        await monetizationManager.waitForIdentification()

        #expect(monetizationManager.identifiedCustomer?.userID == "no-email-climber")
        #expect(monetizationManager.identifiedCustomer?.email == nil)
    }
}

@MainActor
private final class MonetizationIdentityManagerSpy: MonetizationIdentityManaging {
    var authenticationState: (() -> AuthenticationState)?
    private(set) var stateObservedDuringPreparation: AuthenticationState?
    private(set) var preparedCustomer: MonetizationCustomerIdentity?
    private(set) var identifiedCustomer: MonetizationCustomerIdentity?
    private var revision: UInt = 0

    func prepareIdentity(
        _ customer: MonetizationCustomerIdentity
    ) -> MonetizationIdentityTransition {
        stateObservedDuringPreparation = authenticationState?()
        preparedCustomer = customer
        revision &+= 1
        return MonetizationIdentityTransition(
            revision: revision,
            userID: customer.userID
        )
    }

    func identify(
        _ customer: MonetizationCustomerIdentity,
        transition: MonetizationIdentityTransition
    ) async {
        identifiedCustomer = customer
    }

    func prepareIdentityReset() -> MonetizationIdentityTransition {
        revision &+= 1
        return MonetizationIdentityTransition(
            revision: revision,
            userID: nil
        )
    }

    func resetIdentity(transition: MonetizationIdentityTransition) async {}

    /// Waits on the unstructured `Task` `beginAuthenticatedSession` starts. A claim that never
    /// arrives fails the assertion that follows rather than passing late.
    func waitForIdentification() async {
        for _ in 0..<1_000 {
            if identifiedCustomer != nil { return }
            await Task.yield()
        }
    }
}
