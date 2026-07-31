import Foundation

enum AppAccessPaywallPresentationState: CaseIterable, Hashable, Sendable {
    case ready
    case presenting
    case presented
    case readyToRetry
    case failed

    var primaryButtonTitle: String {
        switch self {
        case .ready:
            return "View Plans"
        case .presenting, .presented, .readyToRetry, .failed:
            return "Try Again"
        }
    }

    /// While the paywall is being presented the gate shows a loading surface instead of controls,
    /// so there is never a visible-but-unpressable call to action.
    var showsRecoveryActions: Bool {
        switch self {
        case .presenting, .presented:
            return false
        case .ready, .readyToRetry, .failed:
            return true
        }
    }

    /// Once Superwall's paywall covers the gate, the loading surface underneath is invisible, so its
    /// animation stops rather than redrawing for the whole time the user spends on the paywall.
    var pausesLoadingAnimation: Bool {
        self == .presented
    }

    var statusMessage: String? {
        switch self {
        case .ready:
            return nil
        case .presenting, .presented:
            return nil
        case .readyToRetry:
            return "Access is still locked. Open the paywall to keep climbing."
        case .failed:
            return "Paywall failed to load. Check your connection and try again."
        }
    }

    mutating func beginPresentation() {
        self = .presenting
    }

    mutating func handle(_ outcome: PaywallPresentationOutcome) {
        switch outcome {
        case .presented:
            self = .presented
        case .purchased, .restored:
            self = .ready
        case .dismissedWithoutPurchase, .skipped:
            self = .readyToRetry
        case .failed:
            self = .failed
        }
    }
}
