import Foundation
import Observation

@MainActor
@Observable
final class MonetizationManager {
    static let shared = MonetizationManager()

    private let entitlementService: any EntitlementServicing
    private let paywallPresenter: any PaywallPresenting
    private(set) var configuration: MonetizationConfiguration

    var entitlementState: MonetizationEntitlementState {
        entitlementService.entitlementState
    }

    var hasAppAccess: Bool {
        configuration.allowsUnentitledAppAccess
            || entitlementState.hasActiveEntitlement(configuration.revenueCatEntitlementID)
    }

    var isRevenueCatConfigured: Bool {
        entitlementService.isConfigured
    }

    var isSuperwallConfigured: Bool {
        paywallPresenter.isConfigured
    }

    init(
        configuration: MonetizationConfiguration = .live,
        entitlementService: any EntitlementServicing = RevenueCatEntitlementService.shared,
        paywallPresenter: any PaywallPresenting = SuperwallPaywallPresenter.shared
    ) {
        self.configuration = configuration
        self.entitlementService = entitlementService
        self.paywallPresenter = paywallPresenter
    }

    func configure(configuration: MonetizationConfiguration = .live) {
        self.configuration = configuration
        entitlementService.configure(configuration: configuration)
        paywallPresenter.configure(configuration: configuration)
    }

    func identify(userId: String) async {
        await entitlementService.identify(userId: userId)
        paywallPresenter.identify(userId: userId)
    }

    func resetIdentity() async {
        await entitlementService.resetIdentity()
        paywallPresenter.resetIdentity()
    }

    func refreshEntitlements() async {
        await entitlementService.refreshCustomerInfo()
    }

    func restorePurchases() async throws {
        try await entitlementService.restorePurchases()
    }

    func presentPaywall(_ placement: SuperwallPlacement, params: [String: Any]? = nil) {
        LifecycleEventRecorder.shared.recordPaywallReached(
            placement: placement.rawValue
        )
        trackPaywallReached(placement, params: params)
        paywallPresenter.register(placement: placement, params: params)
    }

    private func trackPaywallReached(_ placement: SuperwallPlacement, params: [String: Any]?) {
        let source = params?["source"] as? String
        var parameters: [String: TelemetryValue] = [
            "placement": .string(placement.rawValue)
        ]

        if let source {
            parameters["source"] = .string(source)
        }

        TelemetryManager.shared.track(
            TelemetryRecord(
                name: "paywall_reached",
                parameters: parameters
            )
        )

        guard placement == .onboardingPaywall else { return }

        TelemetryManager.shared.track(
            OnboardingAnalyticsEvent.paywallReached(
                placement: placement.rawValue,
                source: source
            )
        )
    }
}
