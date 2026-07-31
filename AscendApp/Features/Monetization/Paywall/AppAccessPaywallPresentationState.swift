import Foundation

enum AppAccessPaywallPresentationState: Equatable, Sendable {
    case ready
    case presenting
    case readyToRetry
    case failed

    var primaryButtonTitle: String {
        switch self {
        case .ready:
            return "View Plans"
        case .presenting, .readyToRetry, .failed:
            return "Try Again"
        }
    }

    /// While the paywall is being presented the gate shows a loading surface instead of controls,
    /// so there is never a visible-but-unpressable call to action.
    var showsRecoveryActions: Bool {
        self != .presenting
    }

    var statusMessage: String? {
        switch self {
        case .ready:
            return nil
        case .presenting:
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
            self = .presenting
        case .purchased, .restored:
            self = .ready
        case .dismissedWithoutPurchase, .skipped:
            self = .readyToRetry
        case .failed:
            self = .failed
        }
    }
}
