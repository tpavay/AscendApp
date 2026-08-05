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
        "revenuecat_restore_not_found",
        "revenuecat_restore_failed"
    ]

    // MARK: - Purchase

    @Test
    func successfulPurchaseEmitsOneCompletedTerminalAndReturnsSuperwallPurchased() async {
        let harness = Self.makePurchaseHarness(refreshedState: .active([Self.entitlementID]))
        Self.recordPaywallContext(in: harness.contextStore)

        let result = await harness.executor.executePurchase(productID: Self.productID) {
            RevenueCatPurchaseExecutor.PurchaseResponse(userCancelled: false)
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
        #expect(harness.published == [[Self.entitlementID]])
    }

    /// The purchase response is a pre-refresh snapshot. Only the refreshed RevenueCat entitlement
    /// state decides the verdict, so a slow projection can no longer be reported as a verified
    /// purchase.
    @Test
    func theRefreshedEntitlementStateAloneDecidesTheVerdict() async {
        let harness = Self.makePurchaseHarness(refreshedState: .active([Self.entitlementID]))

        let result = await harness.executor.executePurchase(productID: Self.productID) {
            RevenueCatPurchaseExecutor.PurchaseResponse(userCancelled: false)
        }

        #expect(harness.refreshCount == 1)
        #expect(Self.superwallTerminalName(for: result) == "paywall_transaction_completed")
    }

    /// A refresh that established nothing must say so. Reporting the stored entitlement in its
    /// place is what let a transitional `.unknown` read as a lapsed subscription.
    @Test
    func everyUnavailableRefreshFailsThePurchaseWithItsOwnBoundedReason() async {
        let expectations: [(MonetizationEntitlementRefreshFailure, String)] = [
            (.notConfigured, "configuration"),
            (.identityUnresolved, "entitlement_unresolved"),
            (.refreshTimedOut, "entitlement_refresh_timeout"),
            (.providerFailed, "entitlement_refresh_failed")
        ]

        for (failure, errorType) in expectations {
            let harness = Self.makePurchaseHarness(refreshFailure: failure)
            Self.recordPaywallContext(in: harness.contextStore)

            let result = await harness.executor.executePurchase(productID: Self.productID) {
                RevenueCatPurchaseExecutor.PurchaseResponse(userCancelled: false)
            }

            let records = harness.sink.records
            #expect(records.map(\.name) == [
                "revenuecat_purchase_started",
                "revenuecat_purchase_failed"
            ])
            Self.expectOnePurchaseTerminal(in: records)
            #expect(records[1].parameters["error_type"] == TelemetryValue.string(errorType))
            #expect(Self.superwallTerminalName(for: result) == "paywall_transaction_failed")
            #expect(harness.published.isEmpty)
            Self.expectNoRawErrorText(in: records)
        }
    }

    @Test
    func cancelledPurchaseEmitsOneCancelledTerminalAndNeverRefreshes() async {
        let harness = Self.makePurchaseHarness(refreshedState: .active([Self.entitlementID]))
        Self.recordPaywallContext(in: harness.contextStore)

        let result = await harness.executor.executePurchase(productID: Self.productID) {
            RevenueCatPurchaseExecutor.PurchaseResponse(userCancelled: true)
        }

        let records = harness.sink.records
        #expect(records.map(\.name) == [
            "revenuecat_purchase_started",
            "revenuecat_purchase_cancelled"
        ])
        Self.expectOnePurchaseTerminal(in: records)
        #expect(Self.superwallTerminalName(for: result) == "paywall_transaction_abandoned")
        #expect(records[1].parameters["outcome"] == TelemetryValue.string("user_cancelled"))
        #expect(harness.refreshCount == 0)
    }

    @Test
    func thrownCancellationEmitsTheSameSingleCancelledTerminal() async {
        let harness = Self.makePurchaseHarness(refreshedState: .inactive)
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
        let harness = Self.makePurchaseHarness(refreshedState: .inactive)
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
        let harness = Self.makePurchaseHarness(refreshedState: .inactive)
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
        Self.expectNoRawErrorText(in: records)
    }

    @Test
    func purchaseWithoutActiveEntitlementIsFailedInsteadOfCompleted() async {
        let harness = Self.makePurchaseHarness(refreshedState: .inactive)
        Self.recordPaywallContext(in: harness.contextStore)

        let result = await harness.executor.executePurchase(productID: Self.productID) {
            RevenueCatPurchaseExecutor.PurchaseResponse(userCancelled: false)
        }

        let records = harness.sink.records
        #expect(records.map(\.name) == [
            "revenuecat_purchase_started",
            "revenuecat_purchase_failed"
        ])
        Self.expectOnePurchaseTerminal(in: records)
        #expect(Self.superwallTerminalName(for: result) == "paywall_transaction_failed")
        #expect(records[1].parameters["error_type"] == TelemetryValue.string("no_active_entitlement"))
        #expect(Self.presentedMessage(for: result) == "Ascend couldn't confirm your subscription. Check your connection and try again.")
    }

    @Test
    func anUnresolvedRefreshFailsThePurchaseWithoutClaimingALapse() async {
        let harness = Self.makePurchaseHarness(refreshedState: .unknown)
        Self.recordPaywallContext(in: harness.contextStore)

        let result = await harness.executor.executePurchase(productID: Self.productID) {
            RevenueCatPurchaseExecutor.PurchaseResponse(userCancelled: false)
        }

        let records = harness.sink.records
        #expect(records.map(\.name) == [
            "revenuecat_purchase_started",
            "revenuecat_purchase_failed"
        ])
        Self.expectOnePurchaseTerminal(in: records)
        #expect(Self.superwallTerminalName(for: result) == "paywall_transaction_failed")
        #expect(records[1].parameters["error_type"] == TelemetryValue.string("entitlement_unresolved"))
        #expect(harness.published.isEmpty)
    }

    @Test
    func missingStoreProductEmitsOneFailureWithoutClaimingARevenueCatStart() {
        let harness = Self.makePurchaseHarness(refreshedState: .inactive)
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

    /// Every message a climber can be shown names Ascend and an action, never RevenueCat,
    /// Superwall, or the internal entitlement ID.
    @Test
    func noPurchaseOrRestoreErrorLeaksVendorOrEntitlementWording() {
        let messages = [
            RevenueCatPurchaseControllerError.missingStoreKitProduct,
            .monetizationUnavailable,
            .entitlementUnconfirmed,
            .noPurchasesFound
        ].map { $0.localizedDescription }

        for message in messages {
            #expect(!message.localizedStandardContains("RevenueCat"))
            #expect(!message.localizedStandardContains("Superwall"))
            #expect(!message.localizedStandardContains("app_access"))
            #expect(!message.localizedStandardContains("StoreKit"))
            #expect(!message.isEmpty)
        }
        #expect(
            RevenueCatPurchaseControllerError.noPurchasesFound.localizedDescription
                == "No purchases found to restore."
        )
    }

    // MARK: - Restore

    @Test
    func successfulRestoreEmitsOneCompletedTerminalAndReturnsRestored() async {
        let harness = Self.makeRestoreHarness(restoredState: .active([Self.entitlementID]))

        let outcome = await harness.service.restore()

        let records = harness.sink.records
        #expect(records.map(\.name) == [
            "revenuecat_restore_started",
            "revenuecat_restore_completed"
        ])
        Self.expectOneRestoreTerminal(in: records)
        #expect(Self.isRestored(outcome))
        #expect(records[1].parameters["outcome"] == TelemetryValue.string("success"))
        #expect(records[1].parameters["entitlement_id"] == TelemetryValue.string(Self.entitlementID))
        #expect(records[1].parameters["entitlement_active"] == TelemetryValue.bool(true))
    }

    @Test
    func restoreWithoutAnyPurchaseEmitsOneNotFoundTerminal() async {
        let harness = Self.makeRestoreHarness(restoredState: .inactive)

        let outcome = await harness.service.restore()

        let records = harness.sink.records
        #expect(records.map(\.name) == [
            "revenuecat_restore_started",
            "revenuecat_restore_not_found"
        ])
        Self.expectOneRestoreTerminal(in: records)
        #expect(Self.isNotFound(outcome))
        #expect(records[1].parameters["outcome"] == TelemetryValue.string("no_entitlement"))
        #expect(records[1].parameters["entitlement_id"] == TelemetryValue.string(Self.entitlementID))
        #expect(records[1].parameters["entitlement_active"] == TelemetryValue.bool(false))
    }

    @Test
    func restoreThatResolvesOtherEntitlementsIsStillNotFound() async {
        let harness = Self.makeRestoreHarness(restoredState: .active(["some_other_entitlement"]))

        let outcome = await harness.service.restore()

        #expect(harness.sink.records.map(\.name) == [
            "revenuecat_restore_started",
            "revenuecat_restore_not_found"
        ])
        #expect(Self.isNotFound(outcome))
    }

    @Test
    func anUnresolvedRestoreFailsWithoutAssertingTheEntitlementIsInactive() async {
        let harness = Self.makeRestoreHarness(restoredState: .unknown)

        let outcome = await harness.service.restore()

        let records = harness.sink.records
        #expect(records.map(\.name) == [
            "revenuecat_restore_started",
            "revenuecat_restore_failed"
        ])
        Self.expectOneRestoreTerminal(in: records)
        #expect(Self.isFailed(outcome))
        #expect(records[1].parameters["outcome"] == TelemetryValue.string("failed"))
        #expect(records[1].parameters["error_type"] == TelemetryValue.string("entitlement_unresolved"))
        #expect(records[1].parameters["entitlement_active"] == nil)
    }

    @Test
    func failedRestoreEmitsOneFailedTerminalWithBoundedErrorAndNoEntitlementClaim() async {
        let harness = Self.makeRestoreHarness(
            restoredState: .inactive,
            restoreError: ErrorCode.networkError
        )

        let outcome = await harness.service.restore()

        let records = harness.sink.records
        #expect(records.map(\.name) == [
            "revenuecat_restore_started",
            "revenuecat_restore_failed"
        ])
        Self.expectOneRestoreTerminal(in: records)
        #expect(Self.isFailed(outcome))
        #expect(records[1].parameters["outcome"] == TelemetryValue.string("failed"))
        #expect(records[1].parameters["error_type"] == TelemetryValue.string("network"))
        #expect(records[1].parameters["entitlement_active"] == nil)
        Self.expectNoRawErrorText(in: records)
    }

    @Test
    func anUnconfiguredRestoreEmitsOneFailureWithoutClaimingARevenueCatStart() async {
        let harness = Self.makeRestoreHarness(
            restoredState: .inactive,
            isRevenueCatConfigured: false
        )

        let outcome = await harness.service.restore()

        let records = harness.sink.records
        #expect(records.map(\.name) == ["revenuecat_restore_failed"])
        Self.expectOneRestoreTerminal(in: records)
        #expect(Self.isFailed(outcome))
        #expect(records[0].parameters["error_type"] == TelemetryValue.string("configuration"))
        #expect(harness.restorer.restoreCount == 0)
    }

    // MARK: - Every restore entry point runs the same contract

    @Test
    func theSuperwallRestoreEntryPointEmitsExactlyOneTerminalPerOutcome() async {
        for restoredState in [
            MonetizationEntitlementState.active([Self.entitlementID]),
            .inactive,
            .unknown
        ] {
            let harness = Self.makeRestoreHarness(restoredState: restoredState)
            let controller = RevenueCatPurchaseController(
                coordinator: { harness.restorer },
                applySuperwallStatus: { _ in },
                restoreService: harness.service
            )

            _ = await controller.restorePurchases()

            #expect(harness.sink.records.first?.name == "revenuecat_restore_started")
            Self.expectOneRestoreTerminal(in: harness.sink.records)
        }
    }

    @Test
    func theSuperwallRestoreNeverReportsRestoredWhenThereIsNothingToRestore() async {
        let harness = Self.makeRestoreHarness(restoredState: .inactive)
        var published: [SuperwallKit.SubscriptionStatus] = []
        let controller = RevenueCatPurchaseController(
            coordinator: { harness.restorer },
            applySuperwallStatus: { published.append($0) },
            restoreService: harness.service
        )

        let result = await controller.restorePurchases()

        #expect(result != .restored)
        #expect(published.isEmpty)
        #expect(Self.restoreResultErrorMessage(for: result) == "No purchases found to restore.")
        #expect(harness.sink.records.map(\.name).contains("revenuecat_restore_completed") == false)
        #expect(harness.sink.records.map(\.name).contains("paywall_restore_completed") == false)
    }

    @Test
    func theAccountRestoreEntryPointEmitsExactlyOneTerminalPerOutcome() async {
        let expectations: [(MonetizationEntitlementState, String, String)] = [
            (.active([Self.entitlementID]), "revenuecat_restore_completed", "Restore Complete"),
            (.inactive, "revenuecat_restore_not_found", "No purchases found to restore."),
            (.unknown, "revenuecat_restore_failed", "Restore Failed")
        ]

        for (restoredState, terminalName, alertTitle) in expectations {
            let harness = Self.makeRestoreHarness(restoredState: restoredState)
            let viewModel = RestorePurchasesViewModel(restoreService: harness.service)

            await viewModel.restorePurchases()

            #expect(harness.sink.records.map(\.name) == [
                "revenuecat_restore_started",
                terminalName
            ])
            Self.expectOneRestoreTerminal(in: harness.sink.records)
            #expect(viewModel.result?.title == alertTitle)
        }
    }

    /// The only sentence the climber is shown is the contract's, verbatim and exactly once - the
    /// alert carries no paraphrased heading above it.
    @Test
    func theAccountRestoreShowsTheExactNoPurchasesCopy() async {
        let harness = Self.makeRestoreHarness(restoredState: .inactive)
        let viewModel = RestorePurchasesViewModel(restoreService: harness.service)

        await viewModel.restorePurchases()

        #expect(viewModel.result == .noPurchasesFound)
        #expect(viewModel.result?.title == Self.noPurchasesCopy)
        #expect(viewModel.result?.message == nil)
    }

    /// An unresolved restore never borrows the conclusive negative's event, result, or wording: it
    /// says the operation failed and asks for a retry, and claims nothing about what the climber owns.
    @Test
    func theAccountRestoreKeepsFailureGenericAndDistinctFromTheConclusiveNegative() async {
        let harness = Self.makeRestoreHarness(restoredState: .unknown)
        let viewModel = RestorePurchasesViewModel(restoreService: harness.service)

        await viewModel.restorePurchases()

        #expect(viewModel.result == .failed)
        #expect(viewModel.result != .noPurchasesFound)
        #expect(viewModel.result?.title == "Restore Failed")
        #expect(
            viewModel.result?.message
                == "Ascend couldn't restore your purchases. Check your connection and try again."
        )
        Self.expectClaimsNothingAboutOwnership(viewModel.result?.title)
        Self.expectClaimsNothingAboutOwnership(viewModel.result?.message)
    }

    @Test
    func theAppAccessGateRestoreEntryPointEmitsExactlyOneTerminalPerOutcome() async {
        let expectations: [(MonetizationEntitlementState, String, AppAccessRestoreState)] = [
            (.active([Self.entitlementID]), "revenuecat_restore_completed", .restored),
            (.inactive, "revenuecat_restore_not_found", .noPurchasesFound),
            (.unknown, "revenuecat_restore_failed", .failed)
        ]

        for (restoredState, terminalName, expectedState) in expectations {
            let harness = Self.makeRestoreHarness(restoredState: restoredState)

            let gateState = AppAccessRestoreState(outcome: await harness.service.restore())

            #expect(harness.sink.records.map(\.name) == [
                "revenuecat_restore_started",
                terminalName
            ])
            Self.expectOneRestoreTerminal(in: harness.sink.records)
            #expect(gateState == expectedState)
        }
    }

    @Test
    func theAppAccessGateShowsTheExactNoPurchasesCopy() {
        #expect(AppAccessRestoreState.noPurchasesFound.statusMessage == Self.noPurchasesCopy)
        // The conclusive negative reads as a finished operation the climber may simply repeat.
        #expect(
            AppAccessRestoreState.noPurchasesFound.buttonTitle(isRevenueCatConfigured: true)
                == AppAccessRestoreState.idle.buttonTitle(isRevenueCatConfigured: true)
        )
    }

    @Test
    func theAppAccessGateKeepsFailureGenericAndDistinctFromTheConclusiveNegative() {
        #expect(AppAccessRestoreState.failed != .noPurchasesFound)
        #expect(
            AppAccessRestoreState.failed.statusMessage
                == "Ascend couldn't restore your purchases. Check your connection and try again."
        )
        #expect(AppAccessRestoreState.failed.buttonTitle(isRevenueCatConfigured: true) == "Restore Failed")
        Self.expectClaimsNothingAboutOwnership(AppAccessRestoreState.failed.statusMessage)
        Self.expectClaimsNothingAboutOwnership(
            AppAccessRestoreState.failed.buttonTitle(isRevenueCatConfigured: true)
        )
    }

    /// Every climber-visible sentence for a conclusive negative, across every restore surface, is
    /// the one contract sentence. A paraphrase anywhere is what this test exists to catch.
    @Test
    func noRestoreSurfaceParaphrasesTheConclusiveNegative() {
        let visibleNoPurchasesCopy = [
            AppAccessRestoreState.noPurchasesFound.statusMessage,
            RestorePurchasesViewModel.Result.noPurchasesFound.title,
            RestorePurchasesViewModel.Result.noPurchasesFound.message,
            RevenueCatPurchaseControllerError.noPurchasesFound.errorDescription
        ].compactMap { $0 }

        #expect(Set(visibleNoPurchasesCopy) == [Self.noPurchasesCopy])
    }

    private static let noPurchasesCopy = "No purchases found to restore."

    /// Failure copy is about the operation, never about what the climber owns - an unresolved
    /// restore is not evidence of a lapsed or absent subscription.
    private static func expectClaimsNothingAboutOwnership(
        _ copy: String?,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let copy else {
            Issue.record("Expected visible failure copy", sourceLocation: sourceLocation)
            return
        }
        #expect(copy != noPurchasesCopy, sourceLocation: sourceLocation)
        for ownershipClaim in ["no purchases", "nothing to restore", "no subscription", "not subscribed"] {
            #expect(
                !copy.localizedStandardContains(ownershipClaim),
                "Failure copy must not imply what the climber owns: \(copy)",
                sourceLocation: sourceLocation
            )
        }
    }
}

// MARK: - Harness

@MainActor
private final class RestorerStub: PaywallPurchaseCoordinating {
    var isRevenueCatConfigured: Bool
    private(set) var restoreCount = 0
    private let restoredState: MonetizationEntitlementState
    private let restoreError: (any Error)?

    init(
        restoredState: MonetizationEntitlementState,
        restoreError: (any Error)? = nil,
        isRevenueCatConfigured: Bool = true
    ) {
        self.restoredState = restoredState
        self.restoreError = restoreError
        self.isRevenueCatConfigured = isRevenueCatConfigured
    }

    @discardableResult
    func refreshEntitlements(
        force: Bool,
        waitsForPendingIdentity: Bool
    ) async -> MonetizationEntitlementRefresh {
        .refreshed(restoredState)
    }

    @discardableResult
    func restorePurchases() async throws -> MonetizationEntitlementState {
        restoreCount += 1
        if let restoreError {
            throw restoreError
        }
        return restoredState
    }
}

@MainActor
private final class PurchaseHarness {
    let sink = InMemoryTelemetrySink(destination: .analytics)
    let contextStore = PaywallTransactionContextStore()
    private(set) var published: [Set<String>] = []
    private(set) var refreshCount = 0
    private(set) var executor: RevenueCatPurchaseExecutor!

    init(entitlementID: String, refresh: MonetizationEntitlementRefresh) {
        executor = RevenueCatPurchaseExecutor(
            telemetry: makeTestTelemetry(sink: sink),
            transactionContextStore: contextStore,
            entitlementID: entitlementID,
            applySubscriptionStatus: { [weak self] entitlementIDs in
                self?.published.append(entitlementIDs)
            },
            refreshEntitlementState: { [weak self] in
                self?.refreshCount += 1
                return refresh
            }
        )
    }
}

@MainActor
private extension PaywallPurchaseAnalyticsContractTests {
    typealias RestoreHarness = (
        service: AppAccessRestoreService,
        sink: InMemoryTelemetrySink,
        restorer: RestorerStub
    )

    static func makePurchaseHarness(
        refreshedState: MonetizationEntitlementState
    ) -> PurchaseHarness {
        PurchaseHarness(entitlementID: entitlementID, refresh: .refreshed(refreshedState))
    }

    static func makePurchaseHarness(
        refreshFailure: MonetizationEntitlementRefreshFailure
    ) -> PurchaseHarness {
        PurchaseHarness(entitlementID: entitlementID, refresh: .unavailable(refreshFailure))
    }

    static func makeRestoreHarness(
        restoredState: MonetizationEntitlementState,
        restoreError: (any Error)? = nil,
        isRevenueCatConfigured: Bool = true
    ) -> RestoreHarness {
        let sink = InMemoryTelemetrySink(destination: .analytics)
        let restorer = RestorerStub(
            restoredState: restoredState,
            restoreError: restoreError,
            isRevenueCatConfigured: isRevenueCatConfigured
        )
        let service = AppAccessRestoreService(
            telemetry: makeTestTelemetry(sink: sink),
            entitlementID: entitlementID,
            restorer: { restorer }
        )
        return (service, sink, restorer)
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

    /// `error_type` is the only error surface a terminal carries, and it is always one of the
    /// bounded `RevenueCatAnalyticsErrorType` values.
    static func expectNoRawErrorText(in records: [EnvelopedTelemetryRecord]) {
        let bounded = Set(
            [
                RevenueCatAnalyticsErrorType.configuration,
                .entitlementRefreshFailed,
                .entitlementRefreshTimedOut,
                .entitlementUnresolved,
                .missingStoreProduct,
                .network,
                .noActiveEntitlement,
                .purchaseNotAllowed,
                .receipt,
                .store,
                .unknown
            ].map(\.rawValue)
        )

        for record in records {
            #expect(record.parameters["error"] == nil)
            #expect(record.parameters["message"] == nil)
            guard case .string(let errorType)? = record.parameters["error_type"] else { continue }
            #expect(bounded.contains(errorType))
        }
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

    static func presentedMessage(for result: SuperwallKit.PurchaseResult) -> String? {
        guard case .failed(let error) = result else { return nil }
        return error.localizedDescription
    }

    /// The message inside the `RestorationResult`, not the alert Superwall shows. Superwall's
    /// restore-failure alert presents `options.paywalls.restoreFailed` and discards this error, so
    /// on the paywall surface only telemetry carries the nothing-found reason.
    static func restoreResultErrorMessage(for result: SuperwallKit.RestorationResult) -> String? {
        guard case .failed(let error) = result else { return nil }
        return error?.localizedDescription
    }

    static func isRestored(_ outcome: AppAccessRestoreOutcome) -> Bool {
        if case .restored = outcome { return true }
        return false
    }

    static func isNotFound(_ outcome: AppAccessRestoreOutcome) -> Bool {
        if case .notFound = outcome { return true }
        return false
    }

    static func isFailed(_ outcome: AppAccessRestoreOutcome) -> Bool {
        if case .failed = outcome { return true }
        return false
    }
}
