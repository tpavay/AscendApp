import Foundation
import Testing
@testable import AscendApp

/// Grant provenance is persisted with the pass it describes, so any test that reads a completion
/// reason has to own its storage rather than inherit whatever the simulator's shared defaults hold.
@MainActor
private struct OnboardingLifecycleFixture {
    let suiteName: String
    let defaults: UserDefaults

    init() {
        suiteName = "MonetizationManagerPaywallTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    func makeLifecycle() -> OnboardingFlowAnalyticsCoordinator {
        OnboardingFlowAnalyticsCoordinator(userDefaults: defaults)
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

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
        let fixture = OnboardingLifecycleFixture()
        defer { fixture.cleanUp() }

        let manager = MonetizationManager(
            configuration: MonetizationConfiguration(
                infoDictionary: [
                    MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "NO"
                ]
            ),
            entitlementService: EntitlementServiceStub(
                entitlementState: .active(["app_access"])
            ),
            paywallPresenter: PaywallPresenterSpy(),
            onboardingLifecycle: fixture.makeLifecycle()
        )

        #expect(manager.hasAppAccess)
        #expect(manager.onboardingCompletionReasonForActiveAccess == .existingEntitlement)
    }

    @Test
    func purchaseReasonIsAttributedFromTheReportedPaywallOutcome() {
        let fixture = OnboardingLifecycleFixture()
        defer { fixture.cleanUp() }

        let entitlementService = EntitlementServiceStub()
        let paywallPresenter = PaywallPresenterSpy()
        let manager = MonetizationManager(
            entitlementService: entitlementService,
            paywallPresenter: paywallPresenter,
            onboardingLifecycle: fixture.makeLifecycle()
        )

        manager.presentPaywall(.appAccessGate, params: ["source": "onboarding"])
        paywallPresenter.send(.presented)
        paywallPresenter.send(.purchased)
        entitlementService.setEntitlementState(.active(["app_access"]))

        #expect(manager.onboardingCompletionReasonForActiveAccess == .purchase)
    }

    /// The entitlement can turn active before Superwall says how it was granted. Completion is
    /// persisted the first time a reason exists, so answering early would bank a guess that the
    /// real outcome arrives too late to correct.
    @Test
    func noReasonIsReportedWhileThePaywallOutcomeIsStillPending() {
        let fixture = OnboardingLifecycleFixture()
        defer { fixture.cleanUp() }

        let entitlementService = EntitlementServiceStub()
        let paywallPresenter = PaywallPresenterSpy()
        let manager = MonetizationManager(
            entitlementService: entitlementService,
            paywallPresenter: paywallPresenter,
            onboardingLifecycle: fixture.makeLifecycle()
        )

        manager.presentPaywall(.appAccessGate, params: ["source": "onboarding"])
        paywallPresenter.send(.presented)
        entitlementService.setEntitlementState(.active(["app_access"]))

        #expect(manager.onboardingCompletionReasonForActiveAccess == nil)

        paywallPresenter.send(.restored)

        #expect(manager.onboardingCompletionReasonForActiveAccess == .restore)
    }

    /// The same ordering through the restore call: the entitlement can flip while the restore is
    /// still in flight, and the answer has to wait for what the restore itself reports.
    @Test
    func noReasonIsReportedWhileARestoreIsStillInFlight() async throws {
        let fixture = OnboardingLifecycleFixture()
        defer { fixture.cleanUp() }

        let entitlementService = EntitlementServiceStub()
        entitlementService.restoredState = .active(["app_access"])
        let manager = MonetizationManager(
            entitlementService: entitlementService,
            paywallPresenter: PaywallPresenterSpy(),
            onboardingLifecycle: fixture.makeLifecycle()
        )

        entitlementService.onRestoreStarted = {
            entitlementService.setEntitlementState(.active(["app_access"]))
            #expect(manager.onboardingCompletionReasonForActiveAccess == nil)
        }

        try await manager.restorePurchases()

        #expect(manager.onboardingCompletionReasonForActiveAccess == .restore)
    }

    /// A build with no Superwall key never presents anything, so the request has to close itself or
    /// the climber waits on a result that will never arrive.
    @Test
    func anUnpresentablePaywallClosesItsOwnRequest() {
        let fixture = OnboardingLifecycleFixture()
        defer { fixture.cleanUp() }

        let entitlementService = EntitlementServiceStub()
        let manager = MonetizationManager(
            entitlementService: entitlementService,
            paywallPresenter: PaywallPresenterSpy(isConfigured: false),
            onboardingLifecycle: fixture.makeLifecycle()
        )

        manager.presentPaywall(.appAccessGate, params: ["source": "onboarding"])
        entitlementService.setEntitlementState(.active(["app_access"]))

        #expect(manager.onboardingCompletionReasonForActiveAccess == .purchase)
    }

    /// A dismissal, a skip or a failure is not evidence that the climber already owned access. If
    /// the entitlement turns on afterwards - a webhook-delayed purchase, a Superwall presentation
    /// that reported skip while the purchase still went through - the grant this pass asked for is
    /// what turned it on.
    @Test
    func accessGrantedAfterAPaywallOutcomeThatReportedNothingIsStillAPurchase() {
        let fixture = OnboardingLifecycleFixture()
        defer { fixture.cleanUp() }

        let entitlementService = EntitlementServiceStub()
        let paywallPresenter = PaywallPresenterSpy()
        let manager = MonetizationManager(
            entitlementService: entitlementService,
            paywallPresenter: paywallPresenter,
            onboardingLifecycle: fixture.makeLifecycle()
        )

        manager.presentPaywall(.appAccessGate, params: ["source": "onboarding"])
        paywallPresenter.send(.skipped(reason: "no_audience_match"))
        entitlementService.setEntitlementState(.active(["app_access"]))

        #expect(manager.onboardingCompletionReasonForActiveAccess == .purchase)
    }

    @Test
    func restoreThatFoundNothingDoesNotMakeALaterGrantLookPreExisting() async throws {
        let fixture = OnboardingLifecycleFixture()
        defer { fixture.cleanUp() }

        let entitlementService = EntitlementServiceStub()
        let manager = MonetizationManager(
            entitlementService: entitlementService,
            paywallPresenter: PaywallPresenterSpy(),
            onboardingLifecycle: fixture.makeLifecycle()
        )

        try await manager.restorePurchases()
        entitlementService.setEntitlementState(.active(["app_access"]))

        #expect(manager.onboardingCompletionReasonForActiveAccess == .purchase)
    }

    @Test
    func restoreReasonIsRecordedOnlyAfterRestoredAccessIsActive() async throws {
        let fixture = OnboardingLifecycleFixture()
        defer { fixture.cleanUp() }

        let entitlementService = EntitlementServiceStub()
        entitlementService.restoredState = .active(["app_access"])
        let manager = MonetizationManager(
            entitlementService: entitlementService,
            paywallPresenter: PaywallPresenterSpy(),
            onboardingLifecycle: fixture.makeLifecycle()
        )

        #expect(manager.onboardingCompletionReasonForActiveAccess == nil)

        try await manager.restorePurchases()
        // The restore is what turned access on, so the service reports it from here.
        entitlementService.setEntitlementState(.active(["app_access"]))

        #expect(manager.onboardingCompletionReasonForActiveAccess == .restore)
    }

    /// A second account replaces the pass outright, and the grant provenance is part of that pass,
    /// so nothing the previous climber's paywall did may attribute the next climber's access.
    @Test
    func replacingTheAccountClearsTheGrantEvidenceOfThePreviousPass() {
        let fixture = OnboardingLifecycleFixture()
        defer { fixture.cleanUp() }

        let entitlementService = EntitlementServiceStub()
        let paywallPresenter = PaywallPresenterSpy()
        let manager = MonetizationManager(
            entitlementService: entitlementService,
            paywallPresenter: paywallPresenter,
            onboardingLifecycle: fixture.makeLifecycle()
        )

        manager.prepareIdentity(userId: "climber-a")
        manager.presentPaywall(.appAccessGate, params: ["source": "onboarding"])
        paywallPresenter.send(.purchased)

        manager.prepareIdentity(userId: "climber-b")
        entitlementService.setEntitlementState(.active(["app_access"]))

        #expect(manager.onboardingCompletionReasonForActiveAccess == .existingEntitlement)
    }

    /// The paywall screen view is the one step the monetization layer owns, so it has to read the
    /// resume marker from the injected lifecycle rather than from device-wide state.
    @Test
    func paywallScreenViewReadsTheResumeMarkerFromTheInjectedLifecycle() {
        let suiteName = "MonetizationManagerPaywallTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        let lifecycle = OnboardingFlowAnalyticsCoordinator(
            userDefaults: defaults,
            telemetry: telemetry
        )
        lifecycle.recordFlowStartedIfNeeded(
            context: PostAuthOnboardingStage.stairStepperBaseline.analyticsContext
        )

        let manager = MonetizationManager(
            entitlementService: EntitlementServiceStub(),
            paywallPresenter: PaywallPresenterSpy(),
            telemetry: telemetry,
            onboardingLifecycle: lifecycle
        )
        manager.presentPaywall(.appAccessGate, params: ["source": "onboarding"])

        let paywallView = sink.records.first {
            $0.name == "onboarding_screen_viewed"
                && $0.parameters["screen_id"] == .string("paywall")
        }
        #expect(paywallView?.parameters["resume"] == .bool(true))
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
            updatePresentation: nil,
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
            updatePresentation: nil,
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
    var identityGeneration: MonetizationIdentityTransition? { currentTransition }
    var isConfigured = true
    var identityResolution = MonetizationEntitlementState.inactive
    var restoreError: (any Error)?
    /// A restore resolves its own answer even when a pending identity transition holds
    /// `entitlementState` at `.unknown`, so the two are settable independently.
    var restoredState: MonetizationEntitlementState?
    /// Runs inside the restore, so a test can flip the entitlement while the call is still in
    /// flight and assert what the manager reports at that moment.
    var onRestoreStarted: (@MainActor () -> Void)?
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

    @discardableResult
    func refreshCustomerInfo(
        waitsForPendingIdentity: Bool
    ) async -> MonetizationEntitlementRefresh {
        .refreshed(entitlementState)
    }

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

    @discardableResult
    func restorePurchases() async throws -> MonetizationEntitlementState {
        onRestoreStarted?()

        if let restoreError {
            throw restoreError
        }

        return restoredState ?? entitlementState
    }

    func setEntitlementState(_ state: MonetizationEntitlementState) {
        entitlementState = state
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
