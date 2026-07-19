import Foundation
import Observation

@MainActor
@Observable
final class RestorePurchasesViewModel {
    enum Result: Hashable, Identifiable {
        case restored
        case failed

        var id: Self { self }

        var title: String {
            switch self {
            case .restored:
                return "Restore Complete"
            case .failed:
                return "Restore Failed"
            }
        }

        var message: String {
            switch self {
            case .restored:
                return "Ascend checked your App Store purchases and updated your access."
            case .failed:
                return "Ascend couldn't restore your purchases. Check your connection and try again."
            }
        }
    }

    private(set) var isRestoring = false
    var result: Result?

    private let purchaseRestorer: any PurchaseRestoring

    init(purchaseRestorer: any PurchaseRestoring = MonetizationManager.shared) {
        self.purchaseRestorer = purchaseRestorer
    }

    var isRestoreAvailable: Bool {
        purchaseRestorer.isRevenueCatConfigured
    }

    func restorePurchases() async {
        guard !isRestoring else { return }
        guard isRestoreAvailable else {
            result = .failed
            return
        }

        isRestoring = true
        result = nil
        defer { isRestoring = false }

        do {
            try await purchaseRestorer.restorePurchases()
            result = .restored
        } catch {
            result = .failed
        }
    }
}
