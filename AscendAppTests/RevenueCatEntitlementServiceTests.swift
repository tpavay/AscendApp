import Foundation
import Testing
@testable import AscendApp

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
    }

    @Test
    func unconfiguredIdentityDoesNotStartCustomerInfoUpdates() async {
        let provider = ControlledRevenueCatEntitlementProvider()
        let service = RevenueCatEntitlementService(provider: provider)

        let identity = service.prepareIdentity(userId: "subscriber")
        await service.identify(userId: "subscriber", transition: identity)

        #expect(service.entitlementState == .inactive)
        #expect(provider.customerInfoUpdatesAccessCount == 0)
    }

    @Test
    func foregroundRefreshRetriesFailedIdentityAndStartsCustomerInfoUpdates() async throws {
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

        let refreshTask = Task {
            await service.refreshCustomerInfo()
        }
        #expect(await invocations.next() == .logIn(userID: "subscriber"))
        provider.completeLogIn(with: .active(["app_access"]))
        await refreshTask.value

        #expect(service.entitlementState == .active(["app_access"]))

        provider.sendCustomerInfoUpdate()
        #expect(await invocations.next() == .customerInfo)
        provider.completeCustomerInfo(with: .active(["app_access"]))
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
    func customerInfoUpdateTriggersRefresh() async throws {
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

        provider.sendCustomerInfoUpdate()
        #expect(await invocations.next() == .customerInfo)
        #expect(provider.customerInfoCallCount == 1)
        provider.completeCustomerInfo(with: .active(["app_access"]))
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
    private(set) var customerInfoUpdatesAccessCount = 0
    private(set) var completedIdentityMutations: [RevenueCatProviderInvocation] = []

    lazy var invocations = AsyncStream<RevenueCatProviderInvocation> { continuation in
        invocationContinuation = continuation
    }

    var customerInfoUpdates: AsyncStream<Void> {
        customerInfoUpdatesAccessCount += 1
        return customerInfoUpdateStream
    }

    private lazy var customerInfoUpdateStream = AsyncStream<Void> { continuation in
        self.customerInfoUpdateContinuation = continuation
    }

    private var invocationContinuation: AsyncStream<RevenueCatProviderInvocation>.Continuation?
    private var customerInfoUpdateContinuation: AsyncStream<Void>.Continuation?
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

    func sendCustomerInfoUpdate() {
        customerInfoUpdateContinuation?.yield()
    }
}

private enum ControlledProviderError: Error {
    case failed
}
