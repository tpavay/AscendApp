import Foundation

/// Decides every word and number in the completion summary's rank hero.
///
/// The hero has always rendered two different measurements in the same slot. One
/// is the standing the server froze when the attempt published - the climber's
/// position and the size of the finisher field at that instant. The other is a
/// position recomputed against the rows that exist right now. They answer
/// different questions and are expected to disagree: the first finisher of a
/// climb is "1st of 1" forever while that climb keeps collecting finishers, so a
/// climb detail reading "50 completed" is not a contradiction of it.
///
/// Two rules keep that legible:
///
/// 1. Rank and total are resolved together from a single source. A frozen
///    position over a live denominator is a number that was never true.
/// 2. The detail line names the basis whenever a rank is shown, so the figure is
///    never left to be read as a current standing when it is not one.
struct LiveClimbSummaryRankHero: Equatable {
    /// Which population the displayed standing was measured against.
    enum Basis: Equatable {
        /// Frozen by the server when the attempt published. Permanent.
        case atCompletion
        /// Recomputed against the completions published right now.
        case current
    }

    /// One candidate standing, carrying the population it was measured against.
    struct Standing: Equatable {
        let rank: Int
        let total: Int?
        let basis: Basis

        init?(rank: Int?, total: Int?, basis: Basis) {
            guard let rank else { return nil }
            self.rank = rank
            self.total = total
            self.basis = basis
        }
    }

    /// The publish/sync state that drives the unranked copy.
    struct SyncState: Equatable {
        let phase: LiveClimbPublicResultPhase?
        /// Whether this surface is allowed to show "still looking" copy at all.
        let showsPendingRanking: Bool
        /// Whether a leaderboard context exists to rank against.
        let hasRankContext: Bool
        let didFinishRankLoad: Bool

        init(
            phase: LiveClimbPublicResultPhase?,
            showsPendingRanking: Bool,
            hasRankContext: Bool,
            didFinishRankLoad: Bool
        ) {
            self.phase = phase
            self.showsPendingRanking = showsPendingRanking
            self.hasRankContext = hasRankContext
            self.didFinishRankLoad = didFinishRankLoad
        }
    }

    /// Caller-supplied wording for the surfaces that are not a landmark climb.
    struct Copy: Equatable {
        let labelOverride: String?
        let completedDetailOverride: String?
        let unrankedValue: String
        let unrankedDetail: String

        init(
            labelOverride: String? = nil,
            completedDetailOverride: String? = nil,
            unrankedValue: String = "Checking",
            unrankedDetail: String = "LOOKING FOR YOUR RANK"
        ) {
            self.labelOverride = labelOverride
            self.completedDetailOverride = completedDetailOverride
            self.unrankedValue = unrankedValue
            self.unrankedDetail = unrankedDetail
        }
    }

    static let atCompletionDetail = "RANK WHEN YOU FINISHED"
    static let currentDetail = "CURRENT LEADERBOARD RANK"

    let label: String
    let value: String
    let detail: String
    let standing: Standing?

    /// The denominator to render beside the value, or `nil` when there is none to
    /// show. Only ever the total belonging to the standing that produced `value`.
    var total: Int? {
        guard let standing, let total = standing.total, total > 0 else { return nil }
        return total
    }

    /// Builds the hero from the candidate standings in precedence order.
    ///
    /// - Parameters:
    ///   - isClimbContext: Whether this summary belongs to a catalog climb.
    ///   - standings: Candidates most-authoritative first; the first non-`nil`
    ///     entry supplies both the rank and its total.
    static func make(
        isClimbContext: Bool,
        standings: [Standing?],
        sync: SyncState,
        copy: Copy
    ) -> Self {
        let standing = standings.compactMap { $0 }.first

        return Self(
            label: label(isClimbContext: isClimbContext, copy: copy),
            value: value(standing: standing, sync: sync, copy: copy),
            detail: detail(
                standing: standing,
                isClimbContext: isClimbContext,
                sync: sync,
                copy: copy
            ),
            standing: standing
        )
    }

    private static func label(isClimbContext: Bool, copy: Copy) -> String {
        copy.labelOverride ?? (isClimbContext ? "CLIMB RANK" : "GLOBAL RANK")
    }

    private static func value(
        standing: Standing?,
        sync: SyncState,
        copy: Copy
    ) -> String {
        if let standing {
            return standing.rank.rankOrdinalText
        }

        if sync.showsRankUnavailableState {
            return "Unavailable"
        }

        switch sync.phase {
        case .savedOnDevice:
            return "Saved"
        case .syncFailedRetry:
            return "Sync failed"
        case .syncingRanking:
            return "Syncing"
        case .pending, .published, nil:
            if sync.showsPendingRankCopy {
                return "Checking"
            }
            return fallbackUnrankedValue(sync: sync, copy: copy)
        }
    }

    private static func detail(
        standing: Standing?,
        isClimbContext: Bool,
        sync: SyncState,
        copy: Copy
    ) -> String {
        // A shown rank always names its own basis. The caller's completed copy
        // ("LIVE CLIMB COMPLETE", "ROUTINE COMPLETE") describes the session, not
        // the population, so it cannot stand in for that here.
        if let standing {
            switch standing.basis {
            case .atCompletion:
                return atCompletionDetail
            case .current:
                return currentDetail
            }
        }

        if sync.showsRankUnavailableState {
            return "CHECK LEADERBOARD LATER"
        }

        switch sync.phase {
        case .savedOnDevice:
            return "RESULT SAVED ON DEVICE"
        case .syncFailedRetry:
            return "SYNC YOUR RESULT TO RANK"
        case .syncingRanking:
            return "SYNCING RANKING"
        case .pending, .published, nil:
            return fallbackUnrankedDetail(
                isClimbContext: isClimbContext,
                sync: sync,
                copy: copy
            )
        }
    }

    private static func fallbackUnrankedValue(sync: SyncState, copy: Copy) -> String {
        if !sync.hasRankContext, copy.unrankedValue == "Checking" {
            return "Complete"
        }

        return copy.unrankedValue
    }

    private static func fallbackUnrankedDetail(
        isClimbContext: Bool,
        sync: SyncState,
        copy: Copy
    ) -> String {
        if !sync.hasRankContext, copy.unrankedDetail == "LOOKING FOR YOUR RANK" {
            return completedDetail(isClimbContext: isClimbContext, copy: copy)
        }

        return copy.unrankedDetail
    }

    private static func completedDetail(isClimbContext: Bool, copy: Copy) -> String {
        copy.completedDetailOverride ??
            (isClimbContext ? "LIVE CLIMB COMPLETE" : "WORKOUT COMPLETE")
    }
}

extension LiveClimbSummaryRankHero.SyncState {
    var showsPendingRankCopy: Bool {
        showsPendingRanking && hasRankContext && !didFinishRankLoad
    }

    var showsRankUnavailableState: Bool {
        showsPendingRanking && hasRankContext && didFinishRankLoad
    }
}

private extension Int {
    var rankOrdinalText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
