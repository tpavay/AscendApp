import Foundation

/// Where one completion sits among the climber's own completions of the same climb.
///
/// This is deliberately not a leaderboard rank. Its field is the climber's own
/// history on one tower, which is why it responds to performance and can fall -
/// the thing "1st of 1 CLIMBER" could never do. A slower repeat drops to `2nd`;
/// a faster one climbs.
///
/// It also collapses the personal-best state into itself: **1st of your own
/// climbs *is* a personal best**, so no separate personal-best hero exists to
/// build or keep in sync.
///
/// Ties do not push a climber down: two attempts at the same duration share the
/// placing, the way standard competition ranking treats a dead heat.
struct PersonalClimbPlacing: Equatable, Sendable {
    /// 1 for the climber's fastest completion of this climb.
    let ordinal: Int
    /// Every completion the climber has recorded on this climb, this one included.
    let total: Int

    /// Whether the climber has any other completion here to be placed against.
    ///
    /// Deliberately NOT the First Ascent test: this stops being true the day the
    /// climber comes back, and the gold flag is permanent.
    /// `PersonalClimbCompletionHistory.claimsFirstAscent` owns that question.
    var isFirstCompletionHere: Bool { total == 1 }

    /// The label that sits beneath the finish-card ordinal, in neutral secondary
    /// white. "Here" is deliberately absent: the climb's name is already in the
    /// card header.
    var fieldLabel: String {
        "OF YOUR \(total.formatted()) \(total == 1 ? "CLIMB" : "CLIMBS")"
    }

    /// The same fact stated in one line, for the achievement row it drops to
    /// whenever a real field of climbers takes the hero instead.
    var achievementTitle: String {
        "\(ordinal.rankOrdinalText.uppercased()) \(fieldLabel)"
    }

    init(ordinal: Int, total: Int) {
        self.total = max(total, 1)
        self.ordinal = min(max(ordinal, 1), self.total)
    }

    /// Places one completion among the climber's other completions of the same
    /// climb.
    ///
    /// The other completions are passed with this one already excluded, so the
    /// caller owns the "is this attempt in the list" question and the arithmetic
    /// here cannot double-count or drop the attempt being placed.
    ///
    /// - Parameters:
    ///   - durationSeconds: This completion's duration.
    ///   - otherCompletionDurationsSeconds: Every *other* completion the climber
    ///     has recorded on this climb. Passing a list is passing complete
    ///     evidence: it is the whole history, so the count and the order both
    ///     come from it. Unmeasured rows are dropped from both rather than
    ///     counted as impossibly fast runs ahead of the climber.
    init?(durationSeconds: Int, otherCompletionDurationsSeconds: [Int]) {
        let measured = otherCompletionDurationsSeconds.filter { $0 > 0 }
        self.init(
            durationSeconds: durationSeconds,
            otherCompletions: PersonalClimbCompletionHistory(
                otherCompletionsCount: measured.count,
                otherCompletionDurationsSeconds: measured,
                durationEvidence: .complete,
                isEarliestCompletionHere: false,
                globalCompletionOrder: nil
            )
        )
    }

    /// Places one completion against the history this device can actually
    /// account for.
    ///
    /// The denominator and the ordinal have to answer to the same evidence. When
    /// they did not, a restored install stated the count the server projection
    /// knew while ordering only the one duration it had kept, so a climber's
    /// slowest run ever was announced as `2ND OF YOUR 7 CLIMBS` - the flattering
    /// ordinal that cannot fall, which is the whole defect this type exists to
    /// delete.
    ///
    /// Under `.partial` evidence only the two ends are decidable, and the
    /// projection's best duration decides both. At or inside it, first is
    /// *proven* and is stated - first of your own climbs is the personal-best
    /// state, and withholding it would be the opposite error. Past it, at least
    /// one completion is known to be faster and the position among the rest is
    /// unknowable, so the placing takes last: the one number the evidence can
    /// never contradict, and never a middle one it cannot support.
    init?(durationSeconds: Int, otherCompletions: PersonalClimbCompletionHistory) {
        guard durationSeconds > 0 else { return nil }

        let others = otherCompletions.otherCompletionDurationsSeconds.filter { $0 > 0 }
        let total = max(otherCompletions.otherCompletionsCount, others.count) + 1

        switch otherCompletions.durationEvidence {
        case .complete:
            self.init(
                ordinal: 1 + others.filter { $0 < durationSeconds }.count,
                total: total
            )
        case .partial:
            let isProvablyFastest = !others.isEmpty && others.allSatisfy { $0 >= durationSeconds }
            self.init(ordinal: isProvablyFastest ? 1 : total, total: total)
        }
    }
}
