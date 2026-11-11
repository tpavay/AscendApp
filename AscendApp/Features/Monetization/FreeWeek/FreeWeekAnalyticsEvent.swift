import Foundation

/// The free week's four moments. Each carries `flow_version`, so a funnel filtered to the 1.3.0
/// onboarding reads them as the tail of that flow.
enum FreeWeekAnalyticsEvent: TelemetryEvent {
    /// The founder letter reached the screen.
    case letterShown(flowVersion: String)
    /// The server started the week. `letterShown` says whether the climber saw the letter first: the
    /// week is granted either way, because the letter is a courtesy and the access is the promise.
    case granted(flowVersion: String, letterShown: Bool)
    /// A climber whose week is over met the paywall. Once per account per device.
    case expiredGated(flowVersion: String)
    /// Apple completed a purchase while the week was still running.
    case purchasedDuringWeek(flowVersion: String, daysLeft: Int)

    var record: TelemetryRecord {
        switch self {
        case .letterShown(let flowVersion):
            TelemetryRecord(
                name: "free_week_letter_shown",
                parameters: ["flow_version": .string(flowVersion)]
            )
        case .granted(let flowVersion, let letterShown):
            TelemetryRecord(
                name: "free_week_granted",
                parameters: [
                    "flow_version": .string(flowVersion),
                    "letter_shown": .bool(letterShown)
                ]
            )
        case .expiredGated(let flowVersion):
            TelemetryRecord(
                name: "free_week_expired_gated",
                parameters: ["flow_version": .string(flowVersion)]
            )
        case .purchasedDuringWeek(let flowVersion, let daysLeft):
            TelemetryRecord(
                name: "free_week_purchase_completed",
                parameters: [
                    "flow_version": .string(flowVersion),
                    "days_left": .int(daysLeft)
                ]
            )
        }
    }
}
