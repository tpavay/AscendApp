import Foundation

struct RevenueCatPurchaseAnalyticsContext: Equatable, Sendable {
    let placement: RevenueCatPurchasePlacement
    let presentationID: String?

    init(placement: String?, presentationID: String?) {
        self.placement = RevenueCatPurchasePlacement(placement)
        self.presentationID = presentationID
    }

    var parameters: [String: TelemetryValue] {
        var parameters: [String: TelemetryValue] = [
            "placement": .string(placement.analyticsValue)
        ]
        if let presentationID {
            parameters["presentation_id"] = .string(presentationID)
        }
        return parameters
    }
}
