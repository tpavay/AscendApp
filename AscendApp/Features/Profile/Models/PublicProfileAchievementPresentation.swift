/// What the comparison screen's ACHIEVEMENTS section draws.
///
/// The section is hidden only when the matchup has nothing to compare - neither climber holds a
/// badge either side can answer for. It is deliberately never hidden on the *other* climber's
/// emptiness: a decorated viewer opening a brand-new climber's profile is the normal case on
/// this screen, and their own case is exactly what the comparison is for.
enum PublicProfileAchievementPresentation: Equatable {
    case hidden
    case visible([ProfileAchievementComparisonEntry])

    init(
        viewer: ProfileAchievementLadder,
        other: ProfileAchievementLadder,
        isOtherLoading: Bool
    ) {
        // The row set depends on both sides, so nothing here can be drawn honestly until the
        // other climber's ladder lands. Half a comparison would claim zeroes we have not read.
        guard !isOtherLoading else {
            self = .hidden
            return
        }

        let entries = ProfileAchievementCatalogue.comparisonEntries(
            viewer: ProfileAchievementTally(ladder: viewer),
            other: ProfileAchievementTally(ladder: other)
        )
        self = entries.isEmpty ? .hidden : .visible(entries)
    }
}
