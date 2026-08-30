import Foundation
import StoreKitTest
import Testing

@Suite(.serialized)
struct StoreKitSubscriptionLifecycleTests {
    private let annualProductID = "ascend_staging_yearly"
    private let monthlyProductID = "ascend_staging_monthly"

    @Test
    func annualAndMonthlyProductsCanCompleteTransactions() async throws {
        // Products share one subscription group, so buying both in one session is a replacement,
        // not evidence that both products are individually purchasable.
        let session = try makeSession()
        defer { cleanUp(session) }
        _ = try await session.buyProduct(identifier: annualProductID)
        #expect(session.allTransactions().contains { $0.productIdentifier == annualProductID })

        session.resetToDefaultState()
        session.clearTransactions()
        _ = try await session.buyProduct(identifier: monthlyProductID)
        #expect(session.allTransactions().contains { $0.productIdentifier == monthlyProductID })
    }

    @Test
    func cancellationDisablesRenewalWithoutRevokingCurrentTransaction() async throws {
        let session = try makeSession()
        defer { cleanUp(session) }
        _ = try await session.buyProduct(identifier: monthlyProductID)
        let transaction = try #require(session.allTransactions().last)

        try session.disableAutoRenewForTransaction(identifier: transaction.identifier)
        let updated = try #require(
            session.allTransactions().first { $0.identifier == transaction.identifier }
        )

        #expect(!updated.autoRenewingEnabled)
        #expect(updated.cancelDate == nil)
    }

    @Test
    func renewalExpirationAndRefundProduceDistinctLifecycleEvidence() async throws {
        let session = try makeSession()
        defer { cleanUp(session) }
        _ = try await session.buyProduct(identifier: monthlyProductID)
        let original = try #require(session.allTransactions().last)

        try session.forceRenewalOfSubscription(productIdentifier: monthlyProductID)
        #expect(session.allTransactions().count >= 2)

        try session.expireSubscription(productIdentifier: monthlyProductID)
        #expect(session.allTransactions().contains { $0.expirationDate != nil })

        try session.refundTransaction(identifier: original.identifier)
        let refunded = try #require(
            session.allTransactions().first { $0.identifier == original.identifier }
        )
        #expect(refunded.cancelDate != nil)
    }

    private func makeSession() throws -> SKTestSession {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let configurationURL = repositoryRoot
            .appending(path: "AscendApp")
            .appending(path: "Configuration")
            .appending(path: "AscendSubscriptions.storekit")
        let session = try SKTestSession(contentsOf: configurationURL)
        session.disableDialogs = true
        session.resetToDefaultState()
        session.clearTransactions()
        return session
    }

    private func cleanUp(_ session: SKTestSession) {
        session.resetToDefaultState()
        session.clearTransactions()
    }
}
