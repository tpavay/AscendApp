import Foundation
import SuperwallKit

/// Forwards Superwall's own paywall funnel to analytics as `sw_*` events, one rule for every paywall.
///
/// Superwall's Mixpanel integration sends only server-side subscription and revenue events, and it
/// needs the App Store Connect connection on the Superwall side. Which paywall a climber saw, opened
/// and closed exists only inside the SDK, so this is where those events leave it. Properties are an
/// allowlist because the SDK's params also carry `app_transaction_id` and error text.
enum SuperwallEventRelay {
    private static let propertyNames = [
        "paywall_name": "paywall_name",
        "paywall_identifier": "paywall_identifier",
        "presented_by_event_name": "placement",
        "product_id": "product_id",
        "presentation_id": "presentation_id"
    ]

    static func record(for event: SuperwallEventObjc, params: [String: Any]) -> TelemetryRecord? {
        guard let name = relayedName(for: event) else { return nil }

        var parameters: [String: TelemetryValue] = [:]
        for (sdkKey, propertyName) in propertyNames {
            if let value = (params[sdkKey] as? String)?.nilIfBlank {
                parameters[propertyName] = .string(value)
            }
        }
        return TelemetryRecord(name: name, parameters: parameters)
    }

    private static func relayedName(for event: SuperwallEventObjc) -> String? {
        switch event {
        case .paywallOpen: "sw_paywall_open"
        case .paywallClose: "sw_paywall_close"
        case .paywallDecline: "sw_paywall_decline"
        case .transactionStart: "sw_transaction_start"
        case .transactionComplete: "sw_transaction_complete"
        case .transactionFail: "sw_transaction_fail"
        case .transactionAbandon: "sw_transaction_abandon"
        case .transactionRestore: "sw_transaction_restore"
        case .subscriptionStart: "sw_subscription_start"
        case .freeTrialStart: "sw_free_trial_start"
        default: nil
        }
    }
}
