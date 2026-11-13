import Foundation

enum SuperwallPlacement: String, CaseIterable, Sendable {
    case appLaunchHardGate = "app_launch_hard_gate"
    case appAccessGate = "app_access_gate"
    /// The founder letter: a hosted screen with no products, registered by the app-access gate
    /// after every paid offer is declined and before the free week starts. Every way of closing it
    /// means the same thing, so the gate never reads a choice out of its dismissal
    /// (`docs/free-week-after-decline.md`).
    case founderLetter = "founder_letter"
    /// The decline offer, registered by the app in exactly one situation: a climber force-closed
    /// the app on the first paywall before the offer opened, and the next launch replays what the
    /// close would have opened (`docs/free-week-after-decline.md`, "Force-closing on the first
    /// paywall"). When the first paywall is closed normally the SDK opens the same offer from its own
    /// `paywall_decline` event, which the SDK refuses to let an app register, so the replay needs a
    /// placement of its own as a second trigger on the decline offer campaign.
    case declineOfferReplay = "decline_offer_replay"

    /// The placements whose paywalls Ascend reports itself. The decline offer is not one of them
    /// even when Ascend registers it: it reports through `SuperwallEventRelay` like the same offer
    /// the SDK chains onto the first paywall, so neither route emits a second set of `paywall_*`
    /// events and neither honours a back action the offer does not have.
    init?(reportedByAscend rawValue: String) {
        guard let placement = Self(rawValue: rawValue), placement != .declineOfferReplay else {
            return nil
        }
        self = placement
    }
}
