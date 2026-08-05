import Foundation
import Observation

@MainActor
@Observable
final class RestorePurchasesViewModel {
    enum Result: Hashable, Identifiable {
        case restored
        case noPurchasesFound
        case failed

        var id: Self { self }

        var title: String {
            switch self {
            case .restored:
                return "Restore Complete"
            case .noPurchasesFound:
                return "Nothing to Restore"
            case .failed:
                return "Restore Failed"
            }
        }

        var message: String {
            switch self {
            case .restored:
                return "Ascend checked your App Store purchases and updated your access."
            case .noPurchasesFound:
                return "No purchases found to restore."
            case .failed:
                return "Ascend couldn't restore your purchases. Check your connection and try again."
            }
        }
    }

    private(set) var isRestoring = false
    var result: Result?

    private let restoreService: AppAccessRestoreService

    init(restoreService: AppAccessRestoreService = AppAccessRestoreService()) {
        self.restoreService = restoreService
    }

    var isRestoreAvailable: Bool {
        restoreService.isRestoreAvailable
    }

    func restorePurchases() async {
        guard !isRestoring else { return }

        isRestoring = true
        result = nil
        defer { isRestoring = false }

        switch await restoreService.restore() {
        case .restored:
            result = .restored
        case .notFound:
            result = .noPurchasesFound
        case .failed:
            result = .failed
        }
    }
}
