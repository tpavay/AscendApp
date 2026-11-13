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
    case placementNotFound = "placement_not_found"
    case other

    /// Superwall chose not to show this climber the paywall, as opposed to having no campaign that
    /// could show it to anybody.
    var isDeliberate: Bool {
        switch self {
        case .holdout, .noAudienceMatch, .userSubscribed: true
        case .placementDisabled, .placementNotFound, .other: false
        }
    }

    static func classify(_ description: String) -> Self {
        let value = description.lowercased()
        if value.contains("not part of a campaign") || value.contains("not found") { return .placementNotFound }
        if value.contains("holdout") { return .holdout }
        if value.contains("audience") || value.contains("rule") { return .noAudienceMatch }
        if value.contains("disable") || value.contains("config") { return .placementDisabled }
        if value.contains("subscribe") || value.contains("entitle") { return .userSubscribed }
        return .other
    }
}
