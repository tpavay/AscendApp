import Testing
@testable import AscendApp

/// How a finish is worded on every share surface: `TOP 12%` in the top half of a real field, its
/// rank everywhere else, and a first ascent as itself.
struct ShareStandingWordingTests {
    private func rank(_ position: Int, of field: Int) throws -> ShareSheetSubject.Rank {
        try #require(ShareSheetSubject.Rank(position: position, field: field))
    }

    @Test(arguments: [
        (7, 64, "TOP 11%"),
        (1, 10, "TOP 10%"),
        (5, 10, "TOP 50%"),
        (32, 64, "TOP 50%"),
        (457, 914, "TOP 50%"),
        (12_345, 98_765, "TOP 12%"),
        (123_456, 1_234_567, "TOP 10%"),
    ])
    func theTopHalfLeadsWithThePercentage(position: Int, field: Int, headline: String) throws {
        let standing = try rank(position, of: field)
        #expect(standing.leadsWithPercent)
        #expect(standing.headline == headline)
    }

    @Test(arguments: [
        (33, 64, "#33"),
        (458, 914, "#458"),
        (806, 914, "#806"),
        (64, 64, "#64"),
        (987_654, 1_234_567, "#987654"),
    ])
    func theLowerHalfLeadsWithTheRank(position: Int, field: Int, headline: String) throws {
        let standing = try rank(position, of: field)
        #expect(!standing.leadsWithPercent)
        #expect(standing.headline == headline)
    }

    @Test
    func theLineIsExactNotRounded() throws {
        // 458 of 914 is 50.11%, which rounds to 50: it still did not beat half, so it is no TOP 50%.
        #expect(try rank(458, of: 914).topPercent == 50)
        #expect(try !rank(458, of: 914).leadsWithPercent)
    }

    @Test(arguments: [(1, 2), (2, 2), (1, 3), (3, 5), (1, 9)])
    func aFieldTooSmallForAPercentageLeadsWithTheRank(position: Int, field: Int) throws {
        let standing = try rank(position, of: field)
        #expect(!standing.leadsWithPercent)
        #expect(standing.headline == "#\(position)")
        #expect(standing.fieldCaption == "OF \(field) CLIMBERS")
    }

    @Test
    func aFieldOfOneIsAFirstAscentAndSaysNothingSilly() throws {
        let only = try rank(1, of: 1)
        #expect(only.headline == "#1")
        #expect(only.fieldCaption == "FIRST ASCENT")
        #expect(only.beatCaption == nil)
        #expect(only.stickerFooter == "FIRST ASCENT")
    }

    @Test
    func tiedClimbersShareOneWording() throws {
        // Two climbers tied for 7th of 14 hold the same frozen position, so they get the same words.
        #expect(try rank(7, of: 14).headline == rank(7, of: 14).headline)
        #expect(try rank(7, of: 14).headline == "TOP 50%")
    }

    @Test
    func theRankStickerFooterNeverClaimsAPercentageItDidNotEarn() throws {
        #expect(try rank(7, of: 64).stickerFooter == "TOP 11% \u{00B7} BEAT 89%")
        #expect(try rank(806, of: 914).stickerFooter == "BEAT 11%")
    }

    @Test
    func totalsStandingsFollowTheSameRule() throws {
        let top = try #require(ShareTotalsSnapshot.Standing(position: 3, field: 914))
        #expect(top.headline == "TOP 1%")
        #expect(top.stickerFooter == "TOP 1% \u{00B7} BY STEPS")
        let low = try #require(ShareTotalsSnapshot.Standing(position: 806, field: 914))
        #expect(low.headline == "#806")
        #expect(low.stickerFooter == "BY STEPS")
    }
}
