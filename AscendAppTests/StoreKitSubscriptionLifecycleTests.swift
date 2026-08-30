import Foundation
import StoreKit
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

    @Test
    func billingRetryWithGraceCanBeResolvedDeterministically() async throws {
        let session = try makeSession()
        defer { cleanUp(session) }
        // A two-second renewal can move through grace before StoreKit's public status catches up.
        // Ten seconds keeps the billing-retry window observable while remaining fast and bounded.
        session.timeRate = .oneRenewalEveryTenSeconds
        session.shouldEnterBillingRetryOnRenewal = true
        session.billingGracePeriodIsEnabled = true
        _ = try await session.buyProduct(identifier: monthlyProductID)

        let retrying = try await waitForTestTransaction(session: session) {
            $0.productIdentifier == monthlyProductID && $0.hasPurchaseIssue
        }
        #expect(retrying.expirationDate != nil)
        let retryingStatus = try await waitForSubscriptionStatus(productID: monthlyProductID) { status in
            let renewal = status.renewalInfo.unsafePayloadValue
            return status.state == .inGracePeriod
                && renewal.isInBillingRetry
                && renewal.gracePeriodExpirationDate != nil
        }
        #expect(retryingStatus.state == .inGracePeriod)

        session.shouldEnterBillingRetryOnRenewal = false
        try session.resolveIssueForTransaction(identifier: retrying.identifier)
        let resolvedStatus = try await waitForSubscriptionStatus(productID: monthlyProductID) { status in
            status.state == .subscribed
                && !status.renewalInfo.unsafePayloadValue.isInBillingRetry
        }
        #expect(resolvedStatus.state == .subscribed)
        let resolved = try await waitForTestTransaction(session: session) {
            $0.identifier == retrying.identifier && !$0.hasPurchaseIssue
        }
        #expect(!resolved.hasPurchaseIssue)
    }

    private func waitForSubscriptionStatus(
        productID: String,
        matching predicate: (Product.SubscriptionInfo.Status) -> Bool
    ) async throws -> Product.SubscriptionInfo.Status {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(20)
        while clock.now < deadline {
            if let product = try await Product.products(for: [productID]).first,
               let subscription = product.subscription,
               let status = try await subscription.status.first(where: predicate) {
                return status
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw StoreKitLifecycleTestError.timedOutWaitingForSubscriptionStatus
    }

    private func waitForTestTransaction(
        session: SKTestSession,
        matching predicate: (SKTestTransaction) -> Bool
    ) async throws -> SKTestTransaction {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(20)
        while clock.now < deadline {
            if let transaction = session.allTransactions().first(where: predicate) {
                return transaction
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw StoreKitLifecycleTestError.timedOutWaitingForTestTransaction
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

private enum StoreKitLifecycleTestError: Error {
    case timedOutWaitingForSubscriptionStatus
    case timedOutWaitingForTestTransaction
}
