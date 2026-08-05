import Foundation
import Testing
@testable import AscendApp

@MainActor
struct MonetizationManagerPaywallTests {
    @Test
    func gatesAccessWithoutAnEntitlementWhenBuildSettingIsDisabled() {
        let manager = MonetizationManager(
            configuration: MonetizationConfiguration(
                infoDictionary: [
                    MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "NO"
                ]
            ),
            entitlementService: EntitlementServiceStub(),
            paywallPresenter: PaywallPresenterSpy()
        )

        #expect(manager.hasAppAccess == false)
    }

    @Test
    func allowsAccessWithoutAnEntitlementWhenBuildSettingIsEnabled() {
        let manager = MonetizationManager(
            configuration: MonetizationConfiguration(
                infoDictionary: [
                    MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "YES"
                ]
            ),
            entitlementService: EntitlementServiceStub(),
            paywallPresenter: PaywallPresenterSpy()
        )

        #expect(manager.hasAppAccess)
    }

    @Test
    func allowsAccessWithActiveAppAccessEntitlementWhenBuildSettingIsDisabled() {
        let manager = MonetizationManager(
            configuration: MonetizationConfiguration(
                infoDictionary: [
                    MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "NO"
                ]
            ),
            entitlementService: EntitlementServiceStub(
                entitlementState: .active(["app_access"])
            ),
            paywallPresenter: PaywallPresenterSpy()
        )

        #expect(manager.hasAppAccess)
    }

    @Test
    func registersAppAccessGateWithSourceParameters() {
        let paywallPresenter = PaywallPresenterSpy()
        let manager = MonetizationManager(
            entitlementService: EntitlementServiceStub(),
            paywallPresenter: paywallPresenter
        )

        manager.presentPaywall(
            .appAccessGate,
            params: ["source": "app_access_gate"]
        )

        #expect(paywallPresenter.registeredPlacement == .appAccessGate)
        #expect(paywallPresenter.registeredSource == "app_access_gate")
    }

    @Test
    func appAccessGateEmitsOnboardingPaywallEventsAndDeduplicatesItsScreenView() {
        let paywallPresenter = PaywallPresenterSpy()
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        let manager = MonetizationManager(
            entitlementService: EntitlementServiceStub(),
            paywallPresenter: paywallPresenter,
            telemetry: telemetry
        )

        manager.presentPaywall(
            .appAccessGate,
            params: ["source": "app_access_gate"]
        )
        manager.presentPaywall(
            .appAccessGate,
            params: ["source": "paywall_placeholder_retry"]
        )

        let onboardingReached = sink.records.filter { $0.name == "onboarding_paywall_reached" }
        let onboardingViews = sink.records.filter { $0.name == "onboarding_screen_viewed" }

        #expect(onboardingReached.count == 2)
        #expect(onboardingReached.first?.parameters["placement"] == .string("app_access_gate"))
        #expect(onboardingReached.first?.parameters["source"] == .string("app_access_gate"))
        #expect(onboardingViews.count == 1)
        #expect(onboardingViews.first?.parameters["screen_id"] == .string("paywall"))
        #expect(onboardingViews.first?.parameters["viewed"] == .bool(true))
    }

    @Test
    func aNewIdentityStartsAFreshPaywallScreenViewPass() async {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let manager = MonetizationManager(
            entitlementService: EntitlementServiceStub(),
            paywallPresenter: PaywallPresenterSpy(),
            telemetry: makeTestTelemetry(sink: sink)
        )

        let firstIdentity = manager.prepareIdentity(userId: "user-a")
        await manager.identify(userId: "user-a", transition: firstIdentity)
        manager.presentPaywall(.onboardingPaywall)
        manager.presentPaywall(.onboardingPaywall)
        let reset = manager.prepareIdentityReset()
        await manager.resetIdentity(transition: reset)
        let secondIdentity = manager.prepareIdentity(userId: "user-b")
        await manager.identify(userId: "user-b", transition: secondIdentity)
        manager.presentPaywall(.onboardingPaywall)

        let onboardingViews = sink.records.filter { $0.name == "onboarding_screen_viewed" }

        #expect(onboardingViews.count == 2)
        #expect(onboardingViews.allSatisfy { $0.parameters["screen_id"] == .string("paywall") })
    }

    @Test
    func repeatIdentifyForTheSameUserKeepsThePaywallScreenViewDeduped() async {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let manager = MonetizationManager(
            entitlementService: EntitlementServiceStub(),
            paywallPresenter: PaywallPresenterSpy(),
            telemetry: makeTestTelemetry(sink: sink)
        )

        let firstIdentity = manager.prepareIdentity(userId: "user-a")
        await manager.identify(userId: "user-a", transition: firstIdentity)
        manager.presentPaywall(.onboardingPaywall)
        let repeatedIdentity = manager.prepareIdentity(userId: "user-a")
        await manager.identify(userId: "user-a", transition: repeatedIdentity)
        manager.presentPaywall(.onboardingPaywall)

        #expect(sink.records.filter { $0.name == "onboarding_screen_viewed" }.count == 1)
    }

    @Test
    func forwardsPresentationOutcomesToGateCaller() {
        let paywallPresenter = PaywallPresenterSpy()
        let manager = MonetizationManager(
            entitlementService: EntitlementServiceStub(),
            paywallPresenter: paywallPresenter
        )
        var receivedOutcome: PaywallPresentationOutcome?

        manager.presentPaywall(.appAccessGate) { outcome in
            receivedOutcome = outcome
        }
        paywallPresenter.send(.skipped(reason: "holdout"))

        #expect(receivedOutcome == .skipped(reason: "holdout"))
    }


    @Test
    func returningActiveSubscriberNeverRegistersAppAccessPaywall() async {
        let entitlementService = EntitlementServiceStub(
            initialState: .active(["app_access"])
        )
        let paywallPresenter = PaywallPresenterSpy()
        let manager = MonetizationManager(
            entitlementService: entitlementService,
            paywallPresenter: paywallPresenter
        )

        let reset = manager.prepareIdentityReset()
        await manager.resetIdentity(transition: reset)

        entitlementService.identityResolution = .active(["app_access"])
        let signIn = manager.prepareIdentity(userId: "returning-subscriber")

        let resolvingRoute = AppRootRouteResolver.resolve(
            authenticationState: .authenticated,
            userId: "returning-subscriber",
            postAuthOnboardingPhase: .complete,
            entitlementState: manager.entitlementStateForRouting,
            requiredEntitlementID: "app_access"
        )
        registerPaywallIfNeeded(
            for: resolvingRoute,
            with: manager
        )

        #expect(manager.entitlementStateForRouting == .unknown)
        #expect(resolvingRoute == .resolving)
        #expect(paywallPresenter.registeredPlacement == nil)

        await manager.identify(
            userId: "returning-subscriber",
            transition: signIn
        )

        let entitledRoute = AppRootRouteResolver.resolve(
            authenticationState: .authenticated,
            userId: "returning-subscriber",
            postAuthOnboardingPhase: .complete,
            entitlementState: manager.entitlementStateForRouting,
            requiredEntitlementID: "app_access"
        )
        registerPaywallIfNeeded(
            for: entitledRoute,
            with: manager
        )

        #expect(entitledRoute == .mainApp)
        #expect(paywallPresenter.registeredPlacement == nil)
    }

    private func registerPaywallIfNeeded(
        for route: AppRootRoute,
        with manager: MonetizationManager
    ) {
        guard route == .paywall else { return }
        manager.presentPaywall(.appAccessGate)
    }

    @Test
    func reportsConfigurationFailureWithoutRegisteringPlacement() {
        let paywallPresenter = PaywallPresenterSpy(isConfigured: false)
        let manager = MonetizationManager(
            entitlementService: EntitlementServiceStub(),
            paywallPresenter: paywallPresenter
        )
        var receivedOutcome: PaywallPresentationOutcome?

        manager.presentPaywall(.appAccessGate) { outcome in
            receivedOutcome = outcome
        }

        #expect(paywallPresenter.registeredPlacement == nil)
        #expect(receivedOutcome == .failed(message: "Superwall is not configured for this build."))
    }

    @Test
    func placeholderKeysLeaveTheGateOnTheUnconfiguredPath() {
        let paywallPresenter = PaywallPresenterSpy()
        let entitlementService = EntitlementServiceStub()
        let manager = MonetizationManager(
            entitlementService: entitlementService,
            paywallPresenter: paywallPresenter
        )
        var receivedOutcome: PaywallPresentationOutcome?

        manager.configure(
            configuration: MonetizationConfiguration(
                infoDictionary: [
                    MonetizationConfiguration.revenueCatAPIKeyInfoKey: "REPLACE_ME_PRODUCTION_REVENUECAT_KEY",
                    MonetizationConfiguration.superwallAPIKeyInfoKey: "REPLACE_ME_PRODUCTION_SUPERWALL_KEY",
                    MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "NO"
                ]
            )
        )
        manager.presentPaywall(.appAccessGate) { outcome in
            receivedOutcome = outcome
        }

        #expect(manager.isRevenueCatConfigured == false)
        #expect(manager.isSuperwallConfigured == false)
        #expect(manager.hasAppAccess == false)
        #expect(paywallPresenter.registeredPlacement == nil)
        #expect(receivedOutcome == .failed(message: "Superwall is not configured for this build."))
        #expect(
            !AppAccessRestoreState.idle.isButtonEnabled(
                isRevenueCatConfigured: manager.isRevenueCatConfigured
            )
        )
        #expect(
            AppAccessRestoreState.idle.buttonTitle(
                isRevenueCatConfigured: manager.isRevenueCatConfigured
            ) == "Restore Unavailable"
        )
    }

    @Test
    func realKeysConfigureBothMonetizationServices() {
        let manager = MonetizationManager(
            entitlementService: EntitlementServiceStub(),
            paywallPresenter: PaywallPresenterSpy()
        )

        manager.configure(
            configuration: MonetizationConfiguration(
                infoDictionary: [
                    MonetizationConfiguration.revenueCatAPIKeyInfoKey: "appl_test_key",
                    MonetizationConfiguration.superwallAPIKeyInfoKey: "pk_test_key",
                    MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "NO"
                ]
            )
        )

        #expect(manager.isRevenueCatConfigured)
        #expect(manager.isSuperwallConfigured)
    }
}

@MainActor
/// Shared with the funnel transcript tests, which drive the same paywall entry point.
final class PaywallPresenterSpy: PaywallPresenting {
    var isConfigured: Bool
    private(set) var registeredPlacement: SuperwallPlacement?
    private(set) var registeredSource: String?
    private(set) var registrations: [SuperwallPlacement] = []
    private var outcomeHandler: (@MainActor (PaywallPresentationOutcome) -> Void)?

    init(isConfigured: Bool = true) {
        self.isConfigured = isConfigured
    }

    /// Mirrors `SuperwallPaywallPresenter.configure`, which needs both keys.
    func configure(configuration: MonetizationConfiguration) {
        isConfigured = configuration.canConfigureSuperwall
    }

    func identify(userId: String) {}

    func resetIdentity() {}

    func register(
        placement: SuperwallPlacement,
        params: [String: Any]?,
        onOutcome: @escaping @MainActor (PaywallPresentationOutcome) -> Void
    ) {
        registeredPlacement = placement
        registeredSource = params?["source"] as? String
        registrations.append(placement)
        outcomeHandler = onOutcome
    }

    func send(_ outcome: PaywallPresentationOutcome) {
        outcomeHandler?(outcome)
    }
}

@MainActor
final class EntitlementServiceStub: EntitlementServicing {
    private(set) var entitlementState: MonetizationEntitlementState
    private(set) var hasFailedIdentityResolution = false
    var isConfigured = true
    var identityResolution = MonetizationEntitlementState.inactive
    var restoreError: (any Error)?
    private var revision: UInt = 0
    private var currentTransition: MonetizationIdentityTransition?

    init(initialState: MonetizationEntitlementState) {
        entitlementState = initialState
    }

    init(
        entitlementState: MonetizationEntitlementState = .inactive,
        restoreError: (any Error)? = nil
    ) {
        self.entitlementState = entitlementState
        self.restoreError = restoreError
    }

    /// Mirrors `RevenueCatEntitlementService.configure`, which needs a usable key.
    func configure(configuration: MonetizationConfiguration) {
        isConfigured = configuration.canConfigureRevenueCat
    }

    func refreshCustomerInfo() async {}

    func prepareIdentity(userId: String) -> MonetizationIdentityTransition {
        prepare(userID: userId)
    }

    func identify(
        userId: String,
        transition: MonetizationIdentityTransition
    ) async {
        resolve(identityResolution, for: transition)
    }

    func prepareIdentityReset() -> MonetizationIdentityTransition {
        prepare(userID: nil)
    }

    func resetIdentity(transition: MonetizationIdentityTransition) async {
        resolve(.inactive, for: transition)
    }

    func retryIdentityResolution() async {}

    func restorePurchases() async throws {
        if let restoreError {
            throw restoreError
        }
    }

    private func prepare(userID: String?) -> MonetizationIdentityTransition {
        revision &+= 1
        entitlementState = .unknown
        hasFailedIdentityResolution = false
        let transition = MonetizationIdentityTransition(
            revision: revision,
            userID: userID
        )
        currentTransition = transition
        return transition
    }

    private func resolve(
        _ state: MonetizationEntitlementState,
        for transition: MonetizationIdentityTransition
    ) {
        guard currentTransition == transition else { return }
        entitlementState = state

        guard state != .unknown else {
            hasFailedIdentityResolution = true
            return
        }

        currentTransition = nil
    }
}
