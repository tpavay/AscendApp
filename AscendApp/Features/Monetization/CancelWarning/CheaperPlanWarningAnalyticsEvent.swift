import Foundation

/// The cheaper-plan heads-up's three moments. Each carries the rate the climber holds and how much
/// cheaper it is, so the funnel reads which rates keep people and which do not.
enum CheaperPlanWarningAnalyticsEvent: TelemetryEvent {
    /// The warning reached the screen.
    case shown(CheaperPlanWarning)
    /// The climber chose `Keep my plan` and stayed.
    case keepTapped(CheaperPlanWarning)
    /// The climber chose `Continue to cancel` and moved on to Apple's cancellation sheet.
    case continueTapped(CheaperPlanWarning)

    var record: TelemetryRecord {
        switch self {
        case .shown(let warning):
            TelemetryRecord(name: "cheaper_plan_warning_shown", parameters: Self.parameters(warning))
        case .keepTapped(let warning):
            TelemetryRecord(name: "cheaper_plan_warning_keep_tapped", parameters: Self.parameters(warning))
        case .continueTapped(let warning):
            TelemetryRecord(name: "cheaper_plan_warning_continue_tapped", parameters: Self.parameters(warning))
        }
    }

    private static func parameters(_ warning: CheaperPlanWarning) -> [String: TelemetryValue] {
        [
            "product_id": .string(warning.heldRate.productID),
            "rate": .double(NSDecimalNumber(decimal: warning.heldRate.price).doubleValue),
            "currency": .string(warning.heldRate.currencyCode),
            "period": .string(warning.heldRate.period.phrase),
            "standard_rate": .double(NSDecimalNumber(decimal: warning.standardRate.price).doubleValue),
            "percent_cheaper": .int(warning.percentCheaper),
            "is_free_trial": .bool(warning.isInFreeTrial),
            "surface": .string("settings")
        ]
    }
}
