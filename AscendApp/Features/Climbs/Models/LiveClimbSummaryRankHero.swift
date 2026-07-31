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
///    position over a live denominator is a number that was never true. This is
///    enforced for every source the hero resolves itself - the frozen snapshot
///    slots, the publish status, the computed rank. For the caller-supplied slot
///    it is a trusted precondition instead: see `Sources.callerSupplied`.
/// 2. The detail line names the basis whenever the hero knows it, so the figure
///    is never left to be read as a current standing when it is not one.
struct LiveClimbSummaryRankHero: Equatable {
    /// Which population the displayed standing was measured against.
    enum Basis: Equatable {
        /// Frozen by the server when the attempt published. Permanent.
        case atCompletion
        /// Recomputed against the completions published right now.
        case current
        /// Reported by the caller's own session. Its population is the session's
        /// race window, which this type cannot characterise, so the copy states
        /// the session finished rather than claiming a leaderboard basis.
        case liveSession
    }

    /// Whether this summary *is* the post-session moment or a look back at a
    /// saved one. Only changes the tense of the frozen-basis copy.
    enum Moment: Equatable {
        case freshCompletion
        case retrospective
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

        init?(reading: Reading, basis: Basis) {
            self.init(rank: reading.rank, total: reading.total, basis: basis)
        }
    }

    /// One rank and its denominator exactly as a single source reported them.
    /// They travel together so a frozen position can never end up over a live
    /// field size.
    struct Reading: Equatable {
        let rank: Int?
        let total: Int?

        static let none = Reading(rank: nil, total: nil)

        init(rank: Int?, total: Int?) {
            self.rank = rank
            self.total = total
        }
    }

    /// Every source a completion summary can draw a standing from.
    struct Sources: Equatable {
        /// Handed in by the presenting surface, already carrying its basis. Only
        /// that surface knows which population it measured: a live session
        /// reports its own race window, a saved-workout screen reports a rank it
        /// just recomputed. This type must never guess between them.
        ///
        /// The hero trusts this pair; it cannot verify that the rank and the
        /// total were drawn from one population, so keeping them coherent is the
        /// caller's responsibility. One caller does not today:
        /// `LiveClimbSessionViewModel.completionLeaderboardRank` is a
        /// bucket-windowed race position while its `completionLeaderboardTotal`
        /// can fall back to `leaderboardSummary.completedCount`, so a Just Climb
        /// session can hand over a mismatched pair. Settling the right
        /// population for those surfaces is a separate, filed piece of work.
        let callerSupplied: Standing?
        /// The frozen snapshot mirrored onto the publish sync status.
        let syncedSnapshot: Reading
        /// The frozen position the publish status recorded.
        let publishStatus: Reading
        /// The frozen snapshot fetched straight from the leaderboard service.
        let fetchedSnapshot: Reading
        /// A position recomputed against the rows that exist right now.
        let computed: Reading

        init(
            callerSupplied: Standing? = nil,
            syncedSnapshot: Reading = .none,
            publishStatus: Reading = .none,
            fetchedSnapshot: Reading = .none,
            computed: Reading = .none
        ) {
            self.callerSupplied = callerSupplied
            self.syncedSnapshot = syncedSnapshot
            self.publishStatus = publishStatus
            self.fetchedSnapshot = fetchedSnapshot
            self.computed = computed
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

    /// Caller-supplied wording. Every field is optional; `nil` means "use the
    /// wording this context calls for".
    struct Copy: Equatable {
        let labelOverride: String?
        let completedDetailOverride: String?
        let unrankedValue: String?
        let unrankedDetail: String?

        init(
            labelOverride: String? = nil,
            completedDetailOverride: String? = nil,
            unrankedValue: String? = nil,
            unrankedDetail: String? = nil
        ) {
            self.labelOverride = labelOverride
            self.completedDetailOverride = completedDetailOverride
            self.unrankedValue = unrankedValue
            self.unrankedDetail = unrankedDetail
        }
    }

    static let atCompletionDetail = "RANK WHEN YOU FINISHED"
    static let freshAtCompletionDetail = "RANK YOU JUST EARNED"
    static let currentDetail = "CURRENT LEADERBOARD RANK"
    static let pendingRankValue = "Checking"
    static let pendingRankDetail = "LOOKING FOR YOUR RANK"

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

    /// The candidate standings a surface offers, most authoritative first.
    ///
    /// A landmark climb prefers the server's immutable frozen sources: that is the
    /// standing the climber earned, and it is what the share card and the public
    /// result assert. Everything else falls back to a rank recomputed against
    /// today's rows, which is a different measurement and says so.
    static func standings(isClimbContext: Bool, sources: Sources) -> [Standing?] {
        guard isClimbContext else {
            return [
                sources.callerSupplied,
                Standing(reading: sources.fetchedSnapshot, basis: .atCompletion),
                Standing(reading: sources.computed, basis: .current)
            ]
        }

        return [
            Standing(reading: sources.syncedSnapshot, basis: .atCompletion),
            Standing(reading: sources.publishStatus, basis: .atCompletion),
            Standing(reading: sources.fetchedSnapshot, basis: .atCompletion),
            Standing(reading: sources.computed, basis: .current)
        ]
    }

    /// Builds the hero from the candidate standings in precedence order.
    ///
    /// - Parameters:
    ///   - isClimbContext: Whether this summary belongs to a catalog climb.
    ///   - moment: Whether this summary is the post-session moment itself.
    ///   - standings: Candidates most-authoritative first; the first non-`nil`
    ///     entry supplies both the rank and its total.
    static func make(
        isClimbContext: Bool,
        moment: Moment = .retrospective,
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
                moment: moment,
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
                return pendingRankValue
            }
            return copy.unrankedValue ?? "Complete"
        }
    }

    private static func detail(
        standing: Standing?,
        isClimbContext: Bool,
        moment: Moment,
        sync: SyncState,
        copy: Copy
    ) -> String {
        // A standing whose population this type knows always names it. The
        // caller's completed copy ("LIVE CLIMB COMPLETE", "ROUTINE COMPLETE")
        // describes the session, not the population, so it only stands where the
        // population is the caller's own race window.
        if let standing {
            switch standing.basis {
            case .atCompletion:
                return moment == .freshCompletion ? freshAtCompletionDetail : atCompletionDetail
            case .current:
                return currentDetail
            case .liveSession:
                return completedDetail(isClimbContext: isClimbContext, copy: copy)
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
            return copy.unrankedDetail ?? defaultUnrankedDetail(
                isClimbContext: isClimbContext,
                sync: sync,
                copy: copy
            )
        }
    }

    private static func defaultUnrankedDetail(
        isClimbContext: Bool,
        sync: SyncState,
        copy: Copy
    ) -> String {
        guard sync.tracksRanking else {
            return completedDetail(isClimbContext: isClimbContext, copy: copy)
        }

        return pendingRankDetail
    }

    private static func completedDetail(isClimbContext: Bool, copy: Copy) -> String {
        copy.completedDetailOverride ??
            (isClimbContext ? "LIVE CLIMB COMPLETE" : "WORKOUT COMPLETE")
    }
}

extension LiveClimbSummaryRankHero.SyncState {
    /// Whether this surface both has a population to rank against and reports its
    /// progress toward that ranking.
    var tracksRanking: Bool {
        showsPendingRanking && hasRankContext
    }

    var showsPendingRankCopy: Bool {
        tracksRanking && !didFinishRankLoad
    }

    var showsRankUnavailableState: Bool {
        tracksRanking && didFinishRankLoad
    }
}

private extension Int {
    var rankOrdinalText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
