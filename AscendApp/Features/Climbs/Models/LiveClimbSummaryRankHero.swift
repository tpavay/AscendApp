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
/// Four rules keep that legible:
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
    ///
    /// One rule governs the choice, locked with the captain on 2026-09-01
    /// (`rank-when-alone`, `solo-repeat-finish-card`, `rival-repeat-finish-card`):
    ///
    /// > The leaderboard rank takes the hero whenever a real field exists. When
    /// > the climber is the only one on the tower, the hero states their placing
    /// > among their own climbs. When both are true the leaderboard rank leads and
    /// > the personal placing drops to the achievement row.
    ///
    /// `1st of 1 CLIMBER` is therefore unrepresentable. It was invariant across
    /// every possible performance - 8:12, 9:40 and 14:00 all produced it - so on a
    /// slower repeat it congratulated the climber for the run that had just beaten
    /// them.
    enum Value: Equatable {
        /// A standing over a real field of other climbers.
        case rank(Int)
        /// Where this run placed among the climber's own climbs of this tower.
        /// Only ever shown where no field of other climbers exists to rank
        /// against - and it can fall, which is the entire point.
        case personalPlacing(PersonalClimbPlacing)
        /// This completion took the tower's First Ascent: the climber's first
        /// finish here, with nobody else on the board. Permanent and
        /// unreclaimable, which is why it outranks any ordinal - and why it is
        /// resolved from facts that never move
        /// (`PersonalClimbCompletionHistory.claimsFirstAscent`) rather than from
        /// a count of the climber's climbs, which grows.
        case firstAscent
        /// The rank is genuinely in flight. The label stays; only the value loads.
        case loading
        /// No rank, and none is arriving. The detail line carries the reason.
        case unranked
    }

    /// How the detail line beneath the value is painted.
    ///
    /// The ordinal is the accent lime in every case; the label beneath it is the
    /// neutral secondary white, because the label's own words already say whose
    /// field is being counted. The one exception is the First Ascent claim, which
    /// is the gold prestige token.
    enum DetailEmphasis: Equatable {
        case neutral
        case prestige
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
    /// The label is caller-owned and exists only for a surface that ranks on a
    /// board of its own - a routine names it, an ordinary leaderboard standing
    /// has nothing to add over the field line. The detail line is not
    /// caller-owned: wherever the hero can name the population the rank was
    /// measured against, it does. The one exception is a `.liveSession`
    /// standing, whose race window only the caller can describe.
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
    /// The whole First Ascent card. No sentence, no date, no dare, no rank -
    /// the gold flag and this claim, and nothing else (`first-ascent-line-copy`).
    static let firstAscentDetail = "FIRST ASCENT CLAIMED"

    /// Names the board this standing sits on, for the surfaces that rank on one
    /// of their own. Nil wherever the field line already says everything true.
    let label: String?
    let value: Value
    let detail: String
    let standing: Standing?
    let showsRetrySync: Bool

    /// Derived from `value` rather than stored beside it, so the pair cannot be
    /// set inconsistently: the gold prestige token belongs to the First Ascent
    /// claim and to nothing else.
    var detailEmphasis: DetailEmphasis {
        value == .firstAscent ? .prestige : .neutral
    }

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
    ///   - personalPlacing: Where this completion sits among the climber's own
    ///     completions of the same climb. Only consulted on a climb, and only
    ///     where the standing counts a field of one.
    ///   - claimsFirstAscent: Whether this completion is the one that took the
    ///     tower's First Ascent. See `Value.firstAscent`.
    static func make(
        isClimbContext: Bool,
        moment: Moment = .retrospective,
        standings: [Standing?],
        personalPlacing: PersonalClimbPlacing? = nil,
        claimsFirstAscent: Bool = false,
        sync: SyncState,
        copy: Copy
    ) -> Self? {
        guard sync.hasRankContext else { return nil }

        let standing = standings.compactMap { $0 }.first
        let value = value(
            standing: standing,
            personalPlacing: personalPlacing,
            claimsFirstAscent: claimsFirstAscent,
            isClimbContext: isClimbContext,
            sync: sync
        )

        return Self(
            label: copy.labelOverride,
            value: value,
            detail: detail(
                value: value,
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

    /// Whether a standing counted a field the climber was alone in.
    ///
    /// Only a positively-known field of one qualifies. A standing with no
    /// denominator says nothing about how many climbers finished, so it keeps its
    /// rank rather than being demoted on a guess.
    private static func countsAFieldOfOne(_ standing: Standing) -> Bool {
        standing.total == 1
    }

    private static func value(
        standing: Standing?,
        personalPlacing: PersonalClimbPlacing?,
        claimsFirstAscent: Bool,
        isClimbContext: Bool,
        sync: SyncState
    ) -> Value {
        if let standing {
            guard isClimbContext, countsAFieldOfOne(standing) else {
                return .rank(standing.rank)
            }

            // Alone on the tower. A rank over a field of one cannot fall, so it
            // is never shown - not as "1st of 1 CLIMBER", not relabelled.
            //
            // The claim is asked for first and never derived from the placing:
            // a First Ascent is permanent, while "this is my only climb here"
            // stops being true the day the climber comes back, which retired the
            // gold flag from a summary that had already earned it.
            if claimsFirstAscent {
                return .firstAscent
            }

            if let personalPlacing {
                return .personalPlacing(personalPlacing)
            }

            // The climber's own history has not been read yet. Wait for it rather
            // than falling back to the number this whole rule exists to remove.
            return sync.rankResolution.isPending ? .loading : .unranked
        }

        if sync.rankResolution.isPending || sync.phase == .syncingRanking {
            return .loading
        }

        return .unranked
    }

    private static func detail(
        value: Value,
        standing: Standing?,
        isClimbContext: Bool,
        moment: Moment,
        sync: SyncState,
        copy: Copy
    ) -> String {
        switch value {
        case .firstAscent:
            return firstAscentDetail
        case .personalPlacing(let placing):
            // Names whose field this ordinal counts, so it can never be read as a
            // leaderboard rank. "Here" is dropped: the climb's name is already in
            // the card header.
            return placing.fieldLabel
        case .rank, .loading, .unranked:
            break
        }

        // A standing whose population this type knows always names it. The
        // caller's completed copy ("LIVE CLIMB COMPLETE", "ROUTINE COMPLETE")
        // describes the session, not the population, so it only stands where the
        // population is the caller's own race window.
        if let standing, case .rank = value {
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
