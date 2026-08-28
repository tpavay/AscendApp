import Foundation
import RevenueCat
import Testing
@testable import AscendApp

/// The exact error `Purchases.logOut()` raises when the app user is already anonymous.
private let anonymousLogOutRefusal = NSError(
    domain: ErrorCode.errorDomain,
    code: ErrorCode.logOutAnonymousUserError.rawValue
)

@MainActor
struct RevenueCatEntitlementServiceTests {
    @Test
    func refreshDuringIdentifyCannotReadOrPublishThePriorIdentity() async throws {
        let provider = ControlledRevenueCatEntitlementProvider()
        var invocations = provider.invocations.makeAsyncIterator()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let identity = service.prepareIdentity(.climber("subscriber"))
        let identifyTask = Task {
            await service.identify(.climber("subscriber"), transition: identity)
        }
        #expect(await invocations.next() == .logIn(userID: "subscriber"))

        await service.refreshCustomerInfo()

        #expect(provider.customerInfoCallCount == 0)
        #expect(service.entitlementState == .unknown)

        provider.completeLogIn(with: .active(["app_access"]))
        await identifyTask.value

        #expect(service.entitlementState == .active(["app_access"]))
    }

    @Test
    func providerIdentityMutationsConvergeOnNewestDesiredUser() async throws {
        let provider = ControlledRevenueCatEntitlementProvider()
        var invocations = provider.invocations.makeAsyncIterator()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let reset = service.prepareIdentityReset()
        let resetTask = Task {
            await service.resetIdentity(transition: reset)
        }
        #expect(await invocations.next() == .logOut)

        let supersededIdentity = service.prepareIdentity(.climber("superseded-user"))
        let supersededIdentifyTask = Task {
            await service.identify(
                .climber("superseded-user"),
                transition: supersededIdentity
            )
        }
        let currentIdentity = service.prepareIdentity(.climber("current-user"))
        let identifyTask = Task {
            await service.identify(.climber("current-user"), transition: currentIdentity)
        }

        provider.completeLogOut(with: .inactive)
        #expect(await invocations.next() == .logIn(userID: "current-user"))
        provider.completeLogIn(with: .active(["app_access"]))

        await resetTask.value
        await supersededIdentifyTask.value
        await identifyTask.value

        #expect(provider.completedIdentityMutations == [.logOut, .logIn(userID: "current-user")])
        #expect(service.entitlementState == .active(["app_access"]))
        #expect(service.scheduledIdentityMutationCount == 0)
    }

    @Test
    func identifyFailureRemainsUnknownAndRoutingKeepsResolving() async throws {
        let provider = ControlledRevenueCatEntitlementProvider()
        var invocations = provider.invocations.makeAsyncIterator()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let identity = service.prepareIdentity(.climber("subscriber"))
        let identifyTask = Task {
            await service.identify(.climber("subscriber"), transition: identity)
        }
        #expect(await invocations.next() == .logIn(userID: "subscriber"))
        provider.failLogIn()
        await identifyTask.value

        let route = AppRootRouteResolver.resolve(
            updatePresentation: nil,
            authenticationState: .authenticated,
            userId: "subscriber",
            postAuthOnboardingPhase: .complete,
            entitlementState: service.entitlementState,
            requiredEntitlementID: "app_access"
        )

        #expect(service.entitlementState == .unknown)
        #expect(route == .resolving)
        #expect(service.hasFailedIdentityResolution)
    }

    @Test
    func retryAfterIdentifyFailureAdmitsTheActiveSubscriber() async throws {
        let provider = ControlledRevenueCatEntitlementProvider()
        var invocations = provider.invocations.makeAsyncIterator()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let identity = service.prepareIdentity(.climber("subscriber"))
        let identifyTask = Task {
            await service.identify(.climber("subscriber"), transition: identity)
        }
        #expect(await invocations.next() == .logIn(userID: "subscriber"))
        provider.failLogIn()
        await identifyTask.value
        #expect(service.hasFailedIdentityResolution)

        let retryTask = Task {
            await service.retryIdentityResolution()
        }
        #expect(await invocations.next() == .logIn(userID: "subscriber"))
        provider.completeLogIn(with: .active(["app_access"]))
        await retryTask.value

        let route = AppRootRouteResolver.resolve(
            updatePresentation: nil,
            authenticationState: .authenticated,
            userId: "subscriber",
            postAuthOnboardingPhase: .complete,
            entitlementState: service.entitlementState,
            requiredEntitlementID: "app_access"
        )

        #expect(service.entitlementState == .active(["app_access"]))
        #expect(!service.hasFailedIdentityResolution)
        #expect(route == .mainApp)
    }

    @Test
    func retryIsIgnoredWhileIdentityResolutionIsStillOutstanding() async throws {
        let provider = ControlledRevenueCatEntitlementProvider()
        var invocations = provider.invocations.makeAsyncIterator()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let identity = service.prepareIdentity(.climber("subscriber"))
        let identifyTask = Task {
            await service.identify(.climber("subscriber"), transition: identity)
        }
        #expect(await invocations.next() == .logIn(userID: "subscriber"))

        await service.retryIdentityResolution()
        #expect(service.scheduledIdentityMutationCount == 1)

        provider.completeLogIn(with: .active(["app_access"]))
        await identifyTask.value

        #expect(service.entitlementState == .active(["app_access"]))
        #expect(provider.completedIdentityMutations == [.logIn(userID: "subscriber")])
    }

    /// The whole point of the change: a customer created after this ships is a person, not an
    /// opaque `$RCAnonymous...` id. The account identifier is claimed first and the address the
    /// sign-in already supplied lands on the customer that log-in just settled on - in that order,
    /// because a subscriber attribute attaches to whichever app user RevenueCat currently holds.
    @Test
    func signingInIdentifiesTheCustomerThenAttachesTheSuppliedEmail() async throws {
        let provider = ControlledRevenueCatEntitlementProvider()
        var invocations = provider.invocations.makeAsyncIterator()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let customer = MonetizationCustomerIdentity(
            userID: "subscriber",
            email: "climber@example.com"
        )
        let identity = service.prepareIdentity(customer)
        let identifyTask = Task {
            await service.identify(customer, transition: identity)
        }
        #expect(await invocations.next() == .logIn(userID: "subscriber"))

        // Nothing is attached until RevenueCat has actually moved onto this customer.
        #expect(provider.completedIdentityMutations == [])

        provider.completeLogIn(with: .active(["app_access"]))
        await identifyTask.value

        #expect(
            provider.completedIdentityMutations == [
                .logIn(userID: "subscriber"),
                .setEmail("climber@example.com")
            ]
        )
    }

    /// Not knowing an address is not the same as knowing there is none. A sign-in that supplied
    /// nothing still claims the account identifier, and writes no attribute at all - blanking one
    /// would erase the very thing that made an earlier customer identifiable.
    @Test
    func signingInWithoutAnEmailWritesNoAttribute() async throws {
        let provider = ControlledRevenueCatEntitlementProvider()
        var invocations = provider.invocations.makeAsyncIterator()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let identity = service.prepareIdentity(.climber("subscriber"))
        let identifyTask = Task {
            await service.identify(.climber("subscriber"), transition: identity)
        }
        #expect(await invocations.next() == .logIn(userID: "subscriber"))
        provider.completeLogIn(with: .active(["app_access"]))
        await identifyTask.value

        #expect(provider.completedIdentityMutations == [.logIn(userID: "subscriber")])
    }

    /// A log-in that never settled leaves the app on whatever customer it already held, so
    /// attaching an address there would stamp one climber's email onto another's record.
    @Test
    func aFailedSignInAttachesNothing() async throws {
        let provider = ControlledRevenueCatEntitlementProvider()
        var invocations = provider.invocations.makeAsyncIterator()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let customer = MonetizationCustomerIdentity(
            userID: "subscriber",
            email: "climber@example.com"
        )
        let identity = service.prepareIdentity(customer)
        let identifyTask = Task {
            await service.identify(customer, transition: identity)
        }
        #expect(await invocations.next() == .logIn(userID: "subscriber"))
        provider.failLogIn()
        await identifyTask.value

        #expect(provider.completedIdentityMutations == [])
        #expect(service.entitlementState == .unknown)
    }

    /// Two climbers, one device. Each address has to reach its own customer, which holds only
    /// because the identity mutations are serialized: the second log-in cannot start until the
    /// first has finished attaching. Signing out clears nothing - the departing climber's address
    /// belongs on the departing climber's own customer, and log-out moves the app onto a fresh
    /// anonymous customer that never carried one.
    @Test
    func switchingAccountsAttachesEachAddressToItsOwnCustomer() async throws {
        let provider = ControlledRevenueCatEntitlementProvider()
        var invocations = provider.invocations.makeAsyncIterator()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let first = MonetizationCustomerIdentity(userID: "climber-a", email: "a@example.com")
        let firstIdentity = service.prepareIdentity(first)
        let firstIdentifyTask = Task {
            await service.identify(first, transition: firstIdentity)
        }
        #expect(await invocations.next() == .logIn(userID: "climber-a"))
        provider.completeLogIn(with: .active(["app_access"]))
        await firstIdentifyTask.value

        let reset = service.prepareIdentityReset()
        let resetTask = Task {
            await service.resetIdentity(transition: reset)
        }
        #expect(await invocations.next() == .logOut)
        provider.completeLogOut(with: .inactive)
        await resetTask.value

        let second = MonetizationCustomerIdentity(userID: "climber-b", email: "b@example.com")
        let secondIdentity = service.prepareIdentity(second)
        let secondIdentifyTask = Task {
            await service.identify(second, transition: secondIdentity)
        }
        #expect(await invocations.next() == .logIn(userID: "climber-b"))
        provider.completeLogIn(with: .inactive)
        await secondIdentifyTask.value

        #expect(
            provider.completedIdentityMutations == [
                .logIn(userID: "climber-a"),
                .setEmail("a@example.com"),
                .logOut,
                .logIn(userID: "climber-b"),
                .setEmail("b@example.com")
            ]
        )
    }

    @Test
    func delayedRefreshCannotOverwriteNewIdentity() async throws {
        let provider = ControlledRevenueCatEntitlementProvider()
        var invocations = provider.invocations.makeAsyncIterator()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let firstIdentity = service.prepareIdentity(.climber("first-user"))
        let firstIdentifyTask = Task {
            await service.identify(.climber("first-user"), transition: firstIdentity)
        }
        #expect(await invocations.next() == .logIn(userID: "first-user"))
        provider.completeLogIn(with: .active(["app_access"]))
        await firstIdentifyTask.value

        let staleRefreshTask = Task {
            await service.refreshCustomerInfo()
        }
        #expect(await invocations.next() == .customerInfo)

        let currentIdentity = service.prepareIdentity(.climber("current-user"))
        let currentIdentifyTask = Task {
            await service.identify(.climber("current-user"), transition: currentIdentity)
        }
        #expect(await invocations.next() == .logIn(userID: "current-user"))
        provider.completeLogIn(with: .active(["app_access"]))
        await currentIdentifyTask.value

        provider.completeCustomerInfo(with: .inactive)
        await staleRefreshTask.value

        #expect(service.entitlementState == .active(["app_access"]))
    }

    @Test
    func customerInfoUpdateAppliesItsOwnPayloadWithoutAnotherFetch() async throws {
        let provider = ControlledRevenueCatEntitlementProvider()
        var invocations = provider.invocations.makeAsyncIterator()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let identity = service.prepareIdentity(.climber("subscriber"))
        let identifyTask = Task {
            await service.identify(.climber("subscriber"), transition: identity)
        }
        #expect(await invocations.next() == .logIn(userID: "subscriber"))
        provider.completeLogIn(with: .active(["app_access"]))
        await identifyTask.value

        provider.sendCustomerInfoUpdate(with: .inactive)
        await settle(until: { service.entitlementState == .inactive })

        #expect(service.entitlementState == .inactive)
        #expect(provider.customerInfoCallCount == 0)
    }

    @Test
    func failedRefreshKeepsTheResolvedEntitlement() async throws {
        let provider = ControlledRevenueCatEntitlementProvider()
        var invocations = provider.invocations.makeAsyncIterator()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let identity = service.prepareIdentity(.climber("subscriber"))
        let identifyTask = Task {
            await service.identify(.climber("subscriber"), transition: identity)
        }
        #expect(await invocations.next() == .logIn(userID: "subscriber"))
        provider.completeLogIn(with: .active(["app_access"]))
        await identifyTask.value

        let refreshTask = Task {
            await service.refreshCustomerInfo()
        }
        #expect(await invocations.next() == .customerInfo)
        provider.failCustomerInfo()
        await refreshTask.value

        let route = AppRootRouteResolver.resolve(
            updatePresentation: nil,
            authenticationState: .authenticated,
            userId: "subscriber",
            postAuthOnboardingPhase: .complete,
            entitlementState: service.entitlementState,
            requiredEntitlementID: "app_access"
        )

        #expect(service.entitlementState == .active(["app_access"]))
        #expect(!service.hasFailedIdentityResolution)
        #expect(route == .mainApp)
    }

    /// A signed-out cold start resets identity for an app user RevenueCat already treats as
    /// anonymous. The state fed to the service here is the one the real provider derives from that
    /// refusal, so if the translation ever stops recognising it this test fails rather than letting a
    /// doomed logout re-run on every refresh.
    @Test
    func theAnonymousLogOutRefusalResolvesTheResetAndStopsRerunningIt() async throws {
        let provider = ControlledRevenueCatEntitlementProvider()
        var invocations = provider.invocations.makeAsyncIterator()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let refusalState = try #require(
            RevenueCatPurchasesProvider.resolvedState(
                forLogOutError: anonymousLogOutRefusal
            ),
            "RevenueCat's already-anonymous logout refusal must resolve to a known state"
        )

        let reset = service.prepareIdentityReset()
        let resetTask = Task {
            await service.resetIdentity(transition: reset)
        }
        #expect(await invocations.next() == .logOut)
        provider.completeLogOut(with: refusalState)
        await resetTask.value

        #expect(service.entitlementState == .inactive)
        #expect(!service.hasFailedIdentityResolution)

        let refreshTask = Task {
            await service.refreshCustomerInfo()
        }
        #expect(await invocations.next() == .customerInfo)
        provider.completeCustomerInfo(with: .inactive)
        await refreshTask.value

        #expect(provider.customerInfoCallCount == 1)
    }

    @Test
    func genuineLogOutFailureStillLeavesResolutionUnanswered() async throws {
        let provider = ControlledRevenueCatEntitlementProvider()
        var invocations = provider.invocations.makeAsyncIterator()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let reset = service.prepareIdentityReset()
        let resetTask = Task {
            await service.resetIdentity(transition: reset)
        }
        #expect(await invocations.next() == .logOut)
        provider.failLogOut()
        await resetTask.value

        #expect(service.entitlementState == .unknown)
        #expect(service.hasFailedIdentityResolution)
    }

    // MARK: - What the refresh actually established

    @Test
    func anUnconfiguredRefreshReportsThatNothingCouldBeAsked() async {
        let service = RevenueCatEntitlementService(
            provider: ControlledRevenueCatEntitlementProvider(),
            startsConfigured: false
        )

        let refresh = await service.refreshCustomerInfo()

        #expect(refresh == .unavailable(.notConfigured))
    }

    @Test
    func aRefreshWithNoSettledIdentityReportsItUnresolvedRatherThanEmpty() async {
        let provider = ControlledRevenueCatEntitlementProvider()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let refresh = await service.refreshCustomerInfo()

        #expect(refresh == .unavailable(.identityUnresolved))
        #expect(provider.customerInfoCallCount == 0)
    }

    /// The background pass must not block on a sign-in, so it reports the identity as unresolved
    /// instead of reading the transitional `.unknown` as an answer.
    @Test
    func aNonWaitingRefreshDuringAnIdentityMutationReportsItUnresolved() async throws {
        let provider = ControlledRevenueCatEntitlementProvider()
        var invocations = provider.invocations.makeAsyncIterator()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let identity = service.prepareIdentity(.climber("subscriber"))
        let identifyTask = Task {
            await service.identify(.climber("subscriber"), transition: identity)
        }
        #expect(await invocations.next() == .logIn(userID: "subscriber"))

        let refresh = await service.refreshCustomerInfo()

        #expect(refresh == .unavailable(.identityUnresolved))
        #expect(provider.customerInfoCallCount == 0)

        provider.completeLogIn(with: .active(["app_access"]))
        await identifyTask.value
    }

    /// The purchase verdict waits the sign-in out instead of reporting the transitional `.unknown`,
    /// which would fail a charged, successful purchase.
    @Test
    func aWaitingRefreshOutlastsAnInFlightIdentityAndReturnsTheRealAnswer() async throws {
        let provider = ControlledRevenueCatEntitlementProvider()
        var invocations = provider.invocations.makeAsyncIterator()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let identity = service.prepareIdentity(.climber("subscriber"))
        let identifyTask = Task {
            await service.identify(.climber("subscriber"), transition: identity)
        }
        #expect(await invocations.next() == .logIn(userID: "subscriber"))

        let refreshTask = Task {
            await service.refreshCustomerInfo(waitsForPendingIdentity: true)
        }

        provider.completeLogIn(with: .active(["app_access"]))
        await identifyTask.value

        #expect(await invocations.next() == .customerInfo)
        provider.completeCustomerInfo(with: .active(["app_access"]))

        #expect(await refreshTask.value == .refreshed(.active(["app_access"])))
    }

    /// Waiting is not the same as inventing an answer: an identity mutation that never resolves
    /// still leaves the refresh with nothing current to report.
    @Test
    func aWaitingRefreshStillReportsUnresolvedWhenTheIdentityNeverResolves() async throws {
        let provider = ControlledRevenueCatEntitlementProvider()
        var invocations = provider.invocations.makeAsyncIterator()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let identity = service.prepareIdentity(.climber("subscriber"))
        let identifyTask = Task {
            await service.identify(.climber("subscriber"), transition: identity)
        }
        #expect(await invocations.next() == .logIn(userID: "subscriber"))

        let refreshTask = Task {
            await service.refreshCustomerInfo(waitsForPendingIdentity: true)
        }

        provider.failLogIn()
        await identifyTask.value

        #expect(await refreshTask.value == .unavailable(.identityUnresolved))
        #expect(provider.customerInfoCallCount == 0)
        #expect(service.hasFailedIdentityResolution)
    }

    @Test
    func aFailedRefreshReportsTheFailureInsteadOfTheStaleEntitlement() async throws {
        let provider = ControlledRevenueCatEntitlementProvider()
        var invocations = provider.invocations.makeAsyncIterator()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let identity = service.prepareIdentity(.climber("subscriber"))
        let identifyTask = Task {
            await service.identify(.climber("subscriber"), transition: identity)
        }
        #expect(await invocations.next() == .logIn(userID: "subscriber"))
        provider.completeLogIn(with: .active(["app_access"]))
        await identifyTask.value

        let refreshTask = Task {
            await service.refreshCustomerInfo()
        }
        #expect(await invocations.next() == .customerInfo)
        provider.failCustomerInfo()

        #expect(await refreshTask.value == .unavailable(.providerFailed))
        #expect(service.entitlementState == .active(["app_access"]))
    }

    /// The identity can move on while `customerInfoState()` is suspended. The answer that lands
    /// then belongs to a superseded identity, and the service refuses it - so the refresh must
    /// refuse it too rather than handing a purchase verdict an entitlement the app does not hold.
    @Test
    func anAnswerTheServiceRefusesIsNeverReportedAsRefreshed() async throws {
        let provider = ControlledRevenueCatEntitlementProvider()
        var invocations = provider.invocations.makeAsyncIterator()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let firstIdentity = service.prepareIdentity(.climber("first-user"))
        let firstIdentifyTask = Task {
            await service.identify(.climber("first-user"), transition: firstIdentity)
        }
        #expect(await invocations.next() == .logIn(userID: "first-user"))
        provider.completeLogIn(with: .active(["app_access"]))
        await firstIdentifyTask.value

        let refreshTask = Task {
            await service.refreshCustomerInfo()
        }
        #expect(await invocations.next() == .customerInfo)

        let switchedIdentity = service.prepareIdentity(.climber("switched-user"))
        let switchedIdentifyTask = Task {
            await service.identify(.climber("switched-user"), transition: switchedIdentity)
        }
        #expect(await invocations.next() == .logIn(userID: "switched-user"))

        provider.completeCustomerInfo(with: .active(["app_access"]))

        #expect(await refreshTask.value == .unavailable(.identityUnresolved))
        #expect(service.entitlementState == .unknown)

        provider.completeLogIn(with: .inactive)
        await switchedIdentifyTask.value
    }

    /// A background pass must not stall a launch or foreground chain on identity work whose answer
    /// it then discards, and must not re-drive a mutation `retryIdentityResolution` owns.
    @Test
    func aBackgroundRefreshNeitherWaitsForNorReDrivesAStalledIdentity() async throws {
        let provider = ControlledRevenueCatEntitlementProvider()
        var invocations = provider.invocations.makeAsyncIterator()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let identity = service.prepareIdentity(.climber("subscriber"))
        let identifyTask = Task {
            await service.identify(.climber("subscriber"), transition: identity)
        }
        #expect(await invocations.next() == .logIn(userID: "subscriber"))
        provider.failLogIn()
        await identifyTask.value
        #expect(service.hasFailedIdentityResolution)

        let refresh = await service.refreshCustomerInfo()

        #expect(refresh == .unavailable(.identityUnresolved))
        #expect(provider.customerInfoCallCount == 0)
        #expect(provider.completedIdentityMutations == [])
        #expect(service.scheduledIdentityMutationCount == 0)
    }

    /// The verdict pass does re-drive it, because a purchase landing mid sign-in has a real answer
    /// waiting behind that mutation.
    @Test
    func aWaitingRefreshReDrivesAStalledIdentityAndThenAsksRevenueCat() async throws {
        let provider = ControlledRevenueCatEntitlementProvider()
        var invocations = provider.invocations.makeAsyncIterator()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let identity = service.prepareIdentity(.climber("subscriber"))
        let identifyTask = Task {
            await service.identify(.climber("subscriber"), transition: identity)
        }
        #expect(await invocations.next() == .logIn(userID: "subscriber"))
        provider.failLogIn()
        await identifyTask.value

        let refreshTask = Task {
            await service.refreshCustomerInfo(waitsForPendingIdentity: true)
        }
        #expect(await invocations.next() == .logIn(userID: "subscriber"))
        provider.completeLogIn(with: .active(["app_access"]))

        #expect(await invocations.next() == .customerInfo)
        provider.completeCustomerInfo(with: .active(["app_access"]))

        #expect(await refreshTask.value == .refreshed(.active(["app_access"])))
    }

    @Test
    func aGenuineRefreshReportsExactlyWhatRevenueCatAnswered() async throws {
        let provider = ControlledRevenueCatEntitlementProvider()
        var invocations = provider.invocations.makeAsyncIterator()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let identity = service.prepareIdentity(.climber("subscriber"))
        let identifyTask = Task {
            await service.identify(.climber("subscriber"), transition: identity)
        }
        #expect(await invocations.next() == .logIn(userID: "subscriber"))
        provider.completeLogIn(with: .active(["app_access"]))
        await identifyTask.value

        let refreshTask = Task {
            await service.refreshCustomerInfo()
        }
        #expect(await invocations.next() == .customerInfo)
        provider.completeCustomerInfo(with: .inactive)

        #expect(await refreshTask.value == .refreshed(.inactive))
        #expect(service.entitlementState == .inactive)
    }
}

/// Hands the cooperative pool enough turns for the service's stream consumer to run. Bounded, so a
/// regression fails the expectation instead of hanging the suite.
@MainActor
private func settle(until condition: () -> Bool) async {
    for _ in 0..<100 {
        if condition() { return }
        await Task.yield()
    }
}

private enum RevenueCatProviderInvocation: Equatable {
    case customerInfo
    case logIn(userID: String)
    case setEmail(String)
    case logOut
    case restore
}

@MainActor
private final class ControlledRevenueCatEntitlementProvider: RevenueCatEntitlementProviding {
    private(set) var customerInfoCallCount = 0
    private(set) var completedIdentityMutations: [RevenueCatProviderInvocation] = []

    lazy var invocations = AsyncStream<RevenueCatProviderInvocation> { continuation in
        invocationContinuation = continuation
    }

    lazy var customerInfoUpdates = AsyncStream<MonetizationEntitlementState> { continuation in
        customerInfoUpdateContinuation = continuation
    }

    private var invocationContinuation: AsyncStream<RevenueCatProviderInvocation>.Continuation?
    private var customerInfoUpdateContinuation: AsyncStream<MonetizationEntitlementState>.Continuation?
    private var customerInfoContinuation: CheckedContinuation<
        MonetizationEntitlementState,
        any Error
    >?
    private var logInContinuation: CheckedContinuation<
        MonetizationEntitlementState,
        any Error
    >?
    private var logOutContinuation: CheckedContinuation<
        MonetizationEntitlementState,
        any Error
    >?
    private var restoreContinuation: CheckedContinuation<
        MonetizationEntitlementState,
        any Error
    >?

    func customerInfoState() async throws -> MonetizationEntitlementState {
        customerInfoCallCount += 1
        invocationContinuation?.yield(.customerInfo)
        return try await withCheckedThrowingContinuation { continuation in
            customerInfoContinuation = continuation
        }
    }

    func logInState(userID: String) async throws -> MonetizationEntitlementState {
        invocationContinuation?.yield(.logIn(userID: userID))
        let state = try await withCheckedThrowingContinuation { continuation in
            logInContinuation = continuation
        }
        completedIdentityMutations.append(.logIn(userID: userID))
        return state
    }

    /// Recorded only in `completedIdentityMutations`. It is a local store write with no round trip
    /// to wait on, so putting it in the invocation stream would only make every test that steps
    /// through log-ins consume a turn for it.
    func setCustomerEmail(_ email: String) {
        completedIdentityMutations.append(.setEmail(email))
    }

    func logOutState() async throws -> MonetizationEntitlementState {
        invocationContinuation?.yield(.logOut)
        let state = try await withCheckedThrowingContinuation { continuation in
            logOutContinuation = continuation
        }
        completedIdentityMutations.append(.logOut)
        return state
    }

    func restorePurchasesState() async throws -> MonetizationEntitlementState {
        invocationContinuation?.yield(.restore)
        return try await withCheckedThrowingContinuation { continuation in
            restoreContinuation = continuation
        }
    }

    func completeCustomerInfo(with state: MonetizationEntitlementState) {
        customerInfoContinuation?.resume(returning: state)
        customerInfoContinuation = nil
    }

    func failCustomerInfo() {
        customerInfoContinuation?.resume(throwing: ControlledProviderError.failed)
        customerInfoContinuation = nil
    }

    func completeLogIn(with state: MonetizationEntitlementState) {
        logInContinuation?.resume(returning: state)
        logInContinuation = nil
    }

    func failLogIn() {
        logInContinuation?.resume(throwing: ControlledProviderError.failed)
        logInContinuation = nil
    }

    func completeLogOut(with state: MonetizationEntitlementState) {
        logOutContinuation?.resume(returning: state)
        logOutContinuation = nil
    }

    func failLogOut() {
        logOutContinuation?.resume(throwing: ControlledProviderError.failed)
        logOutContinuation = nil
    }

    func sendCustomerInfoUpdate(with state: MonetizationEntitlementState) {
        customerInfoUpdateContinuation?.yield(state)
    }
}

private enum ControlledProviderError: Error {
    case failed
}
