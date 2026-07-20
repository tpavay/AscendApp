import Testing
@testable import AscendApp

@MainActor
struct MonetizationManagerPaywallTests {
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
        let telemetry = makeTelemetry(sink: sink)
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

    private func makeTelemetry(sink: InMemoryTelemetrySink) -> TelemetryManager {
        let telemetry = TelemetryManager(
            sinks: [sink],
            crashlyticsReporter: MonetizationNoopCrashlyticsReporter(),
            collectionEnabledOverride: true
        )
        telemetry.configure()
        return telemetry
    }
}

@MainActor
private final class PaywallPresenterSpy: PaywallPresenting {
    var isConfigured: Bool
    private(set) var registeredPlacement: SuperwallPlacement?
    private(set) var registeredSource: String?
    private var outcomeHandler: (@MainActor (PaywallPresentationOutcome) -> Void)?

    init(isConfigured: Bool = true) {
        self.isConfigured = isConfigured
    }

    func configure(configuration: MonetizationConfiguration) {}

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
private final class EntitlementServiceStub: EntitlementServicing {
    var entitlementState = MonetizationEntitlementState.inactive
    var isConfigured = true

    func configure(configuration: MonetizationConfiguration) {}

    func refreshCustomerInfo() async {}

    func identify(userId: String) async {}

    func resetIdentity() async {}

    func restorePurchases() async throws {}
}

private struct MonetizationNoopCrashlyticsReporter: CrashlyticsReporting {
    func setCollectionEnabled(_ enabled: Bool) {}
    func setUserID(_ userID: String?) {}
    func setCustomValue(_ value: Bool, forKey key: String) {}
    func setCustomValue(_ value: Int, forKey key: String) {}
    func setCustomValue(_ value: String, forKey key: String) {}
    func log(_ message: String) {}
    func record(error: Error, context: String, code: String, additionalInfo: [String: String]?) {}
}
