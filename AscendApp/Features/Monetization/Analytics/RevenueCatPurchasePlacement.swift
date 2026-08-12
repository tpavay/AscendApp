import Foundation

enum RevenueCatPurchasePlacement: Equatable, Sendable {
    case known(SuperwallPlacement)
    case unknown

    init(_ placement: SuperwallPlacement?) {
        switch placement {
        case .onboardingPaywall:
            self = .known(.onboardingPaywall)
        case .appLaunchHardGate:
            self = .known(.appLaunchHardGate)
        case .appAccessGate:
            self = .known(.appAccessGate)
        case nil:
            self = .unknown
        }
    }

    var analyticsValue: String {
        switch self {
        case .known(let placement):
            placement.rawValue
        case .unknown:
            "unknown"
        }
    }
}
