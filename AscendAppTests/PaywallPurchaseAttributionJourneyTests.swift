import Foundation
import RevenueCat
import SuperwallKit
import Testing
@testable import AscendApp

/// The purchase terminals are only attributed if the store the Superwall delegate writes into is the
/// same one the executor reads out of. Every other purchase test injects its own store, so nothing
/// exercised the default wiring `SuperwallPaywallPresenter` and `RevenueCatPurchaseExecutor` actually
/// ship with. This drives that shared path with the exact call the delegate makes on
/// `.transactionStart` and renders the join an analyst performs between `paywall_transaction_started`
/// and each RevenueCat terminal.
@MainActor
struct PaywallPurchaseAttributionJourneyTests {
    private static let entitlementID = "app_access"
    private static let placement = "winback_lapsed_yearly"
    private static let presentationID = "pres_3d81c4"

    @Test
    func theSharedStoreTheSuperwallDelegateWritesToAttributesEveryTerminal() async {
        var rows: [JoinRow] = []

        for journey in Self.journeys {
            let productID = "ascend_yearly_\(journey.key)"
            let sink = InMemoryTelemetrySink(destination: .analytics)
            let executor = Self.makeSharedStoreExecutor(sink: sink, refresh: journey.refresh)

            // Exactly what SuperwallPaywallPresenter.handleSuperwallEvent(.transactionStart) does:
            // stash the presentation's own placement and ID against the product being bought.
            PaywallTransactionContextStore.shared.record(
                placement: Self.placement,
                presentationID: Self.presentationID,
                productID: productID
            )

            let result = await executor.executePurchase(productID: productID) {
                if let error = journey.thrownError { throw error }
                return RevenueCatPurchaseExecutor.PurchaseResponse(userCancelled: journey.userCancelled)
            }

            let records = sink.records
            #expect(records.map(\.name) == ["revenuecat_purchase_started", journey.expectedTerminal])
            #expect(records.filter { Self.terminals.contains($0.name) }.count == 1)
            for record in records {
                #expect(
                    record.parameters["placement"] == .string(Self.placement),
                    "\(journey.title) lost the presentation's placement on \(record.name)"
                )
                #expect(
                    record.parameters["presentation_id"] == .string(Self.presentationID),
                    "\(journey.title) lost the presentation ID on \(record.name)"
                )
                #expect(record.parameters["product_id"] == .string(productID))
            }
            rows.append(
                JoinRow(
                    situation: journey.title,
                    events: records.map(\.name),
                    placement: Self.value(records.last?.parameters["placement"]),
                    presentationID: Self.value(records.last?.parameters["presentation_id"]),
                    outcome: Self.value(records.last?.parameters["outcome"]),
                    appResult: Self.describe(result)
                )
            )
        }

        // A failure raised before RevenueCat is ever called cannot claim a purchase started, but its
        // one terminal still belongs to the exact gate presentation that attempted the handoff.
        let preCallProductID = "ascend_yearly_pre_call"
        let preCallSink = InMemoryTelemetrySink(destination: .analytics)
        let preCallExecutor = Self.makeSharedStoreExecutor(
            sink: preCallSink,
            refresh: .refreshed(.active([Self.entitlementID]))
        )
        PaywallTransactionContextStore.shared.record(
            placement: Self.placement,
            presentationID: Self.presentationID,
            productID: preCallProductID
        )

        let preCallResult = preCallExecutor.failPurchaseBeforeRevenueCatCall(
            productID: preCallProductID,
            error: RevenueCatPurchaseControllerError.missingStoreKitProduct,
            errorType: .missingStoreProduct
        )

        let preCallRecords = preCallSink.records
        #expect(preCallRecords.map(\.name) == ["revenuecat_purchase_failed"])
        #expect(preCallRecords[0].parameters["placement"] == .string(Self.placement))
        #expect(preCallRecords[0].parameters["presentation_id"] == .string(Self.presentationID))
        #expect(preCallRecords[0].parameters["error_type"] == .string("missing_store_product"))
        rows.append(
            JoinRow(
                situation: "StoreKit cannot resolve the product (no RevenueCat call)",
                events: preCallRecords.map(\.name),
                placement: Self.value(preCallRecords[0].parameters["placement"]),
                presentationID: Self.value(preCallRecords[0].parameters["presentation_id"]),
                outcome: Self.value(preCallRecords[0].parameters["outcome"]),
                appResult: Self.describe(preCallResult)
            )
        )

        // The stash belongs to one presentation. A purchase retried without a new presentation is
        // honestly unattributed rather than inheriting the dead one's campaign.
        let retrySink = InMemoryTelemetrySink(destination: .analytics)
        let retryExecutor = Self.makeSharedStoreExecutor(
            sink: retrySink,
            refresh: .refreshed(.active([Self.entitlementID]))
        )
        let retryResult = await retryExecutor.executePurchase(productID: preCallProductID) {
            RevenueCatPurchaseExecutor.PurchaseResponse(userCancelled: false)
        }
        let retryRecords = retrySink.records
        #expect(retryRecords.map(\.name) == [
            "revenuecat_purchase_started",
            "revenuecat_purchase_completed"
        ])
        for record in retryRecords {
            #expect(record.parameters["placement"] == .string("unknown"))
            #expect(record.parameters["presentation_id"] == nil)
        }
        rows.append(
            JoinRow(
                situation: "retries the same product with no new presentation",
                events: retryRecords.map(\.name),
                placement: Self.value(retryRecords.last?.parameters["placement"]),
                presentationID: Self.value(retryRecords.last?.parameters["presentation_id"]),
                outcome: Self.value(retryRecords.last?.parameters["outcome"]),
                appResult: Self.describe(retryResult)
            )
        )

        print(Self.render(rows))
    }
}

// MARK: - Journeys

private extension PaywallPurchaseAttributionJourneyTests {
    struct Journey {
        let key: String
        let title: String
        var refresh: MonetizationEntitlementRefresh = .refreshed(.inactive)
        var userCancelled = false
        var thrownError: (any Error)?
        let expectedTerminal: String
    }

    struct JoinRow {
        let situation: String
        let events: [String]
        let placement: String
        let presentationID: String
        let outcome: String
        let appResult: String
    }

    static let terminals: Set<String> = [
        "revenuecat_purchase_completed",
        "revenuecat_purchase_cancelled",
        "revenuecat_purchase_pending",
        "revenuecat_purchase_failed"
    ]

    static var journeys: [Journey] {
        [
            Journey(
                key: "completed",
                title: "buys from the win-back campaign",
                refresh: .refreshed(.active([entitlementID])),
                expectedTerminal: "revenuecat_purchase_completed"
            ),
            Journey(
                key: "cancelled",
                title: "cancels the App Store sheet",
                userCancelled: true,
                expectedTerminal: "revenuecat_purchase_cancelled"
            ),
            Journey(
                key: "pending",
                title: "purchase waits on Ask to Buy",
                thrownError: ErrorCode.paymentPendingError,
                expectedTerminal: "revenuecat_purchase_pending"
            ),
            Journey(
                key: "failed",
                title: "purchase fails on the network",
                thrownError: ErrorCode.networkError,
                expectedTerminal: "revenuecat_purchase_failed"
            )
        ]
    }

    /// No `transactionContextStore` argument: this is the default the app ships, so the executor
    /// reads `PaywallTransactionContextStore.shared` - the store the delegate writes into.
    static func makeSharedStoreExecutor(
        sink: InMemoryTelemetrySink,
        refresh: MonetizationEntitlementRefresh
    ) -> RevenueCatPurchaseExecutor {
        RevenueCatPurchaseExecutor(
            telemetry: makeTestTelemetry(sink: sink),
            entitlementID: entitlementID,
            applySubscriptionStatus: { _ in },
            refreshEntitlementState: { refresh }
        )
    }

    static func value(_ parameter: TelemetryValue?) -> String {
        guard let parameter else { return "-" }
        return parameter.stringValue
    }

    static func describe(_ result: SuperwallKit.PurchaseResult) -> String {
        switch result {
        case .purchased: "purchased"
        case .cancelled: "cancelled"
        case .pending: "pending"
        case .failed: "failed"
        }
    }

    static func render(_ rows: [JoinRow]) -> String {
        var lines: [String] = [
            "",
            "================================================================================",
            " PAYWALL -> PURCHASE ATTRIBUTION JOIN - through the shared store the Superwall",
            " delegate writes on .transactionStart and the shipped executor default reads",
            "================================================================================",
            " Superwall presentation: placement=\(placement) presentation_id=\(presentationID)"
        ]
        for row in rows {
            lines.append("")
            lines.append("● \(row.situation)")
            lines.append("  events             \(row.events.joined(separator: " -> "))")
            lines.append("  placement          \(row.placement)")
            lines.append("  presentation_id    \(row.presentationID)")
            lines.append("  outcome            \(row.outcome)")
            lines.append("  app result         \(row.appResult)")
        }
        lines.append("================================================================================")
        return lines.joined(separator: "\n")
    }
}
