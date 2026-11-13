import Foundation

/// What the `startFreeWeek` callable decided.
enum FreeWeekGrantResponse: Equatable, Sendable {
    /// The week is running. Returned for the first call and for every retry inside the week.
    case granted(FreeWeekGrant)
    /// This account already had its week. Carries the spent week when the server could read it.
    case alreadyUsed(FreeWeekGrant?)
    /// The account holds paid or comped access on the server, so there is nothing to give.
    case paidActive
    /// The rollout is off on the server.
    case disabled
    case unrecognized

    init(payload: [String: Any]?) {
        let grant = Self.grant(from: payload)
        switch payload?["status"] as? String {
        case "granted":
            // A granted answer with no readable window is not an answer the app can route on.
            self = grant.map(Self.granted) ?? .unrecognized
        case "already_used":
            self = .alreadyUsed(grant)
        case "paid_active":
            self = .paidActive
        case "disabled":
            self = .disabled
        default:
            self = .unrecognized
        }
    }

    private static func grant(from payload: [String: Any]?) -> FreeWeekGrant? {
        guard let grantedAtMs = (payload?["grantedAtMs"] as? NSNumber)?.doubleValue,
              let expiresAtMs = (payload?["expiresAtMs"] as? NSNumber)?.doubleValue,
              expiresAtMs > grantedAtMs else {
            return nil
        }

        return FreeWeekGrant(
            grantedAt: Date(timeIntervalSince1970: grantedAtMs / 1_000),
            expiresAt: Date(timeIntervalSince1970: expiresAtMs / 1_000)
        )
    }
}

/// How an attempt to start the week ended, after the one retry the store owns.
enum FreeWeekStartOutcome: Equatable, Sendable {
    case started(FreeWeekGrant)
    case alreadyUsed
    case paidActive
    /// The server refused because the rollout is off, or the call failed twice.
    case failed
}
