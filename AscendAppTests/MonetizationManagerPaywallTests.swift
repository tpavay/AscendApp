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
