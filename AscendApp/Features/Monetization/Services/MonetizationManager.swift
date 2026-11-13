import Foundation
import Observation

@MainActor
@Observable
final class MonetizationManager: MonetizationIdentityManaging {
    static let shared = MonetizationManager()

    private let entitlementService: any EntitlementServicing
    private let paywallPresenter: any PaywallPresenting
    private let appAccessReconciler: any AppAccessReconciling
    /// The server-granted free week, for the account this manager is identified as.
    let freeWeek: FreeWeekAccessStore
    private let telemetry: TelemetryManager
    private let pendingPurchaseHoldStore: PendingPurchaseHoldStore
    private let declineOfferReplayStore: DeclineOfferReplayStore
    private let isOnboardingV3Enabled: @MainActor () -> Bool
    /// The account whose first paywall was on screen when the previous process died, read once at
    /// launch. A marker written during this process is not a force-close, so it is never replayed.
    @ObservationIgnored
    private var declineOfferOwedAtLaunch: String?
    private let verdictBudget: MonetizationVerdictBudget
    private let unattributedGrantSettleDelay: Duration
    private let unattributedGrantSleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored
    private var unattributedGrantSettleTask: Task<Void, Never>?
    @ObservationIgnored
    private let onboardingLifecycle: OnboardingFlowAnalyticsCoordinator
    @ObservationIgnored
    private var identifiedUserID: String?
    @ObservationIgnored
    private var preparedIdentityTransition: MonetizationIdentityTransition?
    @ObservationIgnored
    private var paywallAttemptRevision: UInt = 0
    @ObservationIgnored
    private var activePaywallAttempt: (
        revision: UInt,
        identity: MonetizationIdentityTransition
    )?
    private(set) var configuration: MonetizationConfiguration
    #if DEBUG
    /// Held in memory only, so relaunching is the way out of a forced gate: the gate is a spinner
    /// behind hosted screens, and neither can carry a control that clears a debug override.
    private(set) var debugForcesAppAccessPaywall = false
    #endif

    var entitlementState: MonetizationEntitlementState {
        entitlementService.entitlementState
    }

    var hasFailedIdentityResolution: Bool {
        entitlementService.hasFailedIdentityResolution
    }

    /// A running free week is app access exactly as a paid entitlement is: the server holds the
    /// same grant document for both, so everything that waits on access - routing, the workout
    /// upload hold - opens for it too.
    var hasAppAccess: Bool {
        allowsUnentitledAppAccessForRouting
            || entitlementStateForRouting.hasActiveEntitlement(configuration.revenueCatEntitlementID)
            || freeWeekAccessForRouting == .live
    }

    var freeWeekAccessForRouting: FreeWeekRoutingAccess {
        #if DEBUG
        if debugForcesAppAccessPaywall {
            return .none
        }
        #endif

        return freeWeek.routingAccess
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

    var identityGeneration: MonetizationIdentityTransition? {
        entitlementService.identityGeneration
    }

    var onboardingCompletionReasonForActiveAccess: OnboardingFlowCompletionReason? {
        guard entitlementStateForRouting.hasActiveEntitlement(
            configuration.revenueCatEntitlementID
        ) else {
            // The free week lets a climber in with no entitlement at all, and it names itself.
            return freeWeekAccessForRouting == .live ? .freeWeek : nil
        }

        switch onboardingLifecycle.accessGrantProvenance {
        case .notRequested:
            // Access this pass never asked for is access the climber already held.
            return .existingEntitlement
        case .pending:
            // The entitlement can turn active before the paywall or restore says how. Reporting a
            // reason now would bank a guess the persisted completion can never correct.
            return nil
        case .resolved(let reason):
            // A request that reported no grant of its own - dismissed, skipped, failed, or a
            // restore that found nothing - still asked for one, so what lands afterwards is not a
            // pre-existing entitlement. A purchase confirmed in the app names itself, so what is
            // left is a grant nothing here can vouch for, and it is not counted as a sale.
            return reason ?? .unknown
        }
    }

    init(
        configuration: MonetizationConfiguration = .live,
        entitlementService: any EntitlementServicing = RevenueCatEntitlementService.shared,
        paywallPresenter: any PaywallPresenting = SuperwallPaywallPresenter.shared,
        appAccessReconciler: any AppAccessReconciling = AppAccessReconciliationService.shared,
        freeWeek: FreeWeekAccessStore? = nil,
        telemetry: TelemetryManager = .shared,
        onboardingLifecycle: OnboardingFlowAnalyticsCoordinator = .shared,
        userDefaults: UserDefaults = .standard,
        isOnboardingV3Enabled: @escaping @MainActor () -> Bool = MonetizationManager.liveOnboardingV3Switch,
        verdictBudget: MonetizationVerdictBudget = MonetizationVerdictBudget(),
        unattributedGrantSettleDelay: Duration = .seconds(15),
        unattributedGrantSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.unattributedGrantSettleDelay = unattributedGrantSettleDelay
        self.unattributedGrantSleep = unattributedGrantSleep
        self.configuration = configuration
        self.entitlementService = entitlementService
        self.paywallPresenter = paywallPresenter
        self.appAccessReconciler = appAccessReconciler
        self.freeWeek = freeWeek ?? FreeWeekAccessStore(
            cache: FreeWeekRecordCache(userDefaults: userDefaults)
        )
        self.telemetry = telemetry
        self.onboardingLifecycle = onboardingLifecycle
        pendingPurchaseHoldStore = PendingPurchaseHoldStore(userDefaults: userDefaults)
        declineOfferReplayStore = DeclineOfferReplayStore(userDefaults: userDefaults)
        declineOfferOwedAtLaunch = declineOfferReplayStore.pendingUserID()
        self.isOnboardingV3Enabled = isOnboardingV3Enabled
        self.verdictBudget = verdictBudget
    }

    func configure(configuration: MonetizationConfiguration = .live) {
        self.configuration = configuration
        entitlementService.setEntitlementStateObserver { [weak self] state in
            guard let self else { return }
            let entitlementIDs: Set<String>
            if case .active(let activeIDs) = state {
                entitlementIDs = activeIDs
            } else {
                entitlementIDs = []
            }
            self.paywallPresenter.updateSubscriptionStatus(entitlementIDs: entitlementIDs)
            if state.hasActiveEntitlement(self.configuration.revenueCatEntitlementID) {
                self.releasePendingPurchaseHold()
                self.clearPendingDeclineOffer()
            }
            self.settleUnattributedAccessGrantIfNeeded(for: state)
        }
        entitlementService.configure(configuration: configuration)
        paywallPresenter.configure(configuration: configuration)
        let activeIDs: Set<String>
        if case .active(let entitlementIDs) = entitlementService.entitlementState {
            activeIDs = entitlementIDs
        } else {
            activeIDs = []
        }
        paywallPresenter.updateSubscriptionStatus(entitlementIDs: activeIDs)
    }

    @discardableResult
    func prepareIdentity(
        _ customer: MonetizationCustomerIdentity
    ) -> MonetizationIdentityTransition {
        invalidatePaywallAttempt()
        cancelUnattributedGrantSettle()
        identifiedUserID = customer.userID

        // The pass that opened before auth belongs to whoever just claimed it; a different account
        // retires it, and the grant provenance it was carrying, rather than inheriting either.
        onboardingLifecycle.adoptPassOwner(customer.userID)
        freeWeek.setUser(customer.userID)

        let transition = entitlementService.prepareIdentity(customer)
        preparedIdentityTransition = transition
        return transition
    }

    func identify(
        _ customer: MonetizationCustomerIdentity,
        transition: MonetizationIdentityTransition
    ) async {
        await entitlementService.identify(customer, transition: transition)

        guard identifiedUserID == customer.userID,
              preparedIdentityTransition == transition else {
            return
        }

        preparedIdentityTransition = nil
        paywallPresenter.identify(userId: customer.userID)
    }

    @discardableResult
    func prepareIdentityReset() -> MonetizationIdentityTransition {
        invalidatePaywallAttempt()
        cancelUnattributedGrantSettle()
        // The paywall screen view dedupes per pass, and retiring the pass is what makes every step
        // reportable again - including this one.
        identifiedUserID = nil
        onboardingLifecycle.retireAdoptedPass()
        freeWeek.setUser(nil)

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

    @discardableResult
    func refreshEntitlements(
        force: Bool = false,
        waitsForPendingIdentity: Bool = false
    ) async -> MonetizationEntitlementRefresh {
        // Only a caller waiting on a verdict is holding a climber behind a spinner, so only that
        // caller spends the budget. The background pass never blocks on identity work anyway.
        guard waitsForPendingIdentity else {
            return await refreshAndScheduleReconciliation(
                waitsForPendingIdentity: false,
                force: force
            )
        }

        return await verdictBudget.resolve {
            await self.refreshAndScheduleReconciliation(
                waitsForPendingIdentity: true,
                force: force
            )
        }
    }

    private func refreshAndScheduleReconciliation(
        waitsForPendingIdentity: Bool,
        force: Bool
    ) async -> MonetizationEntitlementRefresh {
        // Launch and every foreground come through here, which is when a week that ended while the
        // app was suspended has to be noticed.
        freeWeek.reevaluate()

        let refresh = await entitlementService.refreshCustomerInfo(
            waitsForPendingIdentity: waitsForPendingIdentity
        )

        if case .refreshed(let state) = refresh {
            scheduleServerAppAccessReconciliation(for: state, force: force)
        }

        return refresh
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

    private func scheduleServerAppAccessReconciliation(
        for state: MonetizationEntitlementState,
        force: Bool
    ) {
        guard state.hasActiveEntitlement(configuration.revenueCatEntitlementID) else { return }
        Task { @MainActor [appAccessReconciler] in
            await appAccessReconciler.reconcileAppAccess(force: force)
        }
    }

    func retryIdentityResolution() async {
        await entitlementService.retryIdentityResolution()
    }

    @discardableResult
    func restorePurchases(
        for identity: MonetizationIdentityTransition
    ) async throws -> MonetizationEntitlementState {
        beginOnboardingAccessGrantRequest()

        do {
            guard entitlementService.identityGeneration == identity else {
                return .unknown
            }
            let state = try await entitlementService.restorePurchases(for: identity)
            guard entitlementService.identityGeneration == identity else {
                return .unknown
            }
            scheduleServerAppAccessReconciliation(for: state, force: true)

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

    @discardableResult
    func restorePurchases() async throws -> MonetizationEntitlementState {
        guard let identity = identityGeneration else { return .unknown }
        return try await restorePurchases(for: identity)
    }

    @discardableResult
    func adoptPurchaseEntitlementState(
        _ state: MonetizationEntitlementState,
        for identity: MonetizationIdentityTransition
    ) -> Bool {
        // Every purchase Apple completed for this account reaches here, whether or not RevenueCat's
        // answer already carries the entitlement - when it does not, a refresh turns it active
        // without passing back through. Recorded before the state is adopted, because adopting is
        // what turns the entitlement active and lets Home route. The paywall's own `.purchased`
        // outcome cannot be relied on: the same flip retires the paywall attempt, so the outcome
        // that follows is dropped and the grant would stay unattributed until the next launch.
        if entitlementService.identityGeneration == identity {
            recordOnboardingAccessGranted(.purchase)
            recordPurchaseDuringFreeWeek(identity: identity)
        }

        guard entitlementService.adoptTransactionState(state, for: identity) else {
            return false
        }
        scheduleServerAppAccessReconciliation(for: state, force: true)
        return true
    }

    /// Which onboarding led the climber to the gate.
    var onboardingFlowVersion: String {
        onboardingLifecycle.activeFlowVersion
    }

    var pendingPurchaseHold: PendingPurchaseHold? {
        pendingPurchaseHoldStore.hold()
    }

    /// Access that has already landed leaves nothing to wait for, so a verdict that loses the race
    /// with the customer-info stream cannot lock this account's next lapse.
    func holdPendingPurchase(_ hold: PendingPurchaseHold) {
        guard !entitlementState.hasActiveEntitlement(configuration.revenueCatEntitlementID) else {
            return
        }
        pendingPurchaseHoldStore.mark(hold)
    }

    func releasePendingPurchaseHold() {
        pendingPurchaseHoldStore.clear()
    }

    // MARK: - Decline offer replay

    /// The v3 onboarding's decline offer rides on the free week rollout: with either switch off the
    /// gate behaves exactly as it did before the replay existed.
    private var declineOfferReplayIsOn: Bool {
        freeWeek.isEnabled && isOnboardingV3Enabled()
    }

    static func liveOnboardingV3Switch() -> Bool {
        #if DEBUG || STAGING
        if OnboardingV3DebugReplay().forcesFlow { return true }
        #endif
        return RemoteFeatureFlagStore.shared.isEnabled(.onboardingV3)
    }

    /// The first paywall reached the screen of a climber who walked the v3 onboarding, so closing
    /// the app now would lose them the offer the close was about to open.
    func recordAccessGatePaywallShown() {
        guard declineOfferReplayIsOn,
              onboardingFlowVersion == OnboardingAnalyticsContext.currentFlowVersion,
              let userID = identityGeneration?.userID else { return }
        declineOfferReplayStore.markPending(for: userID)
    }

    /// The decline offer reached the screen, by the SDK's chain or by the replay. It is never owed
    /// to this account again.
    func recordDeclineOfferShown() {
        guard let userID = identityGeneration?.userID else { return }
        declineOfferReplayStore.markShown(for: userID)
        declineOfferOwedAtLaunch = nil
    }

    /// Access arrived, a week started, or the climber left: nothing is owed.
    func clearPendingDeclineOffer() {
        declineOfferReplayStore.clearPending()
        declineOfferOwedAtLaunch = nil
    }

    /// Whether this launch owes the climber the decline offer: their first paywall was on screen
    /// when the previous process died and they have not seen the offer since. Asked once, by the
    /// gate that opens first, so a gate that restarts in the same process shows the paywall.
    func takeOwedDeclineOffer() -> Bool {
        guard let owed = declineOfferOwedAtLaunch else { return false }
        guard declineOfferReplayIsOn,
              identityGeneration?.userID == owed,
              !declineOfferReplayStore.hasShown(for: owed),
              !hasAppAccess,
              pendingPurchaseHold == nil else {
            return false
        }
        declineOfferOwedAtLaunch = nil
        return true
    }

    func presentPaywall(
        _ placement: SuperwallPlacement,
        params: [String: Any]? = nil,
        onOutcome: @escaping @MainActor (PaywallPresentationOutcome) -> Void = { _ in }
    ) {
        // The replayed decline offer sells the same access, so a purchase or restore made on it is
        // attributed like one made on the first paywall. Only the first paywall is a funnel step.
        let tracksOnboardingAccess = placement == .appAccessGate || placement == .declineOfferReplay
        guard let presentationIdentity = identityGeneration else {
            if tracksOnboardingAccess {
                recordOnboardingAccessGrantRequestReportedNothing()
            }
            onOutcome(.failed(message: "Ascend is still confirming your account. Try again."))
            return
        }

        LifecycleEventRecorder.shared.recordPaywallReached(
            placement: placement.rawValue,
            expectedUserID: presentationIdentity.userID
        )
        trackPaywallReached(placement, params: params, identity: presentationIdentity)

        if tracksOnboardingAccess {
            beginOnboardingAccessGrantRequest()
        }

        paywallAttemptRevision &+= 1
        let attemptRevision = paywallAttemptRevision
        activePaywallAttempt = (attemptRevision, presentationIdentity)

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
            identity: presentationIdentity,
            onOutcome: { [weak self] outcome in
                guard let self,
                      self.activePaywallAttempt?.revision == attemptRevision,
                      self.activePaywallAttempt?.identity == presentationIdentity,
                      self.identityGeneration == presentationIdentity else {
                    return
                }
                if tracksOnboardingAccess {
                    self.recordOnboardingPaywallOutcome(outcome)
                }
                onOutcome(outcome)
                // The caller may answer a terminal by presenting the next screen - the founder
                // letter after the last decline, the paywall again once a free week is spent - and
                // that presentation is already the active attempt by the time this line runs.
                if outcome.isTerminal, self.activePaywallAttempt?.revision == attemptRevision {
                    self.activePaywallAttempt = nil
                }
            }
        )
    }

    private func invalidatePaywallAttempt() {
        paywallAttemptRevision &+= 1
        activePaywallAttempt = nil
    }

    func cancelPaywallPresentation() {
        invalidatePaywallAttempt()
        paywallPresenter.cancelPresentation()
    }

    #if DEBUG
    func setDebugForcesAppAccessPaywall(_ shouldForce: Bool) {
        debugForcesAppAccessPaywall = shouldForce
    }
    #endif

    private func trackPaywallReached(
        _ placement: SuperwallPlacement,
        params: [String: Any]?,
        identity: MonetizationIdentityTransition
    ) {
        guard let userID = identity.userID else { return }
        let source = params?["source"] as? String
        var parameters: [String: TelemetryValue] = [
            "placement": .string(placement.rawValue)
        ]

        if let source {
            parameters["source"] = .string(source)
        }

        telemetry.track(
            PaywallAnalyticsEvent.diagnosticRecord(
                name: "paywall_reached",
                parameters: parameters
            ),
            ifIdentifiedAs: userID
        )

        guard placement == .appAccessGate else { return }

        // The gate is where every flow hands a climber without access, so it reports under the pass
        // that led there.
        let context = OnboardingAnalyticsContext.paywallHandOff(flowVersion: onboardingFlowVersion)
        telemetry.track(
            OnboardingAnalyticsEvent.paywallReached(
                placement: placement.rawValue,
                source: source,
                context: context
            ),
            ifIdentifiedAs: userID
        )
        OnboardingScreenViewRecorder(lifecycle: onboardingLifecycle).recordIfNeeded(
            context,
            telemetry: telemetry,
            expectedUserID: userID
        )
    }

    /// Starts the free week for the account the gate is showing, and reports it.
    ///
    /// The report lives here, not in the gate: the moment the week lands the route leaves the gate
    /// and cancels everything the gate was waiting on, its own reaction to this answer included.
    func startFreeWeek(
        letterShown: Bool,
        identity: MonetizationIdentityTransition
    ) async -> FreeWeekStartOutcome {
        guard identityGeneration == identity else { return .failed }

        // Read before the call: the week landing completes the onboarding pass, and a completed
        // pass no longer says which flow it was.
        let flowVersion = onboardingFlowVersion
        let outcome = await freeWeek.startFreeWeek()
        if case .started = outcome, let userID = identity.userID {
            clearPendingDeclineOffer()
            freeWeek.rememberStartedFlowVersion(flowVersion)
            telemetry.track(
                FreeWeekAnalyticsEvent.granted(
                    flowVersion: flowVersion,
                    letterShown: letterShown
                ),
                ifIdentifiedAs: userID
            )
        }
        return outcome
    }

    /// The onboarding a climber's free week belongs to. The week outlives the pass that led to it,
    /// so its later events ask the week itself and only fall back to the live pass for a week
    /// another device started.
    var freeWeekFlowVersion: String {
        freeWeek.startedFlowVersion ?? onboardingFlowVersion
    }

    /// A purchase Apple completed while the free week was still running: the week converted.
    private func recordPurchaseDuringFreeWeek(identity: MonetizationIdentityTransition) {
        guard let userID = identity.userID, let daysLeft = freeWeek.daysLeft else { return }

        telemetry.track(
            FreeWeekAnalyticsEvent.purchasedDuringWeek(
                flowVersion: freeWeekFlowVersion,
                daysLeft: daysLeft
            ),
            ifIdentifiedAs: userID
        )
    }

    /// Access that is already active is access this pass never had to ask for, so the request is
    /// only opened when there is something to grant.
    private func beginOnboardingAccessGrantRequest() {
        guard !entitlementStateForRouting.hasActiveEntitlement(
            configuration.revenueCatEntitlementID
        ) else { return }

        onboardingLifecycle.beginAccessGrantRequest()
    }

    private func recordOnboardingAccessGranted(_ reason: OnboardingFlowCompletionReason) {
        onboardingLifecycle.recordAccessGranted(reason)
    }

    /// Entitlement can turn active through the stream a moment before the purchase that caused it
    /// confirms itself, so a pending request is given a short window to be attributed. A grant that
    /// nobody claims in that window - a comp landing while the gate is up - settles as `unknown`
    /// instead of waiting for a relaunch to be mislabelled a purchase.
    private func settleUnattributedAccessGrantIfNeeded(for state: MonetizationEntitlementState) {
        guard state.hasActiveEntitlement(configuration.revenueCatEntitlementID),
              onboardingLifecycle.accessGrantProvenance == .pending,
              unattributedGrantSettleTask == nil else { return }

        unattributedGrantSettleTask = Task { @MainActor [weak self, unattributedGrantSettleDelay, unattributedGrantSleep] in
            try? await unattributedGrantSleep(unattributedGrantSettleDelay)
            guard !Task.isCancelled else { return }
            self?.settleUnattributedAccessGrant()
        }
    }

    private func cancelUnattributedGrantSettle() {
        unattributedGrantSettleTask?.cancel()
        unattributedGrantSettleTask = nil
    }

    private func settleUnattributedAccessGrant() {
        unattributedGrantSettleTask = nil
        guard onboardingLifecycle.accessGrantProvenance == .pending,
              entitlementState.hasActiveEntitlement(configuration.revenueCatEntitlementID) else { return }

        recordOnboardingAccessGranted(.unknown)
    }

    /// Internal seam so a test can wait out the settle window without sleeping through it.
    func settleUnattributedAccessGrantForTesting() async {
        await unattributedGrantSettleTask?.value
    }

    private func recordOnboardingAccessGrantRequestReportedNothing() {
        onboardingLifecycle.recordAccessGrantRequestReportedNothing()
    }

    /// Only an outcome that names how access was granted may attribute one. A dismissal, a skip or
    /// a failure closes the request without naming anything.
    private func recordOnboardingPaywallOutcome(_ outcome: PaywallPresentationOutcome) {
        switch outcome {
        case .purchased:
            recordOnboardingAccessGranted(.purchase)
        case .restored:
            recordOnboardingAccessGranted(.restore)
        case .dismissedWithoutPurchase, .backRequested, .deleteAccountRequested, .signOutRequested,
             .skipped, .failed:
            // Back, delete-account and sign-out are navigations, not grants: like a dismissal each
            // closes the request without naming how access was given, so a later webhook-delayed
            // purchase still attributes.
            recordOnboardingAccessGrantRequestReportedNothing()
        case .presented, .followOnPaywallOpening, .pendingApproval, .verificationUnavailable:
            // Presentation and recoverable transaction states are not access-grant results.
            // The entitlement stream remains authoritative and may still grant access later.
            break
        }
    }
}
