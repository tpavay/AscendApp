import Foundation
import Testing
@testable import AscendApp

@MainActor
struct RestorePurchasesViewModelTests {
    @Test
    func successfulRestoreConfirmsCompletion() async {
        let restorer = StubPurchaseRestorer()
        let viewModel = RestorePurchasesViewModel(purchaseRestorer: restorer)

        await viewModel.restorePurchases()

        #expect(restorer.restoreCount == 1)
        #expect(viewModel.isRestoring == false)
        #expect(viewModel.result?.title == "Restore Complete")
    }

    @Test
    func failedRestoreSurfacesRetryGuidance() async {
        let restorer = StubPurchaseRestorer(error: StubRestoreError.offline)
        let viewModel = RestorePurchasesViewModel(purchaseRestorer: restorer)

        await viewModel.restorePurchases()

        #expect(restorer.restoreCount == 1)
        #expect(viewModel.isRestoring == false)
        #expect(viewModel.result?.title == "Restore Failed")
        #expect(viewModel.result?.message.contains("try again") == true)
    }

    @Test
    func unavailableRestoreFailsWithoutCallingTheStore() async {
        let restorer = StubPurchaseRestorer(isRevenueCatConfigured: false)
        let viewModel = RestorePurchasesViewModel(purchaseRestorer: restorer)

        await viewModel.restorePurchases()

        #expect(restorer.restoreCount == 0)
        #expect(viewModel.result?.title == "Restore Failed")
    }

    @Test
    func restoreShowsProgressAndIgnoresASecondRequest() async {
        let restorer = SuspendingPurchaseRestorer()
        let viewModel = RestorePurchasesViewModel(purchaseRestorer: restorer)

        async let restoration: Void = viewModel.restorePurchases()
        await restorer.waitUntilRestoreStarts()

        #expect(viewModel.isRestoring)
        await viewModel.restorePurchases()
        #expect(restorer.restoreCount == 1)

        restorer.finishRestore()
        await restoration

        #expect(viewModel.isRestoring == false)
        #expect(viewModel.result?.title == "Restore Complete")
    }
}

private enum StubRestoreError: Error {
    case offline
}

@MainActor
private final class StubPurchaseRestorer: PurchaseRestoring {
    let isRevenueCatConfigured: Bool
    private let error: Error?
    private(set) var restoreCount = 0

    init(isRevenueCatConfigured: Bool = true, error: Error? = nil) {
        self.isRevenueCatConfigured = isRevenueCatConfigured
        self.error = error
    }

    func restorePurchases() async throws {
        restoreCount += 1

        if let error {
            throw error
        }
    }
}

@MainActor
private final class SuspendingPurchaseRestorer: PurchaseRestoring {
    let isRevenueCatConfigured = true
    private(set) var restoreCount = 0

    private var restoreContinuation: CheckedContinuation<Void, Never>?
    private var startObserver: CheckedContinuation<Void, Never>?

    func restorePurchases() async {
        restoreCount += 1
        startObserver?.resume()
        startObserver = nil

        await withCheckedContinuation { continuation in
            restoreContinuation = continuation
        }
    }

    func waitUntilRestoreStarts() async {
        guard restoreCount == 0 else { return }

        await withCheckedContinuation { continuation in
            startObserver = continuation
        }
    }

    func finishRestore() {
        restoreContinuation?.resume()
        restoreContinuation = nil
    }
}
