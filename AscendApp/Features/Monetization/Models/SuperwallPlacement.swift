import Foundation

enum SuperwallPlacement: String, CaseIterable, Sendable {
    case appLaunchHardGate = "app_launch_hard_gate"
    case appAccessGate = "app_access_gate"
    /// The founder letter: a hosted screen with no products, registered by the app-access gate
    /// after every paid offer is declined and before the free week starts. Every way of closing it
    /// means the same thing, so the gate never reads a choice out of its dismissal
    /// (`docs/free-week-after-decline.md`).
    case founderLetter = "founder_letter"
}
