import Testing
@testable import AscendApp

/// The pin card's two numbers, named by what they count. Both come from the leaderboard
/// projection Climb Detail already reads: distinct finishers, and every finished attempt.
struct ClimbPreviewCardCountsTests {
    @Test
    func theCardNamesClimbersWhoCompletedAndCompletions() {
        let counts = ClimbCommunityCounts(completedClimbers: 8, completions: 12)
        #expect(ClimbPreviewCardView.countsText(counts) == "8 COMPLETED · 12 COMPLETIONS")
        #expect(ClimbPreviewCardView.countsText(ClimbCommunityCounts(completedClimbers: 1, completions: 1)) == "1 COMPLETED · 1 COMPLETION")
    }

    @Test
    func completionsCanNeverBeFewerThanTheClimbersWhoCompleted() {
        let counts = ClimbCommunityCounts(completedClimbers: 5, completions: 2)
        #expect(counts.completions == 5)
        #expect(ClimbCommunityCounts(completedClimbers: -1, completions: -4) == ClimbCommunityCounts(completedClimbers: 0, completions: 0))
    }
}
