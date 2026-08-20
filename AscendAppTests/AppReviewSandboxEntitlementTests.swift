import Foundation
import RevenueCat
import SuperwallKit
import Testing
@testable import AscendApp

/// App Review buys in the sandbox from a binary the RevenueCat SDK reads as production, so the
/// reviewer's entitlement is active with `isSandbox: true` while
/// `BundleSandboxEnvironmentDetector` reports production. Reading
/// `entitlements.activeInCurrentEnvironment` dropped exactly that entitlement, and the charged
/// reviewer was told "Ascend couldn't confirm your subscription" - the Guideline 2.1(b) rejection
/// of build 2026081401. TestFlight cannot reproduce it: a TestFlight install has a `sandboxReceipt`
/// path, so both flags say sandbox and the filter passes.
///
/// These tests hold the entitlement in both environments at once. Whichever one the host running
/// the suite is in, the other is the reviewer's case, so the regression cannot come back by
/// passing on the simulator alone.
@MainActor
struct AppReviewSandboxEntitlementTests {
    private static let entitlementID = "app_access"
    private static let productID = "ascend_yearly"

    @Test(arguments: [true, false])
    func anActiveEntitlementIsHeldInEitherStoreKitEnvironment(isSandbox: Bool) {
        let entitlements = Self.entitlements(isActive: true, isSandbox: isSandbox)

        #expect(entitlements.appAccessEntitlementIDs == [Self.entitlementID])
        #expect(entitlements.appAccessEntitlementState == .active([Self.entitlementID]))
    }

    /// Pins the mechanism rather than only its consequence: RevenueCat's own predicate refuses a
    /// held entitlement whenever the entitlement's environment and the device's disagree. Exactly
    /// one of these two entitlements crosses the host's environment, whichever host runs the suite.
    @Test
    func revenueCatsOwnFilterRefusesACrossEnvironmentEntitlement() {
        let sandboxPurchase = Self.entitlement(isActive: true, isSandbox: true)
        let productionPurchase = Self.entitlement(isActive: true, isSandbox: false)

        #expect(sandboxPurchase.isActiveInAnyEnvironment)
        #expect(productionPurchase.isActiveInAnyEnvironment)
        #expect(
            sandboxPurchase.isActiveInCurrentEnvironment
                != productionPurchase.isActiveInCurrentEnvironment
        )
    }

    /// The regression itself, on one entitlement rather than two facts side by side: the shipped
    /// rule reads the very entitlement RevenueCat's filter drops, and grants on it. The `#expect`
    /// on `activeInCurrentEnvironment` *is* the old rule - `Set(...keys)` was the deleted line at
    /// both call sites - so this fails the moment either one goes back.
    @Test
    func theShippedRuleGrantsTheEntitlementTheOldFilterDropped() throws {
        let entitlements = try #require(Self.crossEnvironmentEntitlements())

        #expect(entitlements.activeInCurrentEnvironment.isEmpty)
        #expect(entitlements.appAccessEntitlementIDs == [Self.entitlementID])
        #expect(entitlements.appAccessEntitlementState == .active([Self.entitlementID]))
    }

    /// A real customer buys and installs in one environment, so the old filter and the new rule
    /// have always agreed about them. Pins that the fix widened nothing for anyone but the
    /// cross-environment case.
    @Test
    func aSameEnvironmentPurchaseReadsIdenticallyUnderBothRules() throws {
        let entitlements = try #require(Self.sameEnvironmentEntitlements())

        #expect(Set(entitlements.activeInCurrentEnvironment.keys) == [Self.entitlementID])
        #expect(entitlements.appAccessEntitlementIDs == [Self.entitlementID])
    }

    /// Restore read the same discarded line, so a reviewer's own workaround produced a second
    /// error: `.notFound` -> "No purchases found to restore." Both readings run through the one
    /// service here, so the old one is shown failing beside the new one succeeding.
    @Test
    func restoreFindsTheEntitlementTheOldFilterDropped() async throws {
        let entitlements = try #require(Self.crossEnvironmentEntitlements())

        let oldRuleIDs = Set(entitlements.activeInCurrentEnvironment.keys)
        let underOldRule = await Self.restoreOutcome(
            for: oldRuleIDs.isEmpty ? .inactive : .active(oldRuleIDs)
        )
        guard case .notFound = underOldRule else {
            Issue.record("The old filter is what returned no-purchases-found; got \(underOldRule)")
            return
        }

        let underShippedRule = await Self.restoreOutcome(
            for: entitlements.appAccessEntitlementState
        )
        guard case .restored(let entitlementIDs) = underShippedRule else {
            Issue.record("The shipped rule must restore the reviewer's entitlement")
            return
        }

        #expect(entitlementIDs == [Self.entitlementID])
    }

    /// The pair the filter used to compare is now recorded instead of consulted, so the next
    /// environment surprise is one glance rather than another review cycle.
    @Test(arguments: [true, false])
    func theEnvironmentPairIsReportable(isSandbox: Bool) {
        let entitlements = Self.entitlements(isActive: true, isSandbox: isSandbox)

        #expect(entitlements.holdsSandboxEntitlement == isSandbox)
        #expect(!StoreKitReceiptEnvironment.receiptName.isEmpty)
    }

    /// Recording the pair is not reporting it. It rides the paywall, purchase, and restore events
    /// rather than a Crashlytics custom key, because this rejection produced an alert and no crash
    /// - a custom key would have been attached to a report that was never uploaded, which is how
    /// two submissions went by with the answer unobservable.
    @Test(arguments: [true, false])
    func everyPaywallAndPurchaseEventCarriesTheEnvironmentPair(isSandbox: Bool) {
        let diagnostics = Self.diagnostics(receiptName: "sandboxReceipt").diagnostics
        diagnostics.record(holdsSandboxEntitlement: isSandbox)

        for event in Self.reviewedEvents {
            let parameters = event.record(diagnostics: diagnostics).parameters

            #expect(parameters["holds_sandbox_entitlement"] == .bool(isSandbox))
            #expect(parameters["storekit_receipt_name"] == .string("sandboxReceipt"))
        }
    }

    /// Absent rather than `false` until RevenueCat has answered once: "not asked yet" and "bought
    /// in production" are different facts, and reading the first as the second is the shape of
    /// mistake that started this.
    @Test
    func theSandboxFlagIsAbsentUntilRevenueCatAnswers() {
        let parameters = PaywallAnalyticsEvent.revenueCatRestoreStarted
            .record(diagnostics: Self.diagnostics(receiptName: "none").diagnostics)
            .parameters

        #expect(parameters["holds_sandbox_entitlement"] == nil)
        #expect(parameters["storekit_receipt_name"] == .string("none"))
    }

    /// The injected overload is the only one the assertions above can reach, so this pins the
    /// property `TelemetryManager.track(_ event:)` actually calls to the shared diagnostics.
    /// Without it, dropping the merge from `record` ships events with neither field and the suite
    /// stays green. Only the receipt name is asserted: the sandbox flag is deliberately absent
    /// until RevenueCat answers, and the shared instance's answer depends on what else has run.
    @Test
    func theShippedEventPathCarriesTheEnvironmentPair() {
        let parameters = PaywallAnalyticsEvent.revenueCatRestoreStarted.record.parameters

        #expect(
            parameters["storekit_receipt_name"] == .string(StoreKitReceiptEnvironment.receiptName)
        )
    }

    /// The Crashlytics custom keys are kept alongside the event parameters, for the crash and
    /// Sentry reports that do exist, and the type named for the pair is what sets them - so a
    /// reading that never reaches an entry point still lands on both surfaces.
    @Test(arguments: [true, false])
    func recordingThePairAlsoSetsTheCrashlyticsKeys(isSandbox: Bool) {
        let harness = Self.diagnostics(receiptName: "sandboxReceipt")

        harness.diagnostics.record(holdsSandboxEntitlement: isSandbox)

        #expect(harness.reporter.boolValue(forKey: "holds_sandbox_entitlement") == isSandbox)
        #expect(harness.reporter.stringValue(forKey: "storekit_receipt_name") == "sandboxReceipt")
    }

    @Test(arguments: [true, false])
    func anExpiredEntitlementIsHeldInNeitherStoreKitEnvironment(isSandbox: Bool) {
        let entitlements = Self.entitlements(isActive: false, isSandbox: isSandbox)

        #expect(entitlements.appAccessEntitlementIDs.isEmpty)
        #expect(entitlements.appAccessEntitlementState == .inactive)
    }

    /// The whole reviewed path, from the entitlement RevenueCat actually returned to what Superwall
    /// puts on screen: a purchase that resolves a sandbox entitlement reports `purchased`, publishes
    /// the subscription to Superwall, and presents no failure alert.
    @Test(arguments: [true, false])
    func aCompletedPurchaseSurfacesNoErrorInEitherEnvironment(isSandbox: Bool) async {
        let harness = PurchaseVerdictHarness(
            entitlementID: Self.entitlementID,
            refresh: .refreshed(
                Self.entitlements(isActive: true, isSandbox: isSandbox).appAccessEntitlementState
            )
        )

        let result = await harness.executor.executePurchase(productID: Self.productID) {
            RevenueCatPurchaseExecutor.PurchaseResponse(userCancelled: false)
        }

        #expect(Self.isPurchased(result))
        #expect(!Self.presentsFailureAlert(result))
        #expect(harness.published == [[Self.entitlementID]])

        let names = harness.sink.records.map(\.name)
        #expect(names.contains("revenuecat_purchase_completed"))
        #expect(!names.contains("revenuecat_purchase_failed"))
    }

    /// Restore reads the same rule, so a reviewer who taps Restore instead of buying again is told
    /// the truth rather than "No purchases found to restore."
    @Test(arguments: [true, false])
    func aRestoreFindsTheEntitlementInEitherEnvironment(isSandbox: Bool) async {
        let restorer = StubRestorer(
            state: Self.entitlements(isActive: true, isSandbox: isSandbox).appAccessEntitlementState
        )
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let service = AppAccessRestoreService(
            telemetry: makeTestTelemetry(sink: sink),
            entitlementID: Self.entitlementID,
            restorer: { restorer }
        )

        guard case .restored(let entitlementIDs) = await service.restore() else {
            Issue.record("A held entitlement must restore, sandbox: \(isSandbox)")
            return
        }

        #expect(entitlementIDs == [Self.entitlementID])
        #expect(sink.records.map(\.name).contains("revenuecat_restore_completed"))
    }
}

private extension AppReviewSandboxEntitlementTests {
    /// Diagnostics wired to a telemetry manager of this suite's own, so recording the pair never
    /// reaches the shared singleton.
    static func diagnostics(
        receiptName: String
    ) -> (diagnostics: StoreKitEnvironmentDiagnostics, reporter: CustomKeyRecordingReporter) {
        let reporter = CustomKeyRecordingReporter()

        return (
            StoreKitEnvironmentDiagnostics(
                receiptName: { receiptName },
                telemetry: makeTestTelemetry(reporter: reporter)
            ),
            reporter
        )
    }

    /// One event from each surface the reviewer touched: the purchase terminal that reported
    /// success, the one that raised the alert, and the restore terminal that said no purchases
    /// were found.
    static var reviewedEvents: [PaywallAnalyticsEvent] {
        let context = RevenueCatPurchaseAnalyticsContext(
            placement: "app_access_gate",
            presentationID: nil
        )

        return [
            .revenueCatPurchaseCompleted(
                productID: productID,
                entitlementID: entitlementID,
                context: context
            ),
            .revenueCatPurchaseFailed(
                productID: productID,
                errorType: .noActiveEntitlement,
                attribution: .purchaseStarted(context)
            ),
            .revenueCatRestoreNotFound(entitlementID: entitlementID)
        ]
    }

    /// The reviewer's case, whichever host runs the suite: an active entitlement whose environment
    /// is not the one `BundleSandboxEnvironmentDetector` reads off this binary. Exactly one of the
    /// two environments qualifies, so there is no host on which this test degrades into a tautology
    /// - and if RevenueCat ever stops filtering, `#require` fails rather than passing vacuously.
    static func crossEnvironmentEntitlements() -> RevenueCat.EntitlementInfos? {
        entitlementInfos { !$0.isActiveInCurrentEnvironment }
    }

    /// The paying customer's case: bought and installed in the same environment.
    static func sameEnvironmentEntitlements() -> RevenueCat.EntitlementInfos? {
        entitlementInfos(\.isActiveInCurrentEnvironment)
    }

    static func entitlementInfos(
        _ isIncluded: (RevenueCat.EntitlementInfo) -> Bool
    ) -> RevenueCat.EntitlementInfos? {
        let matches = [true, false]
            .map { entitlement(isActive: true, isSandbox: $0) }
            .filter(isIncluded)

        guard matches.count == 1, let match = matches.first else { return nil }

        return EntitlementInfos(entitlements: [entitlementID: match])
    }

    static func restoreOutcome(
        for state: MonetizationEntitlementState
    ) async -> AppAccessRestoreOutcome {
        await AppAccessRestoreService(
            telemetry: makeTestTelemetry(sink: InMemoryTelemetrySink(destination: .analytics)),
            entitlementID: entitlementID,
            restorer: { StubRestorer(state: state) }
        )
        .restore()
    }

    static func entitlements(
        isActive: Bool,
        isSandbox: Bool
    ) -> RevenueCat.EntitlementInfos {
        EntitlementInfos(
            entitlements: [entitlementID: entitlement(isActive: isActive, isSandbox: isSandbox)]
        )
    }

    /// The reviewer's entitlement: a real `ascend_yearly` trial, active, bought in the sandbox.
    static func entitlement(
        isActive: Bool,
        isSandbox: Bool
    ) -> RevenueCat.EntitlementInfo {
        EntitlementInfo(
            identifier: entitlementID,
            isActive: isActive,
            willRenew: isActive,
            periodType: .trial,
            store: .appStore,
            productIdentifier: productID,
            isSandbox: isSandbox,
            ownershipType: .purchased
        )
    }

    static func isPurchased(_ result: SuperwallKit.PurchaseResult) -> Bool {
        if case .purchased = result { return true }
        return false
    }

    /// Superwall renders the error it is handed as the purchase-failure alert, so `.failed` is the
    /// on-screen error surface this rejection was about.
    static func presentsFailureAlert(_ result: SuperwallKit.PurchaseResult) -> Bool {
        if case .failed = result { return true }
        return false
    }
}

@MainActor
private final class PurchaseVerdictHarness {
    let sink = InMemoryTelemetrySink(destination: .analytics)
    private(set) var published: [Set<String>] = []
    private(set) var executor: RevenueCatPurchaseExecutor!

    init(entitlementID: String, refresh: MonetizationEntitlementRefresh) {
        executor = RevenueCatPurchaseExecutor(
            telemetry: makeTestTelemetry(sink: sink),
            transactionContextStore: PaywallTransactionContextStore(),
            entitlementID: entitlementID,
            applySubscriptionStatus: { [weak self] entitlementIDs in
                self?.published.append(entitlementIDs)
            },
            refreshEntitlementState: { refresh }
        )
    }
}

@MainActor
private final class StubRestorer: PurchaseRestoring {
    let isRevenueCatConfigured = true
    private let state: MonetizationEntitlementState

    init(state: MonetizationEntitlementState) {
        self.state = state
    }

    func restorePurchases() async throws -> MonetizationEntitlementState {
        state
    }
}

/// Captures the Crashlytics custom keys a caller set, which no shared test reporter records.
private final class CustomKeyRecordingReporter: CrashlyticsReporting, @unchecked Sendable {
    private let lock = NSLock()
    private var boolValues: [String: Bool] = [:]
    private var stringValues: [String: String] = [:]

    func boolValue(forKey key: String) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return boolValues[key]
    }

    func stringValue(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return stringValues[key]
    }

    func setCollectionEnabled(_ enabled: Bool) {}
    func setUserID(_ userID: String?) {}

    func setCustomValue(_ value: Bool, forKey key: String) {
        lock.lock()
        boolValues[key] = value
        lock.unlock()
    }

    func setCustomValue(_ value: Int, forKey key: String) {}

    func setCustomValue(_ value: String, forKey key: String) {
        lock.lock()
        stringValues[key] = value
        lock.unlock()
    }

    func log(_ message: String) {}
    func record(error: Error, context: String, code: String, additionalInfo: [String: String]?) {}
}
