import Foundation

/// Assigns the top climbers to the three podium pedestals.
///
/// Pedestals are filled in leaderboard order, one climber each. A pedestal's `position`
/// drives only its geometry — the climber standing on it carries their own competition
/// rank, so two climbers tied for gold both read "T1" in gold even though only one
/// pedestal can stand centre.
///
/// Keying pedestals by rank instead would silently drop climbers: competition ranking
/// repeats ranks, so a tie collapses two climbers onto one pedestal and only the last
/// one survives.
struct ModeratedLeaderboardPodiumLayout: Equatable {
    static let slotCount = 3

    struct Slot: Identifiable, Equatable {
        /// 1 is the centre pedestal, 2 the left, 3 the right.
        let position: Int
        let entry: ModeratedLeaderboardEntry?

        var id: Int { position }

        /// An empty pedestal falls back to its position, which is also the next rank
        /// still up for grabs.
        var displayedRank: Int {
            entry?.rank ?? position
        }

        var isTied: Bool {
            entry?.isTied ?? false
        }
    }

    /// Pedestals in display order: left, centre, right.
    let slots: [Slot]

    init(entries: [ModeratedLeaderboardEntry]) {
        let ordered = Self.podiumEntries(from: entries)

        slots = [2, 1, 3].map { position in
            Slot(
                position: position,
                entry: ordered.indices.contains(position - 1) ? ordered[position - 1] : nil
            )
        }
    }

    /// The climbers who stand on the podium — the first three, by position.
    ///
    /// Splitting on `rank <= 3` instead would drop any climber past the third pedestal
    /// who still holds a top-three rank (four climbers tied for 2nd, say) from the
    /// podium and the list at once.
    static func podiumEntries(
        from entries: [ModeratedLeaderboardEntry]
    ) -> [ModeratedLeaderboardEntry] {
        Array(entries.prefix(slotCount))
    }

    /// Everyone below the podium. Together with `podiumEntries` this covers every entry
    /// exactly once.
    static func listEntries(
        from entries: [ModeratedLeaderboardEntry]
    ) -> [ModeratedLeaderboardEntry] {
        Array(entries.dropFirst(slotCount))
    }
}
