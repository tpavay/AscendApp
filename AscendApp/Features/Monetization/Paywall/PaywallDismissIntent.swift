import Foundation

/// The `Custom action` names Ascend recognises from a Superwall paywall.
///
/// The editor sends an arbitrary string, so this is the one place a string becomes an intent.
/// `CaseIterable` on purpose: the recognised set is derived from here rather than restated in a
/// test, so a control the editor gains cannot be "covered" by a list nobody updated.
enum SuperwallCustomAction: String, CaseIterable {
    /// The paywall's back control, which chains a close action after the custom action.
    case back
    /// The paywall's `DELETE ACCOUNT` control, which chains nothing after the custom action.
    ///
    /// With no close control on the paywall, this is the account-deletion route Guideline
    /// 5.1.1(v) requires for a climber who is locked out and cannot pay.
    case deleteAccount = "delete_account"

    /// Whether Ascend dismisses the paywall itself the moment this action arrives.
    ///
    /// A custom action does not dismiss the paywall and carries no outcome of its own, so every
    /// control has to be dismissed by *somebody*. Two arrangements are possible and they are
    /// mutually exclusive:
    ///
    /// - The paywall chains a close after the custom action and Ascend reads the latched name
    ///   when that dismissal arrives (`back`).
    /// - Ascend owns the dismissal and calls it itself on arrival (`deleteAccount`), the way
    ///   ``HostedPurchaseRecoveryRouting`` already does for a recovered transaction.
    ///
    /// An Ascend-dismissed control must NOT also chain a close in the editor: that close would
    /// race Ascend's own dismissal, and the app would then be handed a dismissal it did not cause.
    var isDismissedByAscend: Bool {
        switch self {
        case .back:
            return false
        case .deleteAccount:
            return true
        }
    }
}

/// What a hosted paywall dismissal meant.
///
/// Superwall reports every user-driven close as the same `PaywallResult.declined` with
/// `PaywallCloseReason.manualClose` - the close message carries no payload at all - so a control
/// that needs to be distinguished cannot be a close action. It fires a *custom* action, and the
/// presenter either latches the name for a close that follows or acts on it directly. This
/// resolves a name into an intent for both paths, so there is one mapping rather than two.
///
/// Deliberately a pure function of the name so the fork is testable without SuperwallKit.
enum PaywallDismissIntent: Equatable {
    /// The climber asked to go back to the onboarding step behind the paywall.
    case back
    /// The climber asked to delete their Ascend account from the paywall.
    case deleteAccount
    /// Anything else: a system dismissal, a webview failure, or a control Ascend does not model.
    case undifferentiated

    static func resolve(latchedActionName: String?) -> Self {
        guard let latchedActionName,
              let action = SuperwallCustomAction(rawValue: latchedActionName) else {
            return .undifferentiated
        }
        return resolve(action)
    }

    static func resolve(_ action: SuperwallCustomAction) -> Self {
        switch action {
        case .back:
            return .back
        case .deleteAccount:
            return .deleteAccount
        }
    }

    var outcome: PaywallPresentationOutcome {
        switch self {
        case .back:
            return .backRequested
        case .deleteAccount:
            return .deleteAccountRequested
        case .undifferentiated:
            return .dismissedWithoutPurchase
        }
    }
}
