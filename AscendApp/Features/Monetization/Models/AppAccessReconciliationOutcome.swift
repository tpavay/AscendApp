import Foundation

/// What the server did with a reconciliation request.
///
/// Only `active` and `inactive` mean the server actually re-derived access from RevenueCat.
/// `throttled` is a refusal, not an answer, so it must never satisfy the client's own spacing.
enum AppAccessReconciliationOutcome: Sendable {
    case active
    case inactive
    case throttled
    case unrecognized

    var didDeriveAccess: Bool {
        switch self {
        case .active, .inactive:
            return true
        case .throttled, .unrecognized:
            return false
        }
    }

    init(status: String?) {
        switch status {
        case "active":
            self = .active
        case "inactive":
            self = .inactive
        case "throttled":
            self = .throttled
        default:
            self = .unrecognized
        }
    }
}
