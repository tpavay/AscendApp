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

        await manager.identify(userId: "user-a")
        manager.presentPaywall(.onboardingPaywall)
        manager.presentPaywall(.onboardingPaywall)
        await manager.resetIdentity()
        await manager.identify(userId: "user-b")
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

        await manager.identify(userId: "user-a")
        manager.presentPaywall(.onboardingPaywall)
        await manager.identify(userId: "user-a")
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
        outcomeHandler = onOutcome
    }

    func send(_ outcome: PaywallPresentationOutcome) {
        outcomeHandler?(outcome)
    }
}

@MainActor
final class EntitlementServiceStub: EntitlementServicing {
    var entitlementState: MonetizationEntitlementState
    var isConfigured = true

    init(entitlementState: MonetizationEntitlementState = .inactive) {
        self.entitlementState = entitlementState
    }

    /// Mirrors `RevenueCatEntitlementService.configure`, which needs a usable key.
    func configure(configuration: MonetizationConfiguration) {
        isConfigured = configuration.canConfigureRevenueCat
    }

    func refreshCustomerInfo() async {}

    func identify(userId: String) async {}

    func resetIdentity() async {}

    func restorePurchases() async throws {}
}
