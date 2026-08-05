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

        let identity = service.prepareIdentity(userId: "subscriber")
        let identifyTask = Task {
            await service.identify(userId: "subscriber", transition: identity)
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

        let supersededIdentity = service.prepareIdentity(userId: "superseded-user")
        let supersededIdentifyTask = Task {
            await service.identify(
                userId: "superseded-user",
                transition: supersededIdentity
            )
        }
        let currentIdentity = service.prepareIdentity(userId: "current-user")
        let identifyTask = Task {
            await service.identify(userId: "current-user", transition: currentIdentity)
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

        let identity = service.prepareIdentity(userId: "subscriber")
        let identifyTask = Task {
            await service.identify(userId: "subscriber", transition: identity)
        }
        #expect(await invocations.next() == .logIn(userID: "subscriber"))
        provider.failLogIn()
        await identifyTask.value

        let route = AppRootRouteResolver.resolve(
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

        let identity = service.prepareIdentity(userId: "subscriber")
        let identifyTask = Task {
            await service.identify(userId: "subscriber", transition: identity)
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

        let identity = service.prepareIdentity(userId: "subscriber")
        let identifyTask = Task {
            await service.identify(userId: "subscriber", transition: identity)
        }
        #expect(await invocations.next() == .logIn(userID: "subscriber"))

        await service.retryIdentityResolution()
        #expect(service.scheduledIdentityMutationCount == 1)

        provider.completeLogIn(with: .active(["app_access"]))
        await identifyTask.value

        #expect(service.entitlementState == .active(["app_access"]))
        #expect(provider.completedIdentityMutations == [.logIn(userID: "subscriber")])
    }

    @Test
    func delayedRefreshCannotOverwriteNewIdentity() async throws {
        let provider = ControlledRevenueCatEntitlementProvider()
        var invocations = provider.invocations.makeAsyncIterator()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let firstIdentity = service.prepareIdentity(userId: "first-user")
        let firstIdentifyTask = Task {
            await service.identify(userId: "first-user", transition: firstIdentity)
        }
        #expect(await invocations.next() == .logIn(userID: "first-user"))
        provider.completeLogIn(with: .active(["app_access"]))
        await firstIdentifyTask.value

        let staleRefreshTask = Task {
            await service.refreshCustomerInfo()
        }
        #expect(await invocations.next() == .customerInfo)

        let currentIdentity = service.prepareIdentity(userId: "current-user")
        let currentIdentifyTask = Task {
            await service.identify(userId: "current-user", transition: currentIdentity)
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

        let identity = service.prepareIdentity(userId: "subscriber")
        let identifyTask = Task {
            await service.identify(userId: "subscriber", transition: identity)
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

        let identity = service.prepareIdentity(userId: "subscriber")
        let identifyTask = Task {
            await service.identify(userId: "subscriber", transition: identity)
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

        let identity = service.prepareIdentity(userId: "subscriber")
        let identifyTask = Task {
            await service.identify(userId: "subscriber", transition: identity)
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

        let identity = service.prepareIdentity(userId: "subscriber")
        let identifyTask = Task {
            await service.identify(userId: "subscriber", transition: identity)
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

        let identity = service.prepareIdentity(userId: "subscriber")
        let identifyTask = Task {
            await service.identify(userId: "subscriber", transition: identity)
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

        let identity = service.prepareIdentity(userId: "subscriber")
        let identifyTask = Task {
            await service.identify(userId: "subscriber", transition: identity)
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

    @Test
    func aGenuineRefreshReportsExactlyWhatRevenueCatAnswered() async throws {
        let provider = ControlledRevenueCatEntitlementProvider()
        var invocations = provider.invocations.makeAsyncIterator()
        let service = RevenueCatEntitlementService(
            provider: provider,
            startsConfigured: true
        )

        let identity = service.prepareIdentity(userId: "subscriber")
        let identifyTask = Task {
            await service.identify(userId: "subscriber", transition: identity)
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
