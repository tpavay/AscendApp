import Foundation
import RevenueCat
import SuperwallKit
import Testing
@testable import AscendApp

@MainActor
struct PaywallPurchaseAnalyticsContractTests {
    private static let productID = "ascend_yearly"
    private static let entitlementID = "app_access"
    private static let purchaseTerminalNames: Set<String> = [
        "revenuecat_purchase_completed",
        "revenuecat_purchase_cancelled",
        "revenuecat_purchase_pending",
        "revenuecat_purchase_failed"
    ]
    private static let restoreTerminalNames: Set<String> = [
        "revenuecat_restore_completed",
        "revenuecat_restore_failed"
    ]

    @Test
    func successfulPurchaseEmitsOneCompletedTerminalAndReturnsSuperwallPurchased() async {
        let harness = Self.makeHarness()
        Self.recordPaywallContext(in: harness.contextStore)

        let result = await harness.executor.executePurchase(productID: Self.productID) {
            RevenueCatPurchaseExecutor.PurchaseResponse(
                userCancelled: false,
                activeEntitlementIDs: [Self.entitlementID]
            )
        }

        let records = harness.sink.records
        #expect(records.map(\.name) == [
            "revenuecat_purchase_started",
            "revenuecat_purchase_completed"
        ])
        Self.expectOnePurchaseTerminal(in: records)
        #expect(Self.superwallTerminalName(for: result) == "paywall_transaction_completed")
        #expect(records[0].parameters["product_id"] == TelemetryValue.string(Self.productID))
        #expect(records[0].parameters["placement"] == TelemetryValue.string("onboarding_paywall"))
        #expect(records[0].parameters["presentation_id"] == TelemetryValue.string("presentation-1"))
        #expect(records[1].parameters["outcome"] == TelemetryValue.string("success"))
        #expect(records[1].parameters["entitlement_id"] == TelemetryValue.string(Self.entitlementID))
        #expect(records[1].parameters["entitlement_active"] == TelemetryValue.bool(true))
    }

    @Test
    func cancelledPurchaseEmitsOneCancelledTerminalAndReturnsSuperwallCancelled() async {
        let harness = Self.makeHarness()
        Self.recordPaywallContext(in: harness.contextStore)

        let result = await harness.executor.executePurchase(productID: Self.productID) {
            RevenueCatPurchaseExecutor.PurchaseResponse(
                userCancelled: true,
                activeEntitlementIDs: []
            )
        }

        let records = harness.sink.records
        #expect(records.map(\.name) == [
            "revenuecat_purchase_started",
            "revenuecat_purchase_cancelled"
        ])
        Self.expectOnePurchaseTerminal(in: records)
        #expect(Self.superwallTerminalName(for: result) == "paywall_transaction_abandoned")
        #expect(records[1].parameters["outcome"] == TelemetryValue.string("user_cancelled"))
    }

    @Test
    func thrownCancellationEmitsTheSameSingleCancelledTerminal() async {
        let harness = Self.makeHarness()
        Self.recordPaywallContext(in: harness.contextStore)

        let result = await harness.executor.executePurchase(productID: Self.productID) {
            throw ErrorCode.purchaseCancelledError
        }

        let records = harness.sink.records
        #expect(records.map(\.name) == [
            "revenuecat_purchase_started",
            "revenuecat_purchase_cancelled"
        ])
        Self.expectOnePurchaseTerminal(in: records)
        #expect(Self.superwallTerminalName(for: result) == "paywall_transaction_abandoned")
    }

    @Test
    func pendingPurchaseEmitsOnePendingTerminalAndReturnsSuperwallPending() async {
        let harness = Self.makeHarness()
        Self.recordPaywallContext(in: harness.contextStore)

        let result = await harness.executor.executePurchase(productID: Self.productID) {
            throw ErrorCode.paymentPendingError
        }

        let records = harness.sink.records
        #expect(records.map(\.name) == [
            "revenuecat_purchase_started",
            "revenuecat_purchase_pending"
        ])
        Self.expectOnePurchaseTerminal(in: records)
        #expect(Self.superwallTerminalName(for: result) == "paywall_transaction_failed")
        #expect(records[1].parameters["outcome"] == TelemetryValue.string("pending"))
    }

    @Test
    func failedPurchaseEmitsOneFailedTerminalWithBoundedErrorAndReturnsSuperwallFailure() async {
        let harness = Self.makeHarness()
        Self.recordPaywallContext(in: harness.contextStore)

        let result = await harness.executor.executePurchase(productID: Self.productID) {
            throw ErrorCode.networkError
        }

        let records = harness.sink.records
        #expect(records.map(\.name) == [
            "revenuecat_purchase_started",
            "revenuecat_purchase_failed"
        ])
        Self.expectOnePurchaseTerminal(in: records)
        #expect(Self.superwallTerminalName(for: result) == "paywall_transaction_failed")
        #expect(records[1].parameters["outcome"] == TelemetryValue.string("failed"))
        #expect(records[1].parameters["error_type"] == TelemetryValue.string("network"))
    }

    @Test
    func purchaseWithoutActiveEntitlementIsFailedInsteadOfCompleted() async {
        let harness = Self.makeHarness()
        Self.recordPaywallContext(in: harness.contextStore)

        let result = await harness.executor.executePurchase(productID: Self.productID) {
            RevenueCatPurchaseExecutor.PurchaseResponse(
                userCancelled: false,
                activeEntitlementIDs: []
            )
        }

        let records = harness.sink.records
        #expect(records.map(\.name) == [
            "revenuecat_purchase_started",
            "revenuecat_purchase_failed"
        ])
        Self.expectOnePurchaseTerminal(in: records)
        #expect(Self.superwallTerminalName(for: result) == "paywall_transaction_failed")
        #expect(records[1].parameters["error_type"] == TelemetryValue.string("no_active_entitlement"))
    }

    @Test
    func missingStoreProductEmitsOneFailureWithoutClaimingARevenueCatStart() {
        let harness = Self.makeHarness()
        Self.recordPaywallContext(in: harness.contextStore)
        let error = RevenueCatPurchaseControllerError.missingStoreKitProduct

        let result = harness.executor.failPurchaseBeforeRevenueCatCall(
            productID: Self.productID,
            error: error,
            errorType: RevenueCatAnalyticsErrorType.missingStoreProduct
        )

        let records = harness.sink.records
        #expect(records.map(\.name) == ["revenuecat_purchase_failed"])
        Self.expectOnePurchaseTerminal(in: records)
        #expect(Self.superwallTerminalName(for: result) == "paywall_transaction_failed")
        #expect(records[0].parameters["error_type"] == TelemetryValue.string("missing_store_product"))
    }

    @Test
    func successfulRestoreEmitsOneCompletedTerminalAndReturnsRestored() async {
        let harness = Self.makeHarness()

        let result = await harness.executor.executeRestore {
            [Self.entitlementID]
        }

        let records = harness.sink.records
        #expect(records.map(\.name) == [
            "revenuecat_restore_started",
            "revenuecat_restore_completed"
        ])
        Self.expectOneRestoreTerminal(in: records)
        #expect(result == .restored)
        #expect(records[1].parameters["outcome"] == TelemetryValue.string("success"))
        #expect(records[1].parameters["entitlement_id"] == TelemetryValue.string(Self.entitlementID))
        #expect(records[1].parameters["entitlement_active"] == TelemetryValue.bool(true))
    }

    @Test
    func restoreWithoutEntitlementEmitsOneFailedTerminalAndNeverCompletesSuperwallRestore() async {
        let harness = Self.makeHarness()

        let result = await harness.executor.executeRestore { [] }

        let records = harness.sink.records
        #expect(records.map(\.name) == [
            "revenuecat_restore_started",
            "revenuecat_restore_failed"
        ])
        Self.expectOneRestoreTerminal(in: records)
        #expect(Self.isSuperwallRestoreCompleted(result) == false)
        #expect(records[1].parameters["outcome"] == TelemetryValue.string("no_entitlement"))
        #expect(records[1].parameters["entitlement_id"] == TelemetryValue.string(Self.entitlementID))
        #expect(records[1].parameters["entitlement_active"] == TelemetryValue.bool(false))
        #expect(records[1].parameters["error_type"] == TelemetryValue.string("no_active_entitlement"))
    }

    @Test
    func failedRestoreEmitsOneFailedTerminalWithBoundedError() async {
        let harness = Self.makeHarness()

        let result = await harness.executor.executeRestore {
            throw ErrorCode.networkError
        }

        let records = harness.sink.records
        #expect(records.map(\.name) == [
            "revenuecat_restore_started",
            "revenuecat_restore_failed"
        ])
        Self.expectOneRestoreTerminal(in: records)
        #expect(Self.isSuperwallRestoreCompleted(result) == false)
        #expect(records[1].parameters["outcome"] == TelemetryValue.string("failed"))
        #expect(records[1].parameters["entitlement_active"] == TelemetryValue.bool(false))
        #expect(records[1].parameters["error_type"] == TelemetryValue.string("network"))
    }
}

@MainActor
private extension PaywallPurchaseAnalyticsContractTests {
    typealias Harness = (
        executor: RevenueCatPurchaseExecutor,
        sink: InMemoryTelemetrySink,
        contextStore: PaywallTransactionContextStore
    )

    static func makeHarness() -> Harness {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let contextStore = PaywallTransactionContextStore()
        let executor = RevenueCatPurchaseExecutor(
            telemetry: makeTestTelemetry(sink: sink),
            transactionContextStore: contextStore,
            entitlementID: entitlementID,
            applySubscriptionStatus: { _ in },
            refreshEntitlementState: {}
        )
        return (executor, sink, contextStore)
    }

    static func recordPaywallContext(in contextStore: PaywallTransactionContextStore) {
        contextStore.record(
            placement: "onboarding_paywall",
            presentationID: "presentation-1",
            productID: productID
        )
    }

    static func expectOnePurchaseTerminal(in records: [EnvelopedTelemetryRecord]) {
        #expect(records.filter { purchaseTerminalNames.contains($0.name) }.count == 1)
    }

    static func expectOneRestoreTerminal(in records: [EnvelopedTelemetryRecord]) {
        #expect(records.filter { restoreTerminalNames.contains($0.name) }.count == 1)
    }

    static func superwallTerminalName(for result: SuperwallKit.PurchaseResult) -> String {
        switch result {
        case .purchased:
            return "paywall_transaction_completed"
        case .cancelled:
            return "paywall_transaction_abandoned"
        case .pending, .failed:
            return "paywall_transaction_failed"
        }
    }

    static func isSuperwallRestoreCompleted(_ result: SuperwallKit.RestorationResult) -> Bool {
        result == .restored
    }
}
