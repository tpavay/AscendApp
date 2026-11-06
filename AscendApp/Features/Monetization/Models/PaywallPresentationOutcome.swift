import Foundation

enum PaywallPresentationOutcome: Equatable, Sendable {
    case presented
    /// This paywall closed so the dashboard's next one can open (a decline offer), which reports
    /// back through the same registration. Nothing has ended yet.
    case followOnPaywallOpening
    case purchased
    case restored
    case pendingApproval
    case verificationUnavailable
    case dismissedWithoutPurchase
    /// The climber tapped the paywall's back control, which is a custom action rather than a close.
    case backRequested
    /// The climber tapped the paywall's delete-account control, also a custom action.
    case deleteAccountRequested
    case skipped(reason: String)
    case failed(message: String)
}

extension PaywallPresentationOutcome {
    var isTerminal: Bool {
        switch self {
        case .presented, .followOnPaywallOpening:
            return false
        case .purchased, .restored, .pendingApproval, .verificationUnavailable,
             .dismissedWithoutPurchase, .backRequested, .deleteAccountRequested, .skipped, .failed:
            return true
        }
    }
}
