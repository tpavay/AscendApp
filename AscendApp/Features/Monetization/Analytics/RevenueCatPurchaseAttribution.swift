import Foundation

enum RevenueCatPurchaseAttribution: Equatable, Sendable {
    case purchaseStarted(RevenueCatPurchaseAnalyticsContext)
    case unavailableBeforeRevenueCatCall

    var parameters: [String: TelemetryValue] {
        switch self {
        case .purchaseStarted(let context):
            context.parameters
        case .unavailableBeforeRevenueCatCall:
            [:]
        }
    }
}
