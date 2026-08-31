import Foundation

/// The names Ascend recognises from a Superwall paywall's `Custom action` click behaviour.
///
/// The editor sends an arbitrary string, so this is the one place a string becomes an intent.
enum SuperwallCustomAction {
    /// Set on the paywall's back control, chained ahead of a `close` action.
    static let back = "back"
}

/// What a hosted paywall dismissal meant.
///
/// Superwall reports every user-driven close as the same `PaywallResult.declined` with
/// `PaywallCloseReason.manualClose` - the close message carries no payload at all - so a control
/// that needs to be distinguished cannot be a close action. It fires a *custom* action first, and
/// the presenter latches the name. This resolves that latch into an intent.
///
/// Deliberately a pure function of the latched name so the fork is testable without SuperwallKit.
enum PaywallDismissIntent: Equatable {
    /// The climber asked to go back to the onboarding step behind the paywall.
    case back
    /// Anything else: a system dismissal, a webview failure, or a control Ascend does not model.
    case undifferentiated

    static func resolve(latchedActionName: String?) -> Self {
        switch latchedActionName {
        case SuperwallCustomAction.back:
            return .back
        default:
            return .undifferentiated
        }
    }

    var outcome: PaywallPresentationOutcome {
        switch self {
        case .back:
            return .backRequested
        case .undifferentiated:
            return .dismissedWithoutPurchase
        }
    }
}
