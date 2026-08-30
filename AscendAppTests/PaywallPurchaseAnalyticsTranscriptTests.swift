import Foundation
import RevenueCat
import SuperwallKit
import Testing
@testable import AscendApp

/// The purchase and restore contract is only readable as the stream an analyst sees: one block per
/// situation a climber can actually land in, the events that situation ships in order, and the
/// properties each one carries. This renders that transcript from real emissions - the same
/// `RevenueCatPurchaseExecutor` and `AppAccessRestoreService` the app runs - and fails the moment a
/// situation ships more than one terminal, ships a `completed` name for anything but verified
/// `app_access`, or leaks raw error text.
@MainActor
struct PaywallPurchaseAnalyticsTranscriptTests {
    private static let productID = "ascend_yearly"
    private static let entitlementID = "app_access"
    nonisolated private static let placement = SuperwallPlacement.onboardingPaywall.rawValue
    nonisolated private static let presentationID = "pres_9f2c"

    @Test
    func everyPurchaseAndRestoreSituationShipsExactlyOneHonestTerminal() async {
        var transcript = TranscriptRenderer()
        var completedNames: [String] = []

        for situation in Self.purchaseSituations {
            let harness = PurchaseHarness(entitlementID: Self.entitlementID, refresh: situation.refresh)
            if situation.hasPaywallContext {
                harness.contextStore.record(
                    placement: Self.placement,
                    presentationID: Self.presentationID,
                    productID: Self.productID
                )
            }

            let result: SuperwallKit.PurchaseResult
            if let preCallFailure = situation.preCallFailure {
                result = harness.executor.failPurchaseBeforeRevenueCatCall(
                    productID: Self.productID,
                    error: RevenueCatPurchaseControllerError.missingStoreKitProduct,
                    errorType: preCallFailure
                )
            } else {
                result = await harness.executor.executePurchase(productID: Self.productID) {
                    if let error = situation.thrownError { throw error }
                    return RevenueCatPurchaseExecutor.PurchaseResponse(
                        userCancelled: situation.userCancelled
                    )
                }
            }

            let records = harness.sink.records
            transcript.append(
                heading: "PURCHASE - \(situation.title)",
                climberSees: situation.climberSees,
                records: records,
                terminalLine: "superwall terminal   \(Self.superwallTerminalName(for: result))",
                resultLine: "app result           \(Self.describe(result))"
            )

            let terminals = records.map(\.name).filter { Self.purchaseTerminals.contains($0) }
            #expect(terminals.count == 1, "\(situation.title) shipped terminals \(terminals)")
            #expect(terminals.first == situation.expectedTerminal, "\(situation.title)")
            #expect(records.map(\.name) == situation.expectedStream, "\(situation.title)")
            #expect(Self.superwallTerminalName(for: result) == situation.expectedSuperwallTerminal)
            guard let terminal = records.last else {
                Issue.record("\(situation.title) shipped no terminal event")
                continue
            }
            #expect(
                terminal.parameters["placement"] == .string(situation.expectedPlacement),
                "\(situation.title) lost its paywall placement"
            )
            #expect(
                terminal.parameters["presentation_id"]
                    == situation.expectedPresentationID.map(TelemetryValue.string),
                "\(situation.title) lost its presentation ID"
            )
            Self.expectNoRawErrorText(in: records, situation: situation.title)
            completedNames.append(contentsOf: terminals.filter { $0 == "revenuecat_purchase_completed" })
        }

        for situation in Self.restoreSituations {
            let sink = InMemoryTelemetrySink(destination: .analytics)
            let restorer = RestorerStub(
                restoredState: situation.restoredState,
                restoreError: situation.restoreError,
                isRevenueCatConfigured: situation.isConfigured
            )
            let service = AppAccessRestoreService(
                telemetry: makeTestTelemetry(sink: sink),
                entitlementID: Self.entitlementID,
                restorer: { restorer }
            )

            let outcome = await service.restore()
            let records = sink.records
            let paywallRestoreCompleted = Self.superwallRestoreCompletedFires(for: outcome)

            transcript.append(
                heading: "RESTORE - \(situation.title)",
                climberSees: situation.climberSees,
                records: records,
                terminalLine: "paywall_restore_completed fires: \(paywallRestoreCompleted ? "yes" : "no")",
                resultLine: "app result           \(Self.describe(outcome))"
            )

            let terminals = records.map(\.name).filter { Self.restoreTerminals.contains($0) }
            #expect(terminals.count == 1, "\(situation.title) shipped terminals \(terminals)")
            #expect(records.map(\.name) == situation.expectedStream, "\(situation.title)")
            #expect(
                paywallRestoreCompleted == (terminals.first == "revenuecat_restore_completed"),
                "\(situation.title) disagrees with paywall_restore_completed"
            )
            Self.expectNoRawErrorText(in: records, situation: situation.title)
        }

        // Seven purchase situations run; exactly one of them is a verified `app_access` success, so
        // exactly one may carry the name that a revenue dashboard counts.
        #expect(completedNames.count == 1)
        #expect(Self.purchaseSituations.count == 7)

        transcript.appendSummary(
            [
                "purchase situations exercised            \(Self.purchaseSituations.count)",
                "situations naming revenuecat_purchase_completed   \(completedNames.count)",
                "restore situations exercised             \(Self.restoreSituations.count)",
                "restores naming revenuecat_restore_completed      1"
            ]
        )

        print(transcript.rendered)
    }
}

// MARK: - Situations

private extension PaywallPurchaseAnalyticsTranscriptTests {
    struct PurchaseSituation {
        let title: String
        let climberSees: String
        var refresh: MonetizationEntitlementRefresh = .refreshed(.inactive)
        var userCancelled = false
        var thrownError: (any Error)?
        var preCallFailure: RevenueCatAnalyticsErrorType?
        var hasPaywallContext = true
        let expectedStream: [String]
        let expectedTerminal: String
        let expectedSuperwallTerminal: String

        /// A purchase that reached RevenueCat always carries a placement; `unknown` is what a
        /// purchase with no recorded presentation reports, never a real campaign name.
        var expectedPlacement: String {
            hasPaywallContext ? PaywallPurchaseAnalyticsTranscriptTests.placement : "unknown"
        }

        var expectedPresentationID: String? {
            hasPaywallContext ? PaywallPurchaseAnalyticsTranscriptTests.presentationID : nil
        }
    }

    struct RestoreSituation {
        let title: String
        let climberSees: String
        var restoredState: MonetizationEntitlementState = .inactive
        var restoreError: (any Error)?
        var isConfigured = true
        let expectedStream: [String]
    }

    static let purchaseTerminals: Set<String> = [
        "revenuecat_purchase_completed",
        "revenuecat_purchase_cancelled",
        "revenuecat_purchase_pending",
        "revenuecat_purchase_failed"
    ]

    static let restoreTerminals: Set<String> = [
        "revenuecat_restore_completed",
        "revenuecat_restore_not_found",
        "revenuecat_restore_failed"
    ]

    static var purchaseSituations: [PurchaseSituation] {
        [
            PurchaseSituation(
                title: "buys the yearly plan and app_access goes active",
                climberSees: "Paywall closes, Ascend unlocks.",
                refresh: .refreshed(.active([entitlementID])),
                expectedStream: ["revenuecat_purchase_started", "revenuecat_purchase_completed"],
                expectedTerminal: "revenuecat_purchase_completed",
                expectedSuperwallTerminal: "paywall_transaction_completed"
            ),
            PurchaseSituation(
                title: "taps Cancel in the App Store sheet",
                climberSees: "Sheet dismisses, paywall stays up, nothing charged.",
                userCancelled: true,
                expectedStream: ["revenuecat_purchase_started", "revenuecat_purchase_cancelled"],
                expectedTerminal: "revenuecat_purchase_cancelled",
                expectedSuperwallTerminal: "paywall_transaction_abandoned"
            ),
            PurchaseSituation(
                title: "purchase needs Ask to Buy approval",
                climberSees: "\"Ask permission\" - the purchase is deferred, not granted.",
                thrownError: ErrorCode.paymentPendingError,
                expectedStream: ["revenuecat_purchase_started", "revenuecat_purchase_pending"],
                expectedTerminal: "revenuecat_purchase_pending",
                expectedSuperwallTerminal: "paywall_transaction_failed"
            ),
            PurchaseSituation(
                title: "loses connectivity mid purchase",
                climberSees: "Purchase-failed alert on the paywall.",
                thrownError: ErrorCode.networkError,
                expectedStream: ["revenuecat_purchase_started", "revenuecat_purchase_failed"],
                expectedTerminal: "revenuecat_purchase_failed",
                expectedSuperwallTerminal: "paywall_transaction_failed"
            ),
            PurchaseSituation(
                title: "Superwall hands back a product StoreKit cannot resolve",
                climberSees: "\"Ascend couldn't start that purchase.\" No RevenueCat call happened.",
                preCallFailure: .missingStoreProduct,
                expectedStream: ["revenuecat_purchase_failed"],
                expectedTerminal: "revenuecat_purchase_failed",
                expectedSuperwallTerminal: "paywall_transaction_failed"
            ),
            PurchaseSituation(
                title: "store reports done but app_access never went active",
                climberSees: "\"Ascend couldn't confirm your subscription.\" Still locked.",
                refresh: .refreshed(.inactive),
                expectedStream: ["revenuecat_purchase_started", "revenuecat_purchase_failed"],
                expectedTerminal: "revenuecat_purchase_failed",
                expectedSuperwallTerminal: "paywall_transaction_failed"
            ),
            PurchaseSituation(
                title: "entitlement refresh times out mid sign-in",
                climberSees: "\"Ascend couldn't confirm your subscription.\" Access unresolved.",
                refresh: .unavailable(.refreshTimedOut),
                expectedStream: ["revenuecat_purchase_started", "revenuecat_purchase_failed"],
                expectedTerminal: "revenuecat_purchase_failed",
                expectedSuperwallTerminal: "paywall_transaction_failed"
            )
        ]
    }

    static var restoreSituations: [RestoreSituation] {
        [
            RestoreSituation(
                title: "restores an existing yearly subscription",
                climberSees: "\"Restore Complete\" - Ascend unlocks.",
                restoredState: .active([entitlementID]),
                expectedStream: ["revenuecat_restore_started", "revenuecat_restore_completed"]
            ),
            RestoreSituation(
                title: "taps Restore with nothing ever purchased",
                climberSees: "\"No active Ascend subscription was found for this Apple ID.\" Still locked.",
                restoredState: .inactive,
                expectedStream: ["revenuecat_restore_started", "revenuecat_restore_not_found"]
            ),
            RestoreSituation(
                title: "restore resolves some other entitlement, not app_access",
                climberSees: "\"No active Ascend subscription was found for this Apple ID.\" Still locked.",
                restoredState: .active(["legacy_beta"]),
                expectedStream: ["revenuecat_restore_started", "revenuecat_restore_not_found"]
            ),
            RestoreSituation(
                title: "restore call fails on the network",
                climberSees: "\"Restore Failed.\" Says nothing about what they own.",
                restoreError: ErrorCode.networkError,
                expectedStream: ["revenuecat_restore_started", "revenuecat_restore_failed"]
            ),
            RestoreSituation(
                title: "restore returns an unresolved entitlement answer",
                climberSees: "\"Restore Failed.\" Not evidence of a lapse.",
                restoredState: .unknown,
                expectedStream: ["revenuecat_restore_started", "revenuecat_restore_failed"]
            ),
            RestoreSituation(
                title: "RevenueCat is not configured on this build",
                climberSees: "\"Ascend could not reach the App Store.\" No restore call happened.",
                isConfigured: false,
                expectedStream: ["revenuecat_restore_started", "revenuecat_restore_failed"]
            )
        ]
    }
}

// MARK: - Rendering

private struct TranscriptRenderer {
    private var lines: [String] = [
        "",
        "================================================================================",
        " PURCHASE / RESTORE ANALYTICS TRANSCRIPT - what an analyst receives per situation",
        " Rendered from real emissions of RevenueCatPurchaseExecutor + AppAccessRestoreService",
        "================================================================================"
    ]

    var rendered: String { lines.joined(separator: "\n") }

    mutating func append(
        heading: String,
        climberSees: String,
        records: [EnvelopedTelemetryRecord],
        terminalLine: String,
        resultLine: String
    ) {
        lines.append("")
        lines.append("● \(heading)")
        lines.append("  climber sees:        \(climberSees)")
        for (index, record) in records.enumerated() {
            lines.append("  \(index + 1). \(record.name)")
            // The envelope repeats the same four build constants on every event; this transcript
            // is about the contract properties that differ per terminal.
            let parameters = record.parameters
                .filter { TelemetryEnvelope.propertyKeys.contains($0.key) == false }
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value.stringValue)" }
            if parameters.isEmpty {
                lines.append("       (no properties)")
            } else {
                for parameter in parameters {
                    lines.append("       \(parameter)")
                }
            }
        }
        lines.append("  \(terminalLine)")
        lines.append("  \(resultLine)")
    }

    mutating func appendSummary(_ summaryLines: [String]) {
        lines.append("")
        lines.append("--------------------------------------------------------------------------------")
        summaryLines.forEach { lines.append(" \($0)") }
        lines.append("================================================================================")
    }
}

// MARK: - Harness

@MainActor
private final class RestorerStub: PaywallPurchaseCoordinating {
    var isRevenueCatConfigured: Bool
    let identityGeneration: MonetizationIdentityTransition? = MonetizationIdentityTransition(
        revision: 1,
        userID: "analytics-transcript-user"
    )
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
    private(set) var executor: RevenueCatPurchaseExecutor!

    init(entitlementID: String, refresh: MonetizationEntitlementRefresh) {
        executor = RevenueCatPurchaseExecutor(
            telemetry: makeTestTelemetry(sink: sink),
            transactionContextStore: contextStore,
            entitlementID: entitlementID,
            applySubscriptionStatus: { _ in },
            refreshEntitlementState: { refresh }
        )
    }
}

// MARK: - Descriptions

@MainActor
private extension PaywallPurchaseAnalyticsTranscriptTests {
    /// Superwall derives its own terminal from the `PurchaseResult` the `PurchaseController`
    /// returns, so the returned case is exactly what decides which `paywall_transaction_*` the
    /// paywall funnel records.
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

    static func describe(_ result: SuperwallKit.PurchaseResult) -> String {
        switch result {
        case .purchased:
            return "purchased - Ascend unlocked"
        case .cancelled:
            return "cancelled - paywall stays up"
        case .pending:
            return "pending - waiting on approval"
        case .failed(let error):
            return "failed - shown: \"\(error.localizedDescription)\""
        }
    }

    static func describe(_ outcome: AppAccessRestoreOutcome) -> String {
        switch outcome {
        case .restored:
            return "restored - Ascend unlocked"
        case .notFound:
            return "notFound - shown: \"No active Ascend subscription was found for this Apple ID.\""
        case .failed(let error):
            return "failed - shown: \"\(error.localizedDescription)\""
        }
    }

    /// `paywall_restore_completed` is emitted from Superwall's `transactionRestore` callback, which
    /// only runs when the controller answers `.restored`.
    static func superwallRestoreCompletedFires(for outcome: AppAccessRestoreOutcome) -> Bool {
        if case .restored = outcome { return true }
        return false
    }

    static func expectNoRawErrorText(in records: [EnvelopedTelemetryRecord], situation: String) {
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
            #expect(record.parameters["error"] == nil, "\(situation)")
            #expect(record.parameters["message"] == nil, "\(situation)")
            #expect(record.parameters["error_description"] == nil, "\(situation)")
            guard case .string(let errorType)? = record.parameters["error_type"] else { continue }
            #expect(bounded.contains(errorType), "\(situation) shipped unbounded error_type \(errorType)")
        }
    }
}
