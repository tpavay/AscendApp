import Foundation

enum AppAccessRestoreState: Equatable, Sendable {
    case idle
    case restoring
    case restored
    case failed

    func buttonTitle(isRevenueCatConfigured: Bool) -> String {
        guard isRevenueCatConfigured else { return "Restore Unavailable" }

        switch self {
        case .idle:
            return "Restore Purchases"
        case .restoring:
            return "Restoring..."
        case .restored:
            return "Restored"
        case .failed:
            return "Restore Failed"
        }
    }

    func isButtonEnabled(isRevenueCatConfigured: Bool) -> Bool {
        isRevenueCatConfigured && self != .restoring
    }
}
