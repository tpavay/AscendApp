import Foundation
import RevenueCat
import SuperwallKit
import Testing
@testable import AscendApp

@MainActor
@Suite(.serialized)
struct HostedPurchaseRecoveryIntegrationTests {
    @Test
    func productionExecutorControllerAndPresenterRoutePendingToOneSafeGateTerminal() async {
        let harness = makeHarness()
        harness.openHostedPresentation()
        harness.contextStore.record(
            placement: "app_access_gate",
            presentationID: harness.presentationID,
            identity: harness.identity,
            productID: harness.productID
        )

        let execution = await harness.executor.executePurchaseWithContext(
            productID: harness.productID
        ) {
            throw NSError(
                domain: ErrorCode.errorDomain,
                code: ErrorCode.paymentPendingError.rawValue
            )
        }
        let result = await harness.controller.resolveHostedExecution(execution)

        #expect(result == .pending)
        #expect(harness.dismissal.count == 1)
        #expect(harness.coordinator.phase == .pendingApproval)
        #expect(harness.coordinator.disablesPurchase)
        #expect(harness.terminals.count == 1)
        #expect(harness.terminals[0].parameters["gate_attempt_id"] != nil)
        #expect(harness.terminals[0].parameters["provider_outcome"] == .string("pending_approval"))

        harness.presenter.handleDismissForTesting(
            revision: harness.presenterRevision,
            result: .declined
        )
        #expect(harness.terminals.count == 1)

        harness.coordinator.entitlementDidChange(.active(["app_access"]))
        #expect(harness.coordinator.phase == .accessConfirmed)
        #expect(harness.coordinator.showsPurchaseControls == false)
    }

    @Test
    func unconfirmedHostedPurchaseReturnsFailedButDismissesIntoVerificationWithoutRepurchase() async {
        let harness = makeHarness()
        harness.openHostedPresentation()
        harness.contextStore.record(
            placement: "app_access_gate",
            presentationID: harness.presentationID,
            identity: harness.identity,
            productID: harness.productID
        )

        let execution = await harness.executor.executePurchaseWithContext(
            productID: harness.productID
        ) {
            RevenueCatPurchaseExecutor.PurchaseResponse(
                userCancelled: false,
                entitlementState: .inactive
            )
        }
        let result = await harness.controller.resolveHostedExecution(execution)

        guard case .failed(let error) = result else {
            Issue.record("Expected the original entitlement-unconfirmed failure")
            return
        }
        #expect(error is RevenueCatPurchaseControllerError)
        #expect(harness.dismissal.count == 1)
        #expect(harness.coordinator.phase == .verificationUnavailable)
        #expect(harness.coordinator.disablesPurchase)
        #expect(harness.terminals.count == 1)
        #expect(
            harness.terminals[0].parameters["provider_outcome"]
                == .string("verification_unavailable")
        )
    }

    @Test
    func staleOrWrongIdentityRecoveryCannotDismissOrMutateTheCurrentPresentation() async {
        let harness = makeHarness()
        harness.openHostedPresentation()
        let staleContext = RevenueCatPurchaseAnalyticsContext(
            placement: "app_access_gate",
            presentationID: "older-presentation"
        )
        let wrongRevision = MonetizationIdentityTransition(
            revision: harness.identity.revision + 1,
            userID: harness.identity.userID
        )

        #expect(await harness.presenter.recoverHostedPurchase(
            .pendingApproval,
            context: staleContext,
            identity: harness.identity
        ) == false)
        #expect(await harness.presenter.recoverHostedPurchase(
            .pendingApproval,
            context: RevenueCatPurchaseAnalyticsContext(
                placement: "app_access_gate",
                presentationID: harness.presentationID
            ),
            identity: wrongRevision
        ) == false)
        #expect(harness.dismissal.count == 0)
        #expect(harness.coordinator.phase == .hostedPresented)
    }

    @Test
    func cancelledQueuedPresentationDismissesIfStillCurrentButStaleCallbackCannotDismissRetry() async {
        let dismissal = ControlledPresenterDismissal()
        let register = PresenterRegistrationRecorder()
        let controller = RevenueCatPurchaseController(isPurchasesConfigured: { false })
        let presenter = SuperwallPaywallPresenter(
            purchaseController: controller,
            startsConfigured: true,
            registerPlacement: register.register,
            dismissPresentation: dismissal.dismiss
        )
        let identity = MonetizationIdentityTransition(revision: 1, userID: "user-a")
        let oldRevision = presenter.beginPresentationAttemptForTesting(
            identity: identity,
            onOutcome: { _ in }
        )

        presenter.cancelPresentation()
        await dismissal.waitUntilCount(1)
        #expect(presenter.handlePresentationBegan(
            revision: oldRevision,
            presentationID: "late-old"
        ) == false)
        dismissal.resume(call: 1)
        await dismissal.waitUntilCount(2)
        dismissal.resume(call: 2)

        presenter.register(placement: .appAccessGate, identity: identity) { _ in }
        await register.waitUntilCount(1)
        let retryRevision = presenter.beginPresentationAttemptForTesting(
            identity: identity,
            onOutcome: { _ in }
        )
        #expect(presenter.handlePresentationBegan(
            revision: retryRevision,
            presentationID: "retry"
        ))

        let countBeforeStaleCallback = dismissal.count
        #expect(presenter.handlePresentationBegan(
            revision: oldRevision,
            presentationID: "late-old-again"
        ) == false)
        await Task.yield()
        #expect(dismissal.count == countBeforeStaleCallback)
    }

    @Test
    func recoveryDismissalSerializesIdentityChangeAndReplacementRegistration() async {
        let dismissal = ControlledPresenterDismissal()
        let register = PresenterRegistrationRecorder()
        let presenter = SuperwallPaywallPresenter(
            purchaseController: RevenueCatPurchaseController(isPurchasesConfigured: { false }),
            startsConfigured: true,
            registerPlacement: register.register,
            dismissPresentation: dismissal.dismiss
        )
        let identity = MonetizationIdentityTransition(revision: 1, userID: "user-a")
        var outcomes: [PaywallPresentationOutcome] = []
        let recoveringRevision = presenter.beginPresentationAttemptForTesting(
            identity: identity,
            onOutcome: { outcomes.append($0) }
        )
        #expect(presenter.handlePresentationBegan(
            revision: recoveringRevision,
            presentationID: "recovering"
        ))

        let recoveryTask = Task { @MainActor in
            await presenter.recoverHostedPurchase(
                .pendingApproval,
                context: RevenueCatPurchaseAnalyticsContext(
                    placement: "app_access_gate",
                    presentationID: "recovering"
                ),
                identity: identity
            )
        }
        await dismissal.waitUntilCount(1)
        #expect(outcomes == [.pendingApproval])

        presenter.cancelPresentation()
        let replacementIdentity = MonetizationIdentityTransition(revision: 2, userID: "user-b")
        presenter.register(placement: .appAccessGate, identity: replacementIdentity) { _ in }
        await Task.yield()
        #expect(register.count == 0)

        dismissal.resume(call: 1)
        await dismissal.waitUntilCount(2)
        #expect(register.count == 0)
        dismissal.resume(call: 2)
        await register.waitUntilCount(1)
        #expect(await recoveryTask.value)

        let replacementRevision = presenter.beginPresentationAttemptForTesting(
            identity: replacementIdentity,
            onOutcome: { _ in }
        )
        #expect(presenter.handlePresentationBegan(
            revision: replacementRevision,
            presentationID: "replacement"
        ))
        let countBeforeStaleCallback = dismissal.count
        #expect(presenter.handlePresentationBegan(
            revision: recoveringRevision,
            presentationID: "recovering-late"
        ) == false)
        await Task.yield()
        #expect(dismissal.count == countBeforeStaleCallback)
        #expect(outcomes == [.pendingApproval])
    }

    @Test
    func sdkDidPresentBeforeHandlerRecordsShownOnceForTheCapturedAccountOnly() {
        let sink = IdentityAttributingTelemetrySink()
        let telemetry = TelemetryManager(
            sinks: [sink],
            crashlyticsReporter: NoopCrashlyticsReporter(),
            collectionEnabledOverride: true,
            identityStore: makeTestIdentityStore()
        )
        telemetry.configure()
        telemetry.setUserId("user-a")
        let contextStore = PaywallTransactionContextStore()
        let currentLifecycleUserID = CurrentLifecycleUserID("user-a")
        var attemptedLifecycleUserIDs: [String] = []
        var deliveredLifecycleTypes: [String] = []
        let presenter = SuperwallPaywallPresenter(
            purchaseController: RevenueCatPurchaseController(isPurchasesConfigured: { false }),
            telemetry: telemetry,
            transactionContextStore: contextStore,
            startsConfigured: true,
            registerPlacement: { _, _, _ in },
            dismissPresentation: {},
            recordLifecyclePaywallShown: { _, expectedUserID in
                attemptedLifecycleUserIDs.append(expectedUserID)
                if expectedUserID == currentLifecycleUserID.value {
                    deliveredLifecycleTypes.append("shown")
                }
            },
            recordLifecyclePaywallDismissed: { _, _, expectedUserID in
                attemptedLifecycleUserIDs.append(expectedUserID)
                if expectedUserID == currentLifecycleUserID.value {
                    deliveredLifecycleTypes.append("dismissed")
                }
            }
        )
        let identityA = MonetizationIdentityTransition(revision: 1, userID: "user-a")
        let revision = presenter.beginPresentationAttemptForTesting(
            identity: identityA,
            onOutcome: { _ in }
        )
        let context = PaywallAnalyticsContext(
            placement: SuperwallPlacement.appAccessGate.rawValue,
            paywallIdentifier: "gate-paywall",
            paywallName: "Gate",
            presentedBy: "placement",
            isFreeTrialAvailable: true,
            presentationID: "presentation-a",
            dismissReason: "close_button"
        )
        presenter.handlePaywallDidPresentFromDelegate(context: context)
        #expect(sink.attributions.isEmpty)
        #expect(attemptedLifecycleUserIDs.isEmpty)

        #expect(presenter.handlePresentationFromHandler(
            revision: revision,
            context: context
        ))
        #expect(presenter.handlePresentationFromHandler(
            revision: revision,
            context: context
        ))

        telemetry.setUserId("user-b")
        currentLifecycleUserID.value = "user-b"
        _ = presenter.beginPresentationAttemptForTesting(
            identity: MonetizationIdentityTransition(revision: 2, userID: "user-b"),
            onOutcome: { _ in }
        )
        presenter.handlePaywallDidPresentFromDelegate(context: context)
        #expect(presenter.handlePresentationFromHandler(
            revision: revision,
            context: context
        ) == false)
        presenter.handlePaywallDismissed(context: context)
        presenter.handleTransactionStarted(context: context, productID: "ascend_yearly")
        presenter.handleTransactionAbandoned(context: context, productID: "ascend_yearly")

        #expect(sink.attributions.map(\.name) == ["paywall_shown"])
        #expect(sink.attributions.map(\.userID) == ["user-a"])
        #expect(attemptedLifecycleUserIDs == ["user-a", "user-a"])
        #expect(deliveredLifecycleTypes == ["shown"])
        let storedContext = contextStore.takeContext(for: "ascend_yearly")
        #expect(storedContext?.identity == identityA)
        #expect(storedContext?.analytics.presentationID == "presentation-a")
        #expect(sink.attributions.allSatisfy {
            $0.parameters["user_id"] == nil &&
                $0.parameters["identity_revision"] == nil
        })
    }

    private func makeHarness() -> HostedHarness {
        let identity = MonetizationIdentityTransition(revision: 41, userID: "hosted-user")
        let contextStore = PaywallTransactionContextStore()
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let telemetry = makeTestTelemetry(sink: sink)
        telemetry.setUserId("hosted-user")
        let executor = RevenueCatPurchaseExecutor(
            telemetry: telemetry,
            transactionContextStore: contextStore,
            entitlementID: "app_access",
            applySubscriptionStatus: { _ in },
            refreshEntitlementState: { .refreshed(.inactive) },
            currentIdentityGeneration: { identity },
            adoptEntitlementState: { _, candidate in candidate == identity }
        )
        let router = HostedRecoveryRouterBox()
        let controller = RevenueCatPurchaseController(
            executor: executor,
            isPurchasesConfigured: { false },
            recoveryRouter: router.route
        )
        let dismissal = ImmediatePresenterDismissal()
        let presenter = SuperwallPaywallPresenter(
            purchaseController: controller,
            startsConfigured: true,
            registerPlacement: { _, _, _ in },
            dismissPresentation: dismissal.dismiss
        )
        router.presenter = presenter
        let entitlements = HostedEntitlementService(identity: identity)
        let manager = MonetizationManager(
            configuration: HostedHarness.configuration,
            entitlementService: entitlements,
            paywallPresenter: presenter,
            telemetry: telemetry,
            userDefaults: UserDefaults(
                suiteName: "HostedPurchaseRecoveryIntegrationTests-\(UUID().uuidString)"
            )!
        )
        let coordinator = AppAccessPaywallCoordinator(
            monetizationManager: manager,
            nativeProvider: HostedNativeProvider(),
            telemetry: telemetry,
            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }
        )
        let presentationID = "presentation-123"
        return HostedHarness(
            identity: identity,
            presentationID: presentationID,
            productID: "ascend_staging_yearly",
            coordinator: coordinator,
            presenter: presenter,
            controller: controller,
            executor: executor,
            contextStore: contextStore,
            dismissal: dismissal,
            sink: sink
        )
    }
}

@MainActor
private final class CurrentLifecycleUserID {
    var value: String

    init(_ value: String) {
        self.value = value
    }
}

@MainActor
private final class HostedHarness {
    static let configuration = MonetizationConfiguration(infoDictionary: [
        MonetizationConfiguration.revenueCatAPIKeyInfoKey: "appl_test",
        MonetizationConfiguration.superwallAPIKeyInfoKey: "pk_test",
        MonetizationConfiguration.revenueCatYearlyProductIDInfoKey: "ascend_staging_yearly",
        MonetizationConfiguration.revenueCatMonthlyProductIDInfoKey: "ascend_staging_monthly",
        MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "NO"
    ])

    let identity: MonetizationIdentityTransition
    let presentationID: String
    private(set) var presenterRevision: UInt = 0
    let productID: String
    let coordinator: AppAccessPaywallCoordinator
    let presenter: SuperwallPaywallPresenter
    let controller: RevenueCatPurchaseController
    let executor: RevenueCatPurchaseExecutor
    let contextStore: PaywallTransactionContextStore
    let dismissal: ImmediatePresenterDismissal
    let sink: InMemoryTelemetrySink

    init(
        identity: MonetizationIdentityTransition,
        presentationID: String,
        productID: String,
        coordinator: AppAccessPaywallCoordinator,
        presenter: SuperwallPaywallPresenter,
        controller: RevenueCatPurchaseController,
        executor: RevenueCatPurchaseExecutor,
        contextStore: PaywallTransactionContextStore,
        dismissal: ImmediatePresenterDismissal,
        sink: InMemoryTelemetrySink
    ) {
        self.identity = identity
        self.presentationID = presentationID
        self.productID = productID
        self.coordinator = coordinator
        self.presenter = presenter
        self.controller = controller
        self.executor = executor
        self.contextStore = contextStore
        self.dismissal = dismissal
        self.sink = sink
    }

    var terminals: [EnvelopedTelemetryRecord] {
        sink.records.filter { $0.name == "app_access_gate_attempt_terminal" }
    }

    func openHostedPresentation() {
        coordinator.start()
        coordinator.handleHostedOutcomeForTesting(.presented)
        presenterRevision = presenter.beginPresentationAttemptForTesting(
            identity: identity,
            onOutcome: { [weak coordinator] outcome in
                coordinator?.handleHostedOutcomeForTesting(outcome)
            }
        )
        #expect(presenter.handlePresentationBegan(
            revision: presenterRevision,
            presentationID: presentationID
        ))
        #expect(coordinator.phase == .hostedPresented)
    }
}

@MainActor
private final class HostedRecoveryRouterBox {
    weak var presenter: SuperwallPaywallPresenter?

    func route(
        recovery: HostedPurchaseRecovery,
        context: RevenueCatPurchaseAnalyticsContext,
        identity: MonetizationIdentityTransition
    ) async -> Bool {
        guard let presenter else { return false }
        return await presenter.recoverHostedPurchase(
            recovery,
            context: context,
            identity: identity
        )
    }
}

@MainActor
private final class ImmediatePresenterDismissal {
    private(set) var count = 0
    func dismiss() async { count += 1 }
}

@MainActor
private final class ControlledPresenterDismissal {
    private(set) var count = 0
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var observers: [CheckedContinuation<Void, Never>] = []

    func dismiss() async {
        count += 1
        observers.forEach { $0.resume() }
        observers = []
        await withCheckedContinuation { continuations[count] = $0 }
    }

    func waitUntilCount(_ expected: Int) async {
        if count >= expected { return }
        await withCheckedContinuation { observers.append($0) }
        if count < expected { await waitUntilCount(expected) }
    }

    func resume(call: Int) {
        continuations.removeValue(forKey: call)?.resume()
    }
}

@MainActor
private final class PresenterRegistrationRecorder {
    private(set) var count = 0
    private var observers: [CheckedContinuation<Void, Never>] = []

    func register(
        placement: String,
        params: [String: Any]?,
        handler: PaywallPresentationHandler
    ) {
        count += 1
        observers.forEach { $0.resume() }
        observers = []
    }

    func waitUntilCount(_ expected: Int) async {
        if count >= expected { return }
        await withCheckedContinuation { observers.append($0) }
        if count < expected { await waitUntilCount(expected) }
    }
}

@MainActor
private final class HostedEntitlementService: EntitlementServicing {
    var entitlementState: MonetizationEntitlementState = .inactive
    var hasFailedIdentityResolution = false
    var identityGeneration: MonetizationIdentityTransition?
    var isConfigured = true

    init(identity: MonetizationIdentityTransition) { identityGeneration = identity }
    func configure(configuration: MonetizationConfiguration) {}
    func refreshCustomerInfo(waitsForPendingIdentity: Bool) async -> MonetizationEntitlementRefresh {
        .refreshed(entitlementState)
    }
    func prepareIdentity(_ customer: MonetizationCustomerIdentity) -> MonetizationIdentityTransition {
        identityGeneration!
    }
    func identify(_ customer: MonetizationCustomerIdentity, transition: MonetizationIdentityTransition) async {}
    func prepareIdentityReset() -> MonetizationIdentityTransition { .init(revision: 0, userID: nil) }
    func resetIdentity(transition: MonetizationIdentityTransition) async {}
    func retryIdentityResolution() async {}
    func adoptTransactionState(_ state: MonetizationEntitlementState, for identity: MonetizationIdentityTransition) -> Bool {
        guard identityGeneration == identity else { return false }
        entitlementState = state
        return true
    }
    func restorePurchases(for identity: MonetizationIdentityTransition) async -> MonetizationEntitlementState { entitlementState }
    func restorePurchases() async -> MonetizationEntitlementState { entitlementState }
}

@MainActor
private final class HostedNativeProvider: NativeSubscriptionProviding {
    func loadPlans() async throws -> [NativeSubscriptionPlan] { [] }
    func purchase(planID: String) async -> PurchaseResult { .cancelled }
}
