import Testing
@testable import AscendApp

struct ResolvedShareStandingTests {
    @Test
    func rankedStandingFormatsTheSettledCopyInputs() throws {
        let standing = try #require(ResolvedShareStanding(rank: 4, totalClimbers: 1_284))

        #expect(standing.ordinalRank == "4th")
        #expect(standing.formattedFieldSize == "1,284")
        #expect(!standing.isFirstAscent)
    }

    /// Last place beat nobody. The card says so rather than rounding the result
    /// up to a percentile the leaderboard does not support.
    @Test
    func lastPlaceReadsZeroPercentInsteadOfAFlatteringFloor() throws {
        let standing = try #require(ResolvedShareStanding(rank: 240, totalClimbers: 240))

        #expect(standing.percentile == 0)
        #expect(!standing.isFirstAscent)
        #expect(standing.formattedFieldSize == "240")
    }

    @Test(arguments: [0, 1, 99])
    func explicitPercentilePreservesBothExtremes(percentile: Int) throws {
        let standing = try #require(
            ResolvedShareStanding(rank: 50, totalClimbers: 100, percentile: percentile)
        )

        #expect(standing.percentile == percentile)
    }

    @Test
    func loneClimberIsFirstAscentInsteadOfOneOfOne() throws {
        let standing = try #require(ResolvedShareStanding(rank: 1, totalClimbers: 1))

        #expect(standing.isFirstAscent)
        #expect(standing.ordinalRank == "1st")
    }
}
