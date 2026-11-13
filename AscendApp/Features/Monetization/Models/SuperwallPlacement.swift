import Foundation

enum SuperwallPlacement: String, CaseIterable, Sendable {
    case appLaunchHardGate = "app_launch_hard_gate"
    case appAccessGate = "app_access_gate"
    /// The founder letter: a hosted screen with no products, registered by the app-access gate
    /// after every paid offer is declined and before the free week starts. Every way of closing it
    /// means the same thing, so the gate never reads a choice out of its dismissal
    /// (`docs/free-week-after-decline.md`).
    case founderLetter = "founder_letter"
    /// Superwall's own decline event, which the dashboard's decline offer campaign is triggered by.
    /// The SDK fires it when the first paywall is closed, so the app never registers it on that
    /// path. It registers it in exactly one situation: a climber force-closed the app on the first
    /// paywall before the offer opened, and the next launch replays what the close would have
    /// opened (`docs/free-week-after-decline.md`, "Force-closing on the first paywall").
    case paywallDecline = "paywall_decline"

    /// The placements whose paywalls Ascend reports itself. The decline offer is not one of them
    /// even when Ascend registers it: it reports through `SuperwallEventRelay` like the same offer
    /// the SDK chains onto the first paywall, so neither route emits a second set of `paywall_*`
    /// events and neither honours a back action the offer does not have.
    init?(reportedByAscend rawValue: String) {
        guard let placement = Self(rawValue: rawValue), placement != .paywallDecline else {
            return nil
        }
        self = placement
    }
}
