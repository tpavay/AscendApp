import Testing
@testable import AscendApp

/// The pin card's one number: distinct climbers who have completed the climb, from
/// the leaderboard projection the board itself reads. Zero is the open First Ascent,
/// said in the app's own First Ascent words.
struct ClimbPreviewCardCompletedClimbersTests {
    @Test(arguments: [
        (0, "First Ascent open"),
        (1, "1 climber completed"),
        (2, "2 climbers completed"),
        (12, "12 climbers completed"),
        (1_204, "1,204 climbers completed"),
    ])
    func theLineCountsClimbersSingularAware(count: Int, expected: String) {
        #expect(ClimbPreviewCardView.completedClimbersText(count) == expected)
    }

    @Test
    func aNegativeCountReadsAsAnOpenFirstAscentRatherThanNonsense() {
        #expect(ClimbPreviewCardView.completedClimbersText(-3) == "First Ascent open")
    }
}
