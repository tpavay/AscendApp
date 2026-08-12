import Foundation

/// The placement is the operator-authored Superwall campaign name, not a value derived from a Swift
/// type, so it is carried through verbatim: a terminal has to join to the `paywall_*` events of the
/// same presentation, and a dashboard campaign Ascend does not register in `SuperwallPlacement` is
/// still a real placement. `unknown` means no placement reached the purchase at all.
enum RevenueCatPurchasePlacement: Equatable, Sendable {
    case presented(String)
    case unknown

    init(_ placement: String?) {
        self = placement?.nilIfBlank.map(Self.presented) ?? .unknown
    }

    var analyticsValue: String {
        switch self {
        case .presented(let placement):
            placement
        case .unknown:
            "unknown"
        }
    }
}
