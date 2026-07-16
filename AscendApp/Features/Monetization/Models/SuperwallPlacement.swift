import Foundation

enum SuperwallPlacement: String, CaseIterable, Sendable {
    case onboardingPaywall = "onboarding_paywall"
    case appLaunchHardGate = "app_launch_hard_gate"
    case appAccessGate = "app_access_gate"
}
