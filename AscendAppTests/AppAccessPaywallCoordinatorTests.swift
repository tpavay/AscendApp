import Foundation
import enum SuperwallKit.PurchaseResult
import Testing
@testable import AscendApp

@MainActor
@Suite(.serialized)
struct AppAccessPaywallCoordinatorTests {
    @Test
    func missingHostedCallbackCancelsPresentationAndLoadsNativeFallback() async {
        let harness = makeHarness(sleep: { _ in })

        harness.coordinator.start()
        await harness.provider.waitUntilLoadCount(1)
        await waitUntil { harness.coordinator.phase == .nativeReady }

        #expect(harness.presenter.cancelCount == 1)
        #expect(harness.coordinator.showsPurchaseControls)
        let terminals = harness.sink.records.filter {
            $0.name == "app_access_gate_attempt_terminal"
        }
        #expect(terminals.count == 1)
        #expect(terminals[0].parameters["provider_outcome"] == .string("native_ready"))
        #expect(terminals[0].parameters["recovery_path"] == .string("native"))
        #expect(terminals[0].parameters["recovery_reason"] == .string("watchdog_timeout"))
        #expect(terminals[0].parameters["identity_match"] == .bool(true))
        #expect(terminals[0].parameters["entitlement_active"] == .bool(false))
        if case .string(let attemptID) = terminals[0].parameters["gate_attempt_id"] {
            #expect(UUID(uuidString: attemptID) != nil)
        } else {
            Issue.record("Gate terminal must carry a bounded attempt correlation ID")
        }
        #expect(terminals[0].parameters["storekit_receipt_name"] != nil)
    }

    @Test
    func presentedCallbackCancelsOpeningDeadlineAndRemainsHosted() async {
        let presenter = CoordinatorPaywallPresenter(automaticOutcome: .presented)
        let harness = makeHarness(presenter: presenter, sleep: { _ in })

        harness.coordinator.start()
        await Task.yield()

        #expect(harness.coordinator.phase == .hostedPresented)
        #expect(harness.provider.loadCount == 0)
        #expect(harness.presenter.cancelCount == 0)
    }

    @Test
    func cancellationPreventsLateNativeLoadAndHostedCallbackMutation() async {
        let provider = CoordinatorNativeProvider(suspendsPlanLoad: true)
        let harness = makeHarness(provider: provider)
        harness.coordinator.start()
        harness.presenter.send(.skipped(reason: "test"), registration: 0)
        await provider.waitUntilLoadCount(1)
        let cancelledPhase = harness.coordinator.phase

        harness.coordinator.cancelOwnedWork()
        provider.completePlanLoad()
        harness.presenter.send(.dismissedWithoutPurchase, registration: 0)
        await Task.yield()

        #expect(cancelledPhase == .loadingNative)
        #expect(harness.coordinator.phase == cancelledPhase)
        #expect(harness.coordinator.plans.isEmpty)
    }

    @Test
    func retryIgnoresAnOlderSlowNativePlanLoad() async {
        let provider = CoordinatorNativeProvider(suspendsPlanLoad: true)
        let harness = makeHarness(provider: provider)
        harness.coordinator.start()
        harness.presenter.send(.skipped(reason: "first"), registration: 0)
        await provider.waitUntilLoadCount(1)

        harness.coordinator.retryHosted()
        harness.presenter.send(.skipped(reason: "retry"), registration: 1)
        await provider.waitUntilLoadCount(2)
        provider.completePlanLoad(at: 1)
        await waitUntil { harness.coordinator.phase == .nativeReady }

        provider.completePlanLoad(
            with: [
                NativeSubscriptionPlan(
                    id: "stale_product",
                    title: "Stale",
                    localizedPrice: "$0.00",
                    renewalDescription: "Stale provider result.",
                    trialDescription: nil
                )
            ]
        )
        await Task.yield()

        #expect(harness.coordinator.phase == .nativeReady)
        #expect(harness.coordinator.plans.count == 2)
        #expect(harness.coordinator.plans.contains { $0.id == "stale_product" } == false)
    }

    @Test
    func nativePlanDeadlineFailsActionablyAndALateOldLoadCannotBeatRetry() async {
        let provider = CoordinatorNativeProvider(suspendsPlanLoad: true)
        let deadline = CoordinatorControlledSleep()
        let harness = makeHarness(provider: provider, nativeLoadSleep: deadline.sleep)

        harness.coordinator.start()
        harness.presenter.send(.skipped(reason: "first"), registration: 0)
        await provider.waitUntilLoadCount(1)
        await deadline.waitUntilCallCount(1)
        deadline.fire(call: 1)
        await waitUntil { harness.coordinator.phase == .failed }

        #expect(harness.coordinator.statusMessage?.contains("too long") == true)
        #expect(harness.coordinator.disablesRestore == false)
        #expect(harness.coordinator.showsPurchaseControls == false)

        harness.coordinator.retryHosted()
        harness.presenter.send(.skipped(reason: "retry"), registration: 1)
        await provider.waitUntilLoadCount(2)
        provider.completePlanLoad(at: 1)
        await waitUntil { harness.coordinator.phase == .nativeReady }

        provider.completePlanLoad(
            with: [.init(
                id: "stale",
                title: "Stale",
                localizedPrice: "$0",
                renewalDescription: "Stale",
                trialDescription: nil
            )],
            at: 0
        )
        await Task.yield()

        #expect(harness.coordinator.phase == .nativeReady)
        #expect(harness.coordinator.plans.contains { $0.id == "stale" } == false)
    }

    @Test
    func restoreInFlightRefusesPlanSelectionAndProgrammaticPurchase() async {
        let identity = MonetizationIdentityTransition(revision: 1, userID: "user-a")
        let restorer = CoordinatorRestoreProvider(identity: identity)
        let restoreService = AppAccessRestoreService(
            telemetry: makeTestTelemetry(
                sink: InMemoryTelemetrySink(destination: .analytics)
            ),
            entitlementID: "app_access",
            restorer: { restorer }
        )
        let harness = makeHarness(identity: identity, restoreService: restoreService)
        await openNativePlans(harness)
        let originalSelection = harness.coordinator.selectedPlanID

        harness.coordinator.restore()
        await restorer.waitUntilStarted()
        harness.coordinator.selectPlan("ascend_staging_monthly")
        harness.coordinator.purchaseSelectedPlan()

        #expect(harness.coordinator.restoreState == .restoring)
        #expect(harness.coordinator.selectedPlanID == originalSelection)
        #expect(harness.provider.purchaseCount == 0)

        restorer.complete(.inactive)
        await waitUntil { harness.coordinator.restoreState == .noPurchasesFound }
        #expect(harness.coordinator.disablesPurchase == false)
    }

    @Test(arguments: [
        PaywallPresentationOutcome.skipped(reason: "rule"),
        PaywallPresentationOutcome.failed(message: "provider"),
        PaywallPresentationOutcome.dismissedWithoutPurchase
    ])
    func hostedTerminalLoadsNativeFallback(
        outcome: PaywallPresentationOutcome
    ) async {
        let harness = makeHarness()
        harness.coordinator.start()

        harness.presenter.send(outcome, registration: 0)
        await harness.provider.waitUntilLoadCount(1)
        await waitUntil { harness.coordinator.phase == .nativeReady }

        #expect(harness.coordinator.showsPurchaseControls)
    }

    @Test(arguments: [
        PurchaseResult.pending,
        PurchaseResult.failed(RevenueCatPurchaseControllerError.entitlementUnconfirmed)
    ])
    func pendingAndUnconfirmedPurchaseNeverInviteRepurchase(
        result: PurchaseResult
    ) async {
        let provider = CoordinatorNativeProvider(automaticPurchaseResult: result)
        let harness = makeHarness(provider: provider)
        await openNativePlans(harness)

        harness.coordinator.selectPlan("ascend_staging_yearly")
        harness.coordinator.purchaseSelectedPlan()
        await provider.waitUntilPurchaseCount(1)
        await waitUntil {
            harness.coordinator.phase == .pendingApproval ||
                harness.coordinator.phase == .verificationUnavailable
        }

        #expect(harness.coordinator.disablesPurchase)
        #expect(!harness.coordinator.showsPurchaseControls)

        harness.coordinator.entitlementDidChange(.active(["app_access"]))
        #expect(harness.coordinator.phase == .accessConfirmed)
    }

    @Test
    func cancelledPurchaseReturnsToPlans() async {
        let provider = CoordinatorNativeProvider(automaticPurchaseResult: .cancelled)
        let harness = makeHarness(provider: provider)
        await openNativePlans(harness)

        harness.coordinator.selectPlan("ascend_staging_yearly")
        harness.coordinator.purchaseSelectedPlan()
        await provider.waitUntilPurchaseCount(1)
        await waitUntil { harness.coordinator.phase == .nativeReady }

        #expect(harness.coordinator.showsPurchaseControls)
    }

    @Test
    func stalePurchaseCompletionCannotConfirmAccessForANewIdentity() async {
        let harness = makeHarness()
        harness.coordinator.start()
        harness.presenter.send(.skipped(reason: "test"), registration: 0)
        await harness.provider.waitUntilLoadCount(1)
        await waitUntil { harness.coordinator.phase == .nativeReady }

        harness.coordinator.selectPlan("ascend_staging_yearly")
        harness.coordinator.purchaseSelectedPlan()
        await harness.provider.waitUntilPurchaseCount(1)

        harness.entitlements.identityGeneration = MonetizationIdentityTransition(
            revision: 2,
            userID: "user-b"
        )
        harness.coordinator.identityDidChange()
        harness.provider.completePurchase(.purchased)
        await Task.yield()

        #expect(harness.coordinator.phase == .openingHosted)
        #expect(!harness.coordinator.showsPurchaseControls)
    }

    @Test
    func staleRestoreCompletionCannotConfirmAccessForANewIdentity() async {
        let identity = MonetizationIdentityTransition(revision: 1, userID: "user-a")
        let restorer = CoordinatorRestoreProvider(identity: identity)
        let restoreService = AppAccessRestoreService(
            telemetry: makeTestTelemetry(
                sink: InMemoryTelemetrySink(destination: .analytics)
            ),
            entitlementID: "app_access",
            restorer: { restorer }
        )
        let harness = makeHarness(identity: identity, restoreService: restoreService)

        harness.coordinator.restore()
        await restorer.waitUntilStarted()

        let newIdentity = MonetizationIdentityTransition(revision: 2, userID: "user-b")
        harness.entitlements.identityGeneration = newIdentity
        restorer.identityGeneration = newIdentity
        harness.coordinator.identityDidChange()
        restorer.complete(.active(["app_access"]))
        await Task.yield()

        #expect(harness.coordinator.phase == .openingHosted)
        #expect(harness.coordinator.restoreState == .idle)
    }

    @Test
    func activeEntitlementRetiresLateNativeLoadAndHostedCallbacks() async {
        let provider = CoordinatorNativeProvider(suspendsPlanLoad: true)
        let harness = makeHarness(provider: provider)
        harness.coordinator.start()
        harness.presenter.send(.skipped(reason: "test"), registration: 0)
        await provider.waitUntilLoadCount(1)

        harness.coordinator.entitlementDidChange(.active(["app_access"]))
        provider.completePlanLoad()
        harness.presenter.send(.dismissedWithoutPurchase, registration: 0)
        await Task.yield()

        #expect(harness.coordinator.phase == .accessConfirmed)
        #expect(!harness.coordinator.showsPurchaseControls)
        #expect(harness.coordinator.disablesPurchase)
    }

    @Test
    func identityChangeRecordsOneRedactedStaleTerminalAndIgnoresOldCallback() async {
        let harness = makeHarness()
        harness.coordinator.start()

        harness.entitlements.identityGeneration = MonetizationIdentityTransition(
            revision: 2,
            userID: "user-b"
        )
        harness.coordinator.identityDidChange()
        harness.presenter.send(.failed(message: "raw provider detail"), registration: 0)
        await Task.yield()

        let terminals = harness.sink.records.filter {
            $0.name == "app_access_gate_attempt_terminal"
        }
        #expect(terminals.count == 1)
        #expect(terminals[0].parameters["provider_outcome"] == .string("stale_identity"))
        #expect(terminals[0].parameters["identity_match"] == .bool(false))
        #expect(terminals[0].parameters.values.contains(.string("user-a")) == false)
        #expect(terminals[0].parameters.values.contains(.string("user-b")) == false)
        #expect(terminals[0].parameters.values.contains(.string("raw provider detail")) == false)
    }

    @Test
    func switchingTelemetryIdentityFirstSuppressesTheOldGateTerminalAndAttributesTheNewAttempt() async {
        let attributionSink = IdentityAttributingTelemetrySink()
        let harness = makeHarness(attributionSink: attributionSink)
        harness.coordinator.start()

        harness.telemetry.setUserId("user-b")
        harness.entitlements.identityGeneration = MonetizationIdentityTransition(
            revision: 2,
            userID: "user-b"
        )
        harness.coordinator.identityDidChange()
        harness.presenter.send(.skipped(reason: "new-account"), registration: 1)
        await harness.provider.waitUntilLoadCount(1)
        await waitUntil { harness.coordinator.phase == .nativeReady }

        let terminals = attributionSink.attributions.filter {
            $0.name == "app_access_gate_attempt_terminal"
        }
        let reached = attributionSink.attributions.filter {
            $0.name == "paywall_reached"
        }
        #expect(reached.map(\.userID) == ["user-a", "user-b"])
        #expect(terminals.count == 1)
        #expect(terminals.first?.userID == "user-b")
        #expect(terminals.first?.parameters["provider_outcome"] == .string("native_ready"))
        #expect(terminals.first?.parameters["identity_match"] == .bool(true))
        #expect(terminals.first?.parameters["user_id"] == nil)
    }

    @Test
    func rawPaywallLifecycleRecordsCarryStoreKitDiagnosticsWithoutRawErrors() {
        let diagnostics = StoreKitEnvironmentDiagnostics(
            receiptName: { "sandboxReceipt" },
            telemetry: makeTestTelemetry(
                sink: InMemoryTelemetrySink(destination: .analytics)
            )
        )

        for name in ["paywall_reached", "paywall_skipped", "paywall_error"] {
            let record = PaywallAnalyticsEvent.diagnosticRecord(
                name: name,
                parameters: ["placement": .string("app_access_gate")],
                diagnostics: diagnostics
            )
            #expect(record.parameters["storekit_receipt_name"] == .string("sandboxReceipt"))
            #expect(record.parameters["error"] == nil)
        }
    }

    private func makeHarness(
        identity: MonetizationIdentityTransition = MonetizationIdentityTransition(
            revision: 1,
            userID: "user-a"
        ),
        provider: CoordinatorNativeProvider = CoordinatorNativeProvider(),
        restoreService: AppAccessRestoreService? = nil,
        presenter: CoordinatorPaywallPresenter = CoordinatorPaywallPresenter(),
        attributionSink: IdentityAttributingTelemetrySink? = nil,
        sleep: @escaping AppAccessPaywallCoordinator.Sleep = {
            try await Task.sleep(for: $0)
        },
        nativeLoadSleep: @escaping AppAccessPaywallCoordinator.Sleep = {
            try await Task.sleep(for: $0)
        }
    ) -> CoordinatorHarness {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        var sinks: [any TelemetrySink] = [sink]
        if let attributionSink {
            sinks.append(attributionSink)
        }
        let telemetry = TelemetryManager(
            sinks: sinks,
            crashlyticsReporter: NoopCrashlyticsReporter(),
            collectionEnabledOverride: true,
            identityStore: makeTestIdentityStore()
        )
        telemetry.configure()
        if let userID = identity.userID {
            telemetry.setUserId(userID)
        }
        let entitlements = CoordinatorEntitlementService(identity: identity)
        let manager = MonetizationManager(
            configuration: testConfiguration,
            entitlementService: entitlements,
            paywallPresenter: presenter,
            appAccessReconciler: CoordinatorReconciler(),
            telemetry: telemetry,
            userDefaults: UserDefaults(
                suiteName: "AppAccessPaywallCoordinatorTests-\(UUID().uuidString)"
            )!
        )
        let service = restoreService ?? AppAccessRestoreService(
            telemetry: telemetry,
            entitlementID: "app_access",
            restorer: { manager }
        )
        let coordinator = AppAccessPaywallCoordinator(
            monetizationManager: manager,
            nativeProvider: provider,
            restoreService: service,
            telemetry: telemetry,
            sleep: sleep,
            nativeLoadSleep: nativeLoadSleep
        )
        return CoordinatorHarness(
            coordinator: coordinator,
            entitlements: entitlements,
            presenter: presenter,
            provider: provider,
            sink: sink,
            telemetry: telemetry
        )
    }

    private func openNativePlans(_ harness: CoordinatorHarness) async {
        harness.coordinator.start()
        harness.presenter.send(.skipped(reason: "test"), registration: 0)
        await harness.provider.waitUntilLoadCount(1)
        await waitUntil { harness.coordinator.phase == .nativeReady }
    }

    private var testConfiguration: MonetizationConfiguration {
        MonetizationConfiguration(
            infoDictionary: [
                MonetizationConfiguration.revenueCatAPIKeyInfoKey: "appl_test",
                MonetizationConfiguration.superwallAPIKeyInfoKey: "pk_test",
                MonetizationConfiguration.revenueCatYearlyProductIDInfoKey:
                    "ascend_staging_yearly",
                MonetizationConfiguration.revenueCatMonthlyProductIDInfoKey:
                    "ascend_staging_monthly",
                MonetizationConfiguration.allowsUnentitledAppAccessInfoKey: "NO"
            ]
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<50 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("Condition did not become true after deterministic task yields.")
    }
}

@MainActor
private struct CoordinatorHarness {
    let coordinator: AppAccessPaywallCoordinator
    let entitlements: CoordinatorEntitlementService
    let presenter: CoordinatorPaywallPresenter
    let provider: CoordinatorNativeProvider
    let sink: InMemoryTelemetrySink
    let telemetry: TelemetryManager
}

@MainActor
private final class CoordinatorNativeProvider: NativeSubscriptionProviding {
    private(set) var loadCount = 0
    private(set) var purchaseCount = 0
    private let suspendsPlanLoad: Bool
    private let automaticPurchaseResult: PurchaseResult?
    private var loadContinuations: [CheckedContinuation<[NativeSubscriptionPlan], Never>] = []
    private var purchaseContinuation: CheckedContinuation<PurchaseResult, Never>?
    private var loadObservers: [CheckedContinuation<Void, Never>] = []
    private var purchaseObservers: [CheckedContinuation<Void, Never>] = []

    init(
        suspendsPlanLoad: Bool = false,
        automaticPurchaseResult: PurchaseResult? = nil
    ) {
        self.suspendsPlanLoad = suspendsPlanLoad
        self.automaticPurchaseResult = automaticPurchaseResult
    }

    func loadPlans() async throws -> [NativeSubscriptionPlan] {
        loadCount += 1
        loadObservers.forEach { $0.resume() }
        loadObservers = []
        guard suspendsPlanLoad else { return Self.plans }
        return await withCheckedContinuation { loadContinuations.append($0) }
    }

    func purchase(planID: String) async -> PurchaseResult {
        purchaseCount += 1
        purchaseObservers.forEach { $0.resume() }
        purchaseObservers = []
        if let automaticPurchaseResult { return automaticPurchaseResult }
        return await withCheckedContinuation { purchaseContinuation = $0 }
    }

    func waitUntilLoadCount(_ expected: Int) async {
        guard loadCount < expected else { return }
        await withCheckedContinuation { loadObservers.append($0) }
    }

    func waitUntilPurchaseCount(_ expected: Int) async {
        guard purchaseCount < expected else { return }
        await withCheckedContinuation { purchaseObservers.append($0) }
    }

    func completePlanLoad(
        with plans: [NativeSubscriptionPlan]? = nil,
        at index: Int = 0
    ) {
        guard loadContinuations.indices.contains(index) else { return }
        loadContinuations.remove(at: index).resume(returning: plans ?? Self.plans)
    }

    func completePurchase(_ result: PurchaseResult) {
        purchaseContinuation?.resume(returning: result)
        purchaseContinuation = nil
    }

    private static let plans = [
        NativeSubscriptionPlan(
            id: "ascend_staging_yearly",
            title: "Annual",
            localizedPrice: "$49.99",
            renewalDescription: "$49.99 per year until cancelled.",
            trialDescription: "7 days free, then $49.99 per year."
        ),
        NativeSubscriptionPlan(
            id: "ascend_staging_monthly",
            title: "Monthly",
            localizedPrice: "$9.99",
            renewalDescription: "$9.99 per month until cancelled.",
            trialDescription: nil
        )
    ]
}

private final class CoordinatorControlledSleep: @unchecked Sendable {
    private let lock = NSLock()
    private var nextCall = 0
    private var continuations: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var observers: [CheckedContinuation<Void, Never>] = []

    func sleep(for duration: Duration) async throws {
        let call = lock.withLock { () -> Int in
            nextCall += 1
            let call = nextCall
            observers.forEach { $0.resume() }
            observers = []
            return call
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    lock.withLock { continuations[call] = continuation }
                }
            }
        } onCancel: {
            let continuation = lock.withLock { continuations.removeValue(forKey: call) }
            continuation?.resume(throwing: CancellationError())
        }
    }

    func fire(call: Int) {
        lock.withLock { continuations.removeValue(forKey: call) }?.resume()
    }

    func waitUntilCallCount(_ expected: Int) async {
        if lock.withLock({ nextCall >= expected }) { return }
        await withCheckedContinuation { continuation in
            let ready = lock.withLock { () -> Bool in
                if nextCall >= expected { return true }
                observers.append(continuation)
                return false
            }
            if ready { continuation.resume() }
        }
    }
}

@MainActor
private final class CoordinatorRestoreProvider: PurchaseRestoring {
    let isRevenueCatConfigured = true
    var identityGeneration: MonetizationIdentityTransition?
    private var startObservers: [CheckedContinuation<Void, Never>] = []
    private var completion: CheckedContinuation<MonetizationEntitlementState, Never>?

    init(identity: MonetizationIdentityTransition) {
        identityGeneration = identity
    }

    func restorePurchases(
        for identity: MonetizationIdentityTransition
    ) async -> MonetizationEntitlementState {
        startObservers.forEach { $0.resume() }
        startObservers = []
        return await withCheckedContinuation { completion = $0 }
    }

    func restorePurchases() async -> MonetizationEntitlementState {
        .unknown
    }

    func waitUntilStarted() async {
        guard completion == nil else { return }
        await withCheckedContinuation { startObservers.append($0) }
    }

    func complete(_ state: MonetizationEntitlementState) {
        completion?.resume(returning: state)
        completion = nil
    }
}

@MainActor
private final class CoordinatorEntitlementService: EntitlementServicing {
    var entitlementState: MonetizationEntitlementState = .inactive
    var hasFailedIdentityResolution = false
    var identityGeneration: MonetizationIdentityTransition?
    var isConfigured = true

    init(identity: MonetizationIdentityTransition) {
        identityGeneration = identity
    }

    func configure(configuration: MonetizationConfiguration) {}

    func refreshCustomerInfo(
        waitsForPendingIdentity: Bool
    ) async -> MonetizationEntitlementRefresh {
        .refreshed(entitlementState)
    }

    func prepareIdentity(
        _ customer: MonetizationCustomerIdentity
    ) -> MonetizationIdentityTransition {
        identityGeneration ?? MonetizationIdentityTransition(
            revision: 0,
            userID: customer.userID
        )
    }

    func identify(
        _ customer: MonetizationCustomerIdentity,
        transition: MonetizationIdentityTransition
    ) async {}

    func prepareIdentityReset() -> MonetizationIdentityTransition {
        MonetizationIdentityTransition(revision: 0, userID: nil)
    }

    func resetIdentity(transition: MonetizationIdentityTransition) async {}
    func retryIdentityResolution() async {}

    func adoptTransactionState(
        _ state: MonetizationEntitlementState,
        for identity: MonetizationIdentityTransition
    ) -> Bool {
        guard identityGeneration == identity else { return false }
        entitlementState = state
        return true
    }

    func restorePurchases(
        for identity: MonetizationIdentityTransition
    ) async -> MonetizationEntitlementState {
        guard identityGeneration == identity else { return .unknown }
        return entitlementState
    }

    func restorePurchases() async -> MonetizationEntitlementState {
        entitlementState
    }
}

@MainActor
private final class CoordinatorPaywallPresenter: PaywallPresenting {
    let isConfigured = true
    private(set) var cancelCount = 0
    private var handlers: [@MainActor (PaywallPresentationOutcome) -> Void] = []
    private let automaticOutcome: PaywallPresentationOutcome?

    init(automaticOutcome: PaywallPresentationOutcome? = nil) {
        self.automaticOutcome = automaticOutcome
    }

    func configure(configuration: MonetizationConfiguration) {}
    func identify(userId: String) {}
    func resetIdentity() {}
    func cancelPresentation() { cancelCount += 1 }

    func register(
        placement: SuperwallPlacement,
        params: [String: Any]?,
        onOutcome: @escaping @MainActor (PaywallPresentationOutcome) -> Void
    ) {
        handlers.append(onOutcome)
        if let automaticOutcome { onOutcome(automaticOutcome) }
    }

    func send(_ outcome: PaywallPresentationOutcome, registration: Int) {
        guard handlers.indices.contains(registration) else { return }
        handlers[registration](outcome)
    }
}

@MainActor
private final class CoordinatorReconciler: AppAccessReconciling {
    func reconcileAppAccess(force: Bool) async {}
}
