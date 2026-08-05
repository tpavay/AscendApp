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
    private let appAccessReconciler: any AppAccessReconciling
    private let telemetry: TelemetryManager
    private let userDefaults: UserDefaults
    @ObservationIgnored
    private let onboardingLifecycle: OnboardingFlowAnalyticsCoordinator
    @ObservationIgnored
    private var onboardingScreenViewRecorder = OnboardingScreenViewRecorder()
    @ObservationIgnored
    private var identifiedUserID: String?
    @ObservationIgnored
    private var preparedIdentityTransition: MonetizationIdentityTransition?
    private(set) var configuration: MonetizationConfiguration
    /// Tracks whether this identity has asked to buy or restore access it does not yet have, and
    /// what that request finally reported. Attribution is read from the request's own result, never
    /// inferred from when the entitlement happened to turn active.
    private var onboardingAccessGrantRequest: OnboardingAccessGrantRequest = .notRequested
    #if DEBUG
    private(set) var debugForcesAppAccessPaywall: Bool
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

    var onboardingCompletionReasonForActiveAccess: OnboardingFlowCompletionReason? {
        guard entitlementStateForRouting.hasActiveEntitlement(
            configuration.revenueCatEntitlementID
        ) else {
            return nil
        }

        switch onboardingAccessGrantRequest {
        case .notRequested:
            // Access this pass never asked for is access the climber already held.
            return .existingEntitlement
        case .pending:
            // The entitlement can turn active before the paywall or restore says how. Reporting a
            // reason now would bank a guess the persisted completion can never correct.
            return nil
        case .resolved(let reason):
            // A request that reported no grant of its own - dismissed, skipped, failed, or a
            // restore that found nothing - still asked for one, so a webhook-delayed purchase that
            // lands afterwards is that purchase, not a pre-existing entitlement.
            return reason ?? .purchase
        }
    }

    init(
        configuration: MonetizationConfiguration = .live,
        entitlementService: any EntitlementServicing = RevenueCatEntitlementService.shared,
        paywallPresenter: any PaywallPresenting = SuperwallPaywallPresenter.shared,
        appAccessReconciler: any AppAccessReconciling = AppAccessReconciliationService.shared,
        telemetry: TelemetryManager = .shared,
        onboardingLifecycle: OnboardingFlowAnalyticsCoordinator = .shared,
        userDefaults: UserDefaults = .standard
    ) {
        self.configuration = configuration
        self.entitlementService = entitlementService
        self.paywallPresenter = paywallPresenter
        self.appAccessReconciler = appAccessReconciler
        self.telemetry = telemetry
        self.onboardingLifecycle = onboardingLifecycle
        self.userDefaults = userDefaults
        #if DEBUG
        debugForcesAppAccessPaywall = userDefaults.bool(
            forKey: MonetizationManager.debugForcesAppAccessPaywallKey
        )
        #endif
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
            onboardingAccessGrantRequest = .notRequested
        }

        // The pass that opened before auth belongs to whoever just claimed it; a different account
        // retires it rather than inheriting its start.
        onboardingLifecycle.adoptPassOwner(userId)

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
        onboardingAccessGrantRequest = .notRequested
        onboardingLifecycle.retireAdoptedPass()

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

    func refreshEntitlements(force: Bool = false) async {
        await entitlementService.refreshCustomerInfo()
        await reconcileServerAppAccess(force: force)
    }

    /// Asks the server to re-derive this user's paid access from RevenueCat.
    ///
    /// The device answer is responsive but not authoritative. A purchase can beat its webhook to
    /// the backend, and a webhook that was never delivered would otherwise lock a real subscriber
    /// out of every paid boundary forever, so an active device entitlement always prompts the
    /// server to reconcile. It costs nothing when the projection is already current.
    func reconcileServerAppAccess(force: Bool = false) async {
        await reconcileServerAppAccess(for: entitlementState, force: force)
    }

    private func reconcileServerAppAccess(
        for state: MonetizationEntitlementState,
        force: Bool
    ) async {
        guard state.hasActiveEntitlement(
            configuration.revenueCatEntitlementID
        ) else { return }

        await appAccessReconciler.reconcileAppAccess(force: force)
    }

    func retryIdentityResolution() async {
        await entitlementService.retryIdentityResolution()
    }

    @discardableResult
    func restorePurchases() async throws -> MonetizationEntitlementState {
        beginOnboardingAccessGrantRequest()

        do {
            let state = try await entitlementService.restorePurchases()
            await reconcileServerAppAccess(for: state, force: true)

            if state.hasActiveEntitlement(configuration.revenueCatEntitlementID) {
                recordOnboardingAccessGranted(.restore)
            } else {
                recordOnboardingAccessGrantRequestReportedNothing()
            }

            return state
        } catch {
            recordOnboardingAccessGrantRequestReportedNothing()
            throw error
        }
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

        let tracksOnboardingAccess = placement == .onboardingPaywall || placement == .appAccessGate
        if tracksOnboardingAccess {
            beginOnboardingAccessGrantRequest()
        }

        guard paywallPresenter.isConfigured else {
            if tracksOnboardingAccess {
                recordOnboardingAccessGrantRequestReportedNothing()
            }
            onOutcome(.failed(message: "Superwall is not configured for this build."))
            return
        }

        paywallPresenter.register(
            placement: placement,
            params: params,
            onOutcome: { [weak self] outcome in
                if tracksOnboardingAccess {
                    self?.recordOnboardingPaywallOutcome(outcome)
                }
                onOutcome(outcome)
            }
        )
    }

    #if DEBUG
    func setDebugForcesAppAccessPaywall(_ shouldForce: Bool) {
        debugForcesAppAccessPaywall = shouldForce
        userDefaults.set(shouldForce, forKey: Self.debugForcesAppAccessPaywallKey)
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
            resume: onboardingLifecycle.consumeScreenResumeFlag(),
            telemetry: telemetry
        )
    }

    private func beginOnboardingAccessGrantRequest() {
        guard !entitlementStateForRouting.hasActiveEntitlement(
            configuration.revenueCatEntitlementID
        ) else { return }

        onboardingAccessGrantRequest = .pending
    }

    private func recordOnboardingAccessGranted(_ reason: OnboardingFlowCompletionReason) {
        onboardingAccessGrantRequest = .resolved(reason)
    }

    /// Closes the pending request without attributing anything, so a climber whose paywall
    /// reported nothing is never left waiting on a result that will not arrive.
    private func recordOnboardingAccessGrantRequestReportedNothing() {
        guard onboardingAccessGrantRequest == .pending else { return }

        onboardingAccessGrantRequest = .resolved(nil)
    }

    /// Only an outcome that names how access was granted may attribute one. A dismissal, a skip or
    /// a failure closes the request without naming anything.
    private func recordOnboardingPaywallOutcome(_ outcome: PaywallPresentationOutcome) {
        switch outcome {
        case .purchased:
            recordOnboardingAccessGranted(.purchase)
        case .restored:
            recordOnboardingAccessGranted(.restore)
        case .dismissedWithoutPurchase, .skipped, .failed:
            recordOnboardingAccessGrantRequestReportedNothing()
        case .presented:
            // The paywall being on screen is not a result; the request stays pending.
            break
        }
    }
}

private enum OnboardingAccessGrantRequest: Equatable {
    case notRequested
    case pending
    /// `nil` when the request closed without naming how access was granted.
    case resolved(OnboardingFlowCompletionReason?)
}
