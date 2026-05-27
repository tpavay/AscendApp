import Foundation
import Testing
@testable import AscendApp

struct ProfileStandingSubtitleFormatterTests {
    @Test
    func tiedFirstUsesLockedGoldCopy() {
        let standing = ProfileStanding(
            timeFrame: .weekly,
            rank: 1,
            value: 42_000,
            leaderValue: 42_000,
            previousRankValue: 39_000,
            totalClimbers: 600,
            tiedForFirst: true
        )

        #expect(ProfileStandingSubtitleFormatter.subtitle(for: standing) == "TIED FOR GOLD")
    }

    @Test
    func rankTwoShowsStepsFromGold() {
        let standing = ProfileStanding(
            timeFrame: .weekly,
            rank: 2,
            value: 39_000,
            leaderValue: 42_000,
            previousRankValue: 42_000,
            totalClimbers: 600,
            tiedForFirst: false
        )

        #expect(ProfileStandingSubtitleFormatter.subtitle(for: standing) == "3,000 STEPS FROM GOLD")
    }

    @Test
    func topHundredUnlocksOnlyAfterPopulationThreshold() {
        let standing = ProfileStanding(
            timeFrame: .weekly,
            rank: 42,
            value: 18_000,
            leaderValue: 42_000,
            previousRankValue: 30_000,
            totalClimbers: 600,
            tiedForFirst: false
        )

        #expect(ProfileStandingSubtitleFormatter.subtitle(for: standing) == "TOP 100 · 12,000 TO TOP 10")
    }

    @Test
    func smallPopulationRankOutsideTopTenShowsChaseTarget() {
        let standing = ProfileStanding(
            timeFrame: .weekly,
            rank: 52,
            value: 1_500,
            leaderValue: 42_000,
            previousRankValue: 9_500,
            totalClimbers: 53,
            tiedForFirst: false
        )

        #expect(ProfileStandingSubtitleFormatter.subtitle(for: standing) == "8,000 STEPS TO TOP 10")
    }

    @Test
    func earnedPercentileBandsOnlyShowForFlexThresholds() {
        let standing = ProfileStanding(
            timeFrame: .weekly,
            rank: 150,
            value: 18_000,
            leaderValue: 90_000,
            previousRankValue: nil,
            totalClimbers: 1_000,
            tiedForFirst: false
        )

        #expect(ProfileStandingSubtitleFormatter.subtitle(for: standing) == "TOP 25% OF CLIMBERS")
    }

    @Test
    func belowTopFiftyShowsTopHundredGoalWhenUnlocked() {
        let standing = ProfileStanding(
            timeFrame: .weekly,
            rank: 600,
            value: 8_000,
            leaderValue: 90_000,
            previousRankValue: nil,
            totalClimbers: 1_000,
            tiedForFirst: false,
            stepsToTopHundred: 22_000,
            stepsToTopFiftyPercent: 12_000
        )

        #expect(ProfileStandingSubtitleFormatter.subtitle(for: standing) == "22,000 STEPS TO TOP 100")
    }
}
