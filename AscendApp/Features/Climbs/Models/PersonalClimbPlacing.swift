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

    /// A first ascent is not "1st of your 1 climbs" - it is the flag. This says
    /// only whether the climber has any earlier completion here to be placed
    /// against.
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
    ///     has recorded on this climb.
    init?(durationSeconds: Int, otherCompletionDurationsSeconds: [Int]) {
        guard durationSeconds > 0 else { return nil }

        let others = otherCompletionDurationsSeconds.filter { $0 > 0 }
        self.init(
            ordinal: 1 + others.filter { $0 < durationSeconds }.count,
            total: others.count + 1
        )
    }
}
