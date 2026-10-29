import Foundation
import os
import Testing
@testable import AscendApp

/// `onboarding_flow_completed` fired on the climber's next cold launch, days after they got in,
/// because the completion reason was held back until the paywall reported how access was granted
/// and a purchase makes the entitlement active first: that flip retires the paywall attempt, and the
/// outcome the retired attempt would have reported is dropped. These tests drive the real manager,
/// gate coordinator and flow coordinator in the order a purchase delivers them.
@MainActor
struct OnboardingCompletionAtAccessConfirmationTests {
    private static let entitlement = MonetizationEntitlementState.active(["app_access"])

    @Test
    func aHostedPurchaseCompletesTheFlowAtConfirmationWithoutARelaunch() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }

        fixture.coordinator.start()
        fixture.confirmPurchase()

        // The entitlement flip reaches the gate's view before Superwall's dismissal does.
        fixture.coordinator.entitlementDidChange(Self.entitlement)
        fixture.paywallPresenter.send(.purchased)

        fixture.completeIfRouted()

        let completed = fixture.records(named: "onboarding_flow_completed")
        #expect(completed.count == 1)
        #expect(completed.first?.parameters["completion_reason"] == .string("purchase"))
    }

    @Test
    func theCompletionIsNotRepeatedByARelaunch() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }

        fixture.coordinator.start()
        fixture.confirmPurchase()
        fixture.coordinator.entitlementDidChange(Self.entitlement)
        fixture.completeIfRouted()

        let relaunch = fixture.relaunch()
        if let reason = relaunch.manager.onboardingCompletionReasonForActiveAccess {
            relaunch.lifecycle.recordFlowCompletedIfNeeded(reason: reason)
        }

        #expect(fixture.records(named: "onboarding_flow_completed").count == 1)
    }

    @Test
    func aPurchaseNeverWaitsOnTheDismissalThatTheEntitlementFlipRetires() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }

        fixture.coordinator.start()
        fixture.confirmPurchase()

        #expect(fixture.manager.onboardingCompletionReasonForActiveAccess == .purchase)
    }

    /// A comp lands through the entitlement stream while the gate is up. Nothing in the app asked
    /// for it, so it must not be counted as a sale, and it must not wait for a relaunch either.
    @Test
    func aGrantNobodyAttributesSettlesAsUnknownRatherThanAPurchase() async {
        let fixture = Fixture(settlesImmediately: true)
        defer { fixture.cleanUp() }

        fixture.coordinator.start()
        fixture.entitlements.setEntitlementState(Self.entitlement)
        fixture.coordinator.entitlementDidChange(Self.entitlement)
        await fixture.manager.settleUnattributedAccessGrantForTesting()

        fixture.completeIfRouted()

        let completed = fixture.records(named: "onboarding_flow_completed")
        #expect(completed.count == 1)
        #expect(completed.first?.parameters["completion_reason"] == .string("unknown"))
    }

    /// The stream can beat the purchase's own confirmation by a moment. The settle window exists so
    /// that moment is not mistaken for a comp.
    @Test
    func aPurchaseConfirmedInsideTheSettleWindowStaysAPurchase() async {
        let fixture = Fixture(settlesImmediately: true)
        defer { fixture.cleanUp() }

        fixture.coordinator.start()
        fixture.entitlements.setEntitlementState(Self.entitlement)
        fixture.coordinator.entitlementDidChange(Self.entitlement)
        #expect(fixture.manager.onboardingCompletionReasonForActiveAccess == nil)

        fixture.confirmPurchase()
        await fixture.manager.settleUnattributedAccessGrantForTesting()

        #expect(fixture.manager.onboardingCompletionReasonForActiveAccess == .purchase)
    }

    /// RevenueCat can finish Apple's transaction before its entitlement projection reaches the
    /// returned CustomerInfo, and the executor's refresh then turns access on without handing the
    /// manager the active state. That is still the purchase the climber just made.
    @Test
    func aPurchaseWhoseEntitlementArrivesThroughTheRefreshStaysAPurchase() async {
        let fixture = Fixture(settlesImmediately: true)
        defer { fixture.cleanUp() }

        fixture.coordinator.start()
        let executor = RevenueCatPurchaseExecutor(
            telemetry: fixture.telemetry,
            entitlementID: "app_access",
            applySubscriptionStatus: { _ in },
            refreshEntitlementState: {
                fixture.entitlements.setEntitlementState(Self.entitlement)
                fixture.coordinator.entitlementDidChange(Self.entitlement)
                return .refreshed(Self.entitlement)
            },
            currentIdentityGeneration: { fixture.manager.identityGeneration },
            adoptEntitlementState: { state, identity in
                fixture.manager.adoptPurchaseEntitlementState(state, for: identity)
            }
        )

        _ = await executor.executePurchase(productID: "ascend_annual") {
            RevenueCatPurchaseExecutor.PurchaseResponse(userCancelled: false, entitlementState: .inactive)
        }
        await fixture.manager.settleUnattributedAccessGrantForTesting()

        fixture.completeIfRouted()

        let completed = fixture.records(named: "onboarding_flow_completed")
        #expect(completed.count == 1)
        #expect(completed.first?.parameters["completion_reason"] == .string("purchase"))
    }

    /// The settle window belongs to the account it was opened for. Switching accounts closes it, so
    /// the next account's own grant opens a window of its own instead of waiting on the old one.
    @Test(.timeLimit(.minutes(1)))
    func switchingAccountsClosesTheSettleWindowItOpened() async {
        let switched = OSAllocatedUnfairLock(initialState: false)
        let (windowsOpened, opened) = AsyncStream<Void>.makeStream()
        let fixture = Fixture(settleSleep: { _ in
            opened.yield()
            if !switched.withLock({ $0 }) {
                try await Task.sleep(for: .seconds(3_600))
            }
        })
        defer { fixture.cleanUp() }

        fixture.coordinator.start()
        fixture.entitlements.setEntitlementState(Self.entitlement)
        for await _ in windowsOpened { break }

        switched.withLock { $0 = true }
        fixture.entitlements.identityResolution = Self.entitlement
        let next = MonetizationCustomerIdentity(userID: "next-user", email: nil)
        let transition = fixture.manager.prepareIdentity(next)
        await fixture.manager.identify(next, transition: transition)
        await fixture.manager.settleUnattributedAccessGrantForTesting()

        #expect(fixture.manager.onboardingCompletionReasonForActiveAccess == .unknown)
    }

    @Test
    func anExistingEntitlementStillCompletesAsExisting() {
        let fixture = Fixture(initialState: Self.entitlement)
        defer { fixture.cleanUp() }

        fixture.completeIfRouted()

        let completed = fixture.records(named: "onboarding_flow_completed")
        #expect(completed.count == 1)
        #expect(completed.first?.parameters["completion_reason"] == .string("existing_entitlement"))
    }

    @MainActor
    private final class Fixture {
        let suiteName = "OnboardingCompletionAtAccessConfirmationTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry: TelemetryManager
        let entitlements: EntitlementServiceStub
        let paywallPresenter = PaywallPresenterSpy()
        let lifecycle: OnboardingFlowAnalyticsCoordinator
        let manager: MonetizationManager
        let coordinator: AppAccessPaywallCoordinator
        let identity = MonetizationIdentityTransition(revision: 1, userID: "test-user")

        init(
            initialState: MonetizationEntitlementState = .inactive,
            settlesImmediately: Bool = false,
            settleSleep: (@Sendable (Duration) async throws -> Void)? = nil
        ) {
            defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            telemetry = makeTestTelemetry(sink: sink)
            telemetry.setUserId("test-user")
            entitlements = EntitlementServiceStub(entitlementState: initialState)
            lifecycle = OnboardingFlowAnalyticsCoordinator(userDefaults: defaults, telemetry: telemetry)
            lifecycle.recordFlowStartedIfNeeded(context: OnboardingAnalyticsEvent.welcomeContext)
            manager = MonetizationManager(
                entitlementService: entitlements,
                paywallPresenter: paywallPresenter,
                telemetry: telemetry,
                onboardingLifecycle: lifecycle,
                unattributedGrantSettleDelay: settlesImmediately ? .zero : .seconds(3_600),
                unattributedGrantSleep: settleSleep ?? { try await Task.sleep(for: $0) }
            )
            manager.configure()
            coordinator = AppAccessPaywallCoordinator(
                monetizationManager: manager,
                telemetry: telemetry,
                sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }
            )
        }

        func records(named name: String) -> [EnvelopedTelemetryRecord] {
            sink.records.filter { $0.name == name }
        }

        /// What `RevenueCatPurchaseExecutor` hands the manager the moment a purchase is confirmed.
        func confirmPurchase() {
            manager.adoptPurchaseEntitlementState(MonetizationEntitlementState.active(["app_access"]), for: identity)
        }

        /// What `RootView` does once the route is Home and the post-auth phase is complete.
        func completeIfRouted() {
            let reason = OnboardingFlowCompletionResolver.completionReason(
                rootRoute: .mainApp,
                postAuthPhase: .complete,
                confirmedAccessReason: manager.onboardingCompletionReasonForActiveAccess
            )
            guard let reason else { return }
            lifecycle.recordFlowCompletedIfNeeded(reason: reason)
        }

        func relaunch() -> (lifecycle: OnboardingFlowAnalyticsCoordinator, manager: MonetizationManager) {
            let relaunched = OnboardingFlowAnalyticsCoordinator(userDefaults: defaults, telemetry: telemetry)
            let relaunchedManager = MonetizationManager(
                entitlementService: EntitlementServiceStub(entitlementState: .active(["app_access"])),
                paywallPresenter: PaywallPresenterSpy(),
                telemetry: telemetry,
                onboardingLifecycle: relaunched
            )
            return (relaunched, relaunchedManager)
        }

        func cleanUp() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}
