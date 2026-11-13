import Foundation
import SuperwallKit

/// Forwards Superwall's own paywall funnel to analytics as `sw_*` events, one rule for every paywall.
///
/// Superwall's Mixpanel integration sends only server-side subscription and revenue events, and it
/// needs the App Store Connect connection on the Superwall side. Which paywall a climber saw, opened
/// and closed exists only inside the SDK, so this is where those events leave it. The SDK's
/// `subscriptionStart` and `freeTrialStart` stay out, so one purchase never reaches Mixpanel under
/// one name from two sources. Properties are an allowlist because the SDK's params also carry
/// `app_transaction_id` and error text.
enum SuperwallEventRelay {
    private static let propertyNames = [
        "paywall_name": "paywall_name",
        "paywall_identifier": "paywall_identifier",
        "presented_by_event_name": "placement",
        "product_id": "product_id",
        "presentation_id": "presentation_id"
    ]

    static func record(
        for event: SuperwallEventObjc,
        params: [String: Any],
        attribution: SuperwallRelayAttribution? = nil
    ) -> TelemetryRecord? {
        guard let name = relayedName(for: event) else { return nil }

        var parameters: [String: TelemetryValue] = [:]
        for (sdkKey, propertyName) in propertyNames {
            if let value = (params[sdkKey] as? String)?.nilIfBlank {
                parameters[propertyName] = .string(value)
            }
        }
        if let attribution {
            parameters["flow_version"] = .string(attribution.flowVersion)
            parameters["origin_placement"] = .string(attribution.originPlacement)
            if let source = attribution.source?.nilIfBlank {
                parameters["source"] = .string(source)
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
        default: nil
        }
    }
}

/// What Ascend knows about the placement it registered, stamped on every `sw_*` event that
/// presentation produces - including a paywall the dashboard chains after it, such as the gift
/// screen after the gate, whose own `placement` names only the trigger that chained it.
///
/// Built only while a v3 onboarding pass is the active flow, so the v1 and non-onboarding events
/// keep exactly the properties they always had.
struct SuperwallRelayAttribution: Equatable, Sendable {
    let flowVersion: String
    /// The placement Ascend registered, such as `app_access_gate`.
    let originPlacement: String
    /// The `source` Ascend registered the placement with, if any.
    let source: String?
}
