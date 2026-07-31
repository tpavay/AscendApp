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
/// Three rules keep that legible:
///
/// 1. Rank and total are resolved together from a single source. A frozen
///    position over a live denominator is a number that was never true. This is
///    enforced for every source the hero resolves itself - the frozen snapshot
///    slots, the publish status, the computed rank. For the caller-supplied slot
///    it is a trusted precondition instead: see `Sources.callerSupplied`.
/// 2. The detail line names the basis whenever the hero knows it, so the figure
///    is never left to be read as a current standing when it is not one.
/// 3. The value slot holds a rank, a loading treatment, or nothing at all - never
///    a status word. "Complete" where "21st" goes reads as a load that never
///    finished, so `Value` makes that state unrepresentable rather than relying
///    on every caller to pass wording that avoids it.
/// 4. "No answer yet" is a pending state, never the settled one. `RankResolution`
///    spells out the difference so a card that has not looked yet cannot render
///    the terminal "no rank" wording for the frame before the lookup starts.
///
/// A frozen standing is also permanent: `FrozenCompletionRankStore` keeps the
/// server's answer on device so a reopened summary renders it without a request.
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

    /// What occupies the big slot.
    enum Value: Equatable {
        case rank(Int)
        /// The rank is genuinely in flight. The label stays; only the value loads.
        case loading
        /// No rank, and none is arriving. The detail line carries the reason.
        case unranked
    }

    /// How far the surface has got in resolving a rank for this session.
    ///
    /// The lookup runs after the first frame, so the state it starts in is
    /// `notStarted` - a wait, not an answer. Both pending cases render the loading
    /// treatment; only `settled` may say the session ranks nowhere.
    enum RankResolution: Equatable {
        /// No lookup has run yet.
        case notStarted
        /// A rank read is running right now.
        case resolving
        /// The lookup finished. Whatever the hero shows now is the final answer.
        case settled

        var isPending: Bool { self != .settled }
    }

    /// The publish/sync state that drives the unranked copy.
    struct SyncState: Equatable {
        let phase: LiveClimbPublicResultPhase?
        /// Whether a leaderboard context exists to rank against. Without one there
        /// is no hero at all.
        let hasRankContext: Bool
        let rankResolution: RankResolution

        init(
            phase: LiveClimbPublicResultPhase?,
            hasRankContext: Bool,
            rankResolution: RankResolution
        ) {
            self.phase = phase
            self.hasRankContext = hasRankContext
            self.rankResolution = rankResolution
        }
    }

    /// Caller-supplied wording for the surfaces that are not a landmark climb.
    ///
    /// The label is caller-owned. The detail line is not: wherever the hero can
    /// name the population the rank was measured against, it does. The one
    /// exception is a `.liveSession` standing, whose race window only the caller
    /// can describe.
    struct Copy: Equatable {
        let labelOverride: String?
        /// Stands in for the detail line only under a `.liveSession` standing.
        let completedDetailOverride: String?

        init(
            labelOverride: String? = nil,
            completedDetailOverride: String? = nil
        ) {
            self.labelOverride = labelOverride
            self.completedDetailOverride = completedDetailOverride
        }
    }

    static let atCompletionDetail = "RANK WHEN YOU FINISHED"
    static let freshAtCompletionDetail = "RANK YOU JUST EARNED"
    static let currentDetail = "CURRENT LEADERBOARD RANK"

    let label: String
    let value: Value
    let detail: String
    let standing: Standing?
    let showsRetrySync: Bool

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
    /// Returns `nil` when this session ranks nowhere: the hero does not render,
    /// and the achievement row below already states the outcome.
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
    ) -> Self? {
        guard sync.hasRankContext else { return nil }

        let standing = standings.compactMap { $0 }.first

        return Self(
            label: label(isClimbContext: isClimbContext, copy: copy),
            value: value(standing: standing, sync: sync),
            detail: detail(
                standing: standing,
                isClimbContext: isClimbContext,
                moment: moment,
                sync: sync,
                copy: copy
            ),
            standing: standing,
            showsRetrySync: standing == nil && sync.phase == .syncFailedRetry
        )
    }

    private static func label(isClimbContext: Bool, copy: Copy) -> String {
        copy.labelOverride ?? (isClimbContext ? "CLIMB RANK" : "GLOBAL RANK")
    }

    private static func value(standing: Standing?, sync: SyncState) -> Value {
        if let standing {
            return .rank(standing.rank)
        }

        if sync.rankResolution.isPending || sync.phase == .syncingRanking {
            return .loading
        }

        return .unranked
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

        switch sync.phase {
        case .savedOnDevice:
            return "RESULT SAVED ON DEVICE"
        case .syncFailedRetry:
            return "SYNC YOUR RESULT TO RANK"
        case .syncingRanking:
            return "SYNCING RANKING"
        case .pending, .published, nil:
            return sync.rankResolution.isPending ? "LOOKING FOR YOUR RANK" : "CHECK LEADERBOARD LATER"
        }
    }

    private static func completedDetail(isClimbContext: Bool, copy: Copy) -> String {
        copy.completedDetailOverride ??
            (isClimbContext ? "LIVE CLIMB COMPLETE" : "WORKOUT COMPLETE")
    }
}

extension Int {
    var rankOrdinalText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
