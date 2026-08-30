import Foundation

@MainActor
final class SuperwallPresentationAttemptRegistry {
    enum Authority {
        case current
        case cancelledCurrent
        case stale
    }

    private(set) var currentRevision: UInt = 0
    private var cancelledRevisions: Set<UInt> = []

    func begin() -> UInt {
        currentRevision &+= 1
        return currentRevision
    }

    func cancelCurrent() {
        guard currentRevision > 0 else { return }
        cancelledRevisions.insert(currentRevision)
    }

    func isAuthoritative(_ revision: UInt) -> Bool {
        revision == currentRevision && !cancelledRevisions.contains(revision)
    }

    func authority(of revision: UInt) -> Authority {
        guard revision == currentRevision else { return .stale }
        return cancelledRevisions.contains(revision) ? .cancelledCurrent : .current
    }
}

enum SuperwallSkipReasonCategory: String, Sendable {
    case holdout
    case noAudienceMatch = "no_audience_match"
    case placementDisabled = "placement_disabled"
    case userSubscribed = "user_subscribed"
    case other

    static func classify(_ description: String) -> Self {
        let value = description.lowercased()
        if value.contains("holdout") { return .holdout }
        if value.contains("audience") || value.contains("rule") { return .noAudienceMatch }
        if value.contains("disable") || value.contains("config") { return .placementDisabled }
        if value.contains("subscribe") || value.contains("entitle") { return .userSubscribed }
        return .other
    }
}
