import Foundation

enum AppAccessRestoreState: Equatable, Sendable {
    case idle
    case restoring
    case restored
    case noPurchasesFound
    case failed

    init(outcome: AppAccessRestoreOutcome) {
        switch outcome {
        case .restored:
            self = .restored
        case .notFound:
            self = .noPurchasesFound
        case .failed:
            self = .failed
        }
    }

    func buttonTitle(isRevenueCatConfigured: Bool) -> String {
        guard isRevenueCatConfigured else { return "Restore Unavailable" }

        switch self {
        case .idle:
            return "Restore Purchases"
        case .restoring:
            return "Restoring..."
        case .restored:
            return "Restored"
        case .noPurchasesFound:
            return "Nothing to Restore"
        case .failed:
            return "Restore Failed"
        }
    }

    var statusMessage: String? {
        switch self {
        case .idle, .restoring, .restored:
            return nil
        case .noPurchasesFound:
            return "No purchases found to restore."
        case .failed:
            return "Ascend couldn't restore your purchases. Check your connection and try again."
        }
    }

    func isButtonEnabled(isRevenueCatConfigured: Bool) -> Bool {
        isRevenueCatConfigured && self != .restoring
    }
}
