import Foundation
import Observation

@MainActor
@Observable
final class MonetizationManager: MonetizationIdentityManaging {
    static let shared = MonetizationManager()
    #if DEBUG
    private static let debugForcesAppAccessPaywallKey = "debug.monetization.forceAppAccessPaywall"
    #endif

    private let entitlementService: any EntitlementServicing
    private let paywallPresenter: any PaywallPresenting
    private let telemetry: TelemetryManager
    @ObservationIgnored
    private var onboardingScreenViewRecorder = OnboardingScreenViewRecorder()
    @ObservationIgnored
    private var identifiedUserID: String?
    @ObservationIgnored
    private var preparedIdentityTransition: MonetizationIdentityTransition?
    private(set) var configuration: MonetizationConfiguration
    #if DEBUG
    private(set) var debugForcesAppAccessPaywall = UserDefaults.standard.bool(
        forKey: MonetizationManager.debugForcesAppAccessPaywallKey
    )
    #endif

    var entitlementState: MonetizationEntitlementState {
        entitlementService.entitlementState
    }

    var hasFailedIdentityResolution: Bool {
        entitlementService.hasFailedIdentityResolution
    }

    var hasAppAccess: Bool {
        allowsUnentitledAppAccessForRouting
            || entitlementStateForRouting.hasActiveEntitlement(configuration.revenueCatEntitlementID)
    }

    var entitlementStateForRouting: MonetizationEntitlementState {
        #if DEBUG
        if debugForcesAppAccessPaywall {
            return .inactive
        }
        #endif

        return entitlementState
    }

    var allowsUnentitledAppAccessForRouting: Bool {
        #if DEBUG
        return configuration.allowsUnentitledAppAccess && !debugForcesAppAccessPaywall
        #else
        return configuration.allowsUnentitledAppAccess
        #endif
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
        paywallPresenter: any PaywallPresenting = SuperwallPaywallPresenter.shared,
        telemetry: TelemetryManager = .shared
    ) {
        self.configuration = configuration
        self.entitlementService = entitlementService
        self.paywallPresenter = paywallPresenter
        self.telemetry = telemetry
    }

    func configure(configuration: MonetizationConfiguration = .live) {
        self.configuration = configuration
        entitlementService.configure(configuration: configuration)
        paywallPresenter.configure(configuration: configuration)
    }

    @discardableResult
    func prepareIdentity(userId: String) -> MonetizationIdentityTransition {
        if identifiedUserID != userId {
            identifiedUserID = userId
            onboardingScreenViewRecorder = OnboardingScreenViewRecorder()
        }

        let transition = entitlementService.prepareIdentity(userId: userId)
        preparedIdentityTransition = transition
        return transition
    }

    func identify(
        userId: String,
        transition: MonetizationIdentityTransition
    ) async {
        await entitlementService.identify(
            userId: userId,
            transition: transition
        )

        guard identifiedUserID == userId,
              preparedIdentityTransition == transition else {
            return
        }

        preparedIdentityTransition = nil
        paywallPresenter.identify(userId: userId)
    }

    @discardableResult
    func prepareIdentityReset() -> MonetizationIdentityTransition {
        // The paywall screen view dedupes per pass through the onboarding funnel, and an identity
        // change starts a new pass, so the recorder cannot outlive the identity it was filled for.
        identifiedUserID = nil
        onboardingScreenViewRecorder = OnboardingScreenViewRecorder()

        let transition = entitlementService.prepareIdentityReset()
        preparedIdentityTransition = transition
        return transition
    }

    func resetIdentity(transition: MonetizationIdentityTransition) async {
        await entitlementService.resetIdentity(transition: transition)

        guard identifiedUserID == nil,
              preparedIdentityTransition == transition else {
            return
        }

        preparedIdentityTransition = nil
        paywallPresenter.resetIdentity()
    }

    func refreshEntitlements() async {
        await entitlementService.refreshCustomerInfo()
    }

    func retryIdentityResolution() async {
        await entitlementService.retryIdentityResolution()
    }

    func restorePurchases() async throws {
        try await entitlementService.restorePurchases()
    }

    func presentPaywall(
        _ placement: SuperwallPlacement,
        params: [String: Any]? = nil,
        onOutcome: @escaping @MainActor (PaywallPresentationOutcome) -> Void = { _ in }
    ) {
        LifecycleEventRecorder.shared.recordPaywallReached(
            placement: placement.rawValue
        )
        trackPaywallReached(placement, params: params)

        guard paywallPresenter.isConfigured else {
            onOutcome(.failed(message: "Superwall is not configured for this build."))
            return
        }

        paywallPresenter.register(
            placement: placement,
            params: params,
            onOutcome: onOutcome
        )
    }

    #if DEBUG
    func setDebugForcesAppAccessPaywall(_ shouldForce: Bool) {
        debugForcesAppAccessPaywall = shouldForce
        UserDefaults.standard.set(shouldForce, forKey: Self.debugForcesAppAccessPaywallKey)
    }
    #endif

    private func trackPaywallReached(_ placement: SuperwallPlacement, params: [String: Any]?) {
        let source = params?["source"] as? String
        var parameters: [String: TelemetryValue] = [
            "placement": .string(placement.rawValue)
        ]

        if let source {
            parameters["source"] = .string(source)
        }

        telemetry.track(
            TelemetryRecord(
                name: "paywall_reached",
                parameters: parameters
            )
        )

        guard placement == .onboardingPaywall || placement == .appAccessGate else { return }

        telemetry.track(
            OnboardingAnalyticsEvent.paywallReached(
                placement: placement.rawValue,
                source: source
            )
        )
        onboardingScreenViewRecorder.recordIfNeeded(
            OnboardingAnalyticsEvent.paywallContext,
            telemetry: telemetry
        )
    }
}
