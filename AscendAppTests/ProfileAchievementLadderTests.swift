import Foundation
import Testing
@testable import AscendApp

/// The ladder decides what the profile shelf is allowed to claim. Exact placements come from
/// recorded ranks; the banded `profile_stats` counters can never produce one.
struct ProfileAchievementLadderTests {
    @Test
    func placementsCountTheExactRecordedRanks() {
        let ladder = ProfileAchievementLadder(
            records: [
                record(id: "a", type: .weeklyTop1, rank: 1),
                record(id: "b", type: .monthlyTop3, rank: 2),
                record(id: "c", type: .yearlyTop3, rank: 2),
                record(id: "d", type: .weeklyTop3, rank: 3),
                record(id: "e", type: .weeklyTop10, rank: 7)
            ]
        )

        #expect(ladder.placements?.second == 2)
        #expect(ladder.placements?.third == 1)
    }

    @Test
    func placementsIgnoreRecordsWithNoLeaderboardRankBand() {
        let ladder = ProfileAchievementLadder(
            records: [
                record(id: "fa", type: .firstAscent, rank: 2),
                record(id: "second", type: .monthlyTop3, rank: 2)
            ]
        )

        #expect(ladder.placements?.second == 1)
    }

    @Test
    func placementsAreZeroRatherThanAbsentWhenRecordsHoldNoPodiumFinish() {
        let ladder = ProfileAchievementLadder(
            records: [record(id: "a", type: .weeklyTop10, rank: 7)]
        )

        #expect(ladder.placements == .zero)
    }

    @Test
    func bandedCountersProveNoExactPlacement() {
        let ladder = ProfileAchievementLadder(
            bandedCounters: ProfileAchievementCounts(top1: 2, top3: 9, top10: 14, top100: 30)
        )

        #expect(ladder.placements == nil)
        #expect(ladder.records.isEmpty)
        #expect(ladder.counts.top3 == 9)
    }

    @Test
    func recordsStillDriveTheCumulativeBandCounts() {
        let ladder = ProfileAchievementLadder(
            records: [
                record(id: "a", type: .weeklyTop1, rank: 1),
                record(id: "b", type: .monthlyTop3, rank: 2),
                record(id: "c", type: .weeklyTop10, rank: 7)
            ]
        )

        #expect(ladder.counts.top1 == 1)
        #expect(ladder.counts.top10 == 3)
        #expect(ladder.counts.top100 == 3)
    }

    @Test
    func theLadderRendersChampionSecondThirdTopTenTopHundredInOrder() {
        let ladder = ProfileAchievementLadder(
            records: [
                record(id: "a", type: .weeklyTop1, rank: 1),
                record(id: "b", type: .monthlyTop3, rank: 2),
                record(id: "c", type: .weeklyTop3, rank: 3),
                record(id: "d", type: .weeklyTop10, rank: 7),
                record(id: "e", type: .weeklyTop100, rank: 55)
            ]
        )

        let tokens = ProfilePrestigeToken.leaderboardTokens(for: ladder)

        #expect(tokens.map(\.id) == ["top1", "place2", "place3", "top10", "top100"])
        #expect(tokens.map(\.label) == ["CHAMPION", "#2", "#3", "TOP 10", "TOP 100"])
    }

    @Test
    func aPlacementWithNoFinishGetsNoBadge() {
        let ladder = ProfileAchievementLadder(
            records: [
                record(id: "a", type: .weeklyTop1, rank: 1),
                record(id: "b", type: .weeklyTop3, rank: 3)
            ]
        )

        let tokens = ProfilePrestigeToken.leaderboardTokens(for: ladder)

        #expect(tokens.contains { $0.id == "place2" } == false)
        #expect(tokens.contains { $0.id == "place3" })
    }

    @Test
    func theBandedFallbackWithholdsBothPlacementBadges() {
        let ladder = ProfileAchievementLadder(
            bandedCounters: ProfileAchievementCounts(top1: 1, top3: 9, top10: 14, top100: 30)
        )

        let tokens = ProfilePrestigeToken.leaderboardTokens(for: ladder)

        #expect(tokens.map(\.id) == ["top1", "top10", "top100"])
    }

    @Test
    func theRetiredTopThreeBandNeverBecomesABadge() {
        let ladder = ProfileAchievementLadder(
            records: [record(id: "a", type: .monthlyTop3, rank: 2)]
        )

        let tokens = ProfilePrestigeToken.leaderboardTokens(for: ladder)

        #expect(ladder.counts.top3 == 1)
        #expect(tokens.contains { $0.label == "TOP 3" } == false)
    }

    @Test
    func aPlacementBadgeListsOnlyItsOwnRankInHistory() {
        let records = [
            record(id: "a", type: .weeklyTop1, rank: 1),
            record(id: "b", type: .monthlyTop3, rank: 2),
            record(id: "c", type: .weeklyTop3, rank: 3)
        ]

        let secondPlace = records.filter(ProfileAchievementHistoryFilter.placement(2).matches)

        #expect(secondPlace.map(\.id) == ["b"])
    }

    @Test
    func aBandBadgeStillListsEveryFinishInsideIt() {
        let records = [
            record(id: "a", type: .weeklyTop1, rank: 1),
            record(id: "b", type: .monthlyTop3, rank: 2),
            record(id: "c", type: .weeklyTop10, rank: 7),
            record(id: "d", type: .weeklyTop100, rank: 55)
        ]

        let topTen = records.filter(ProfileAchievementHistoryFilter.band(.top10).matches)

        #expect(topTen.map(\.id) == ["a", "b", "c"])
    }

    @Test
    func aFirstAscentIsNeverListedUnderALeaderboardPlacement() {
        let records = [record(id: "fa", type: .firstAscent, rank: 2)]

        #expect(records.filter(ProfileAchievementHistoryFilter.placement(2).matches).isEmpty)
    }

    private func record(
        id: String,
        type: ProfileAchievementType,
        rank: Int?
    ) -> ProfileAchievementRecord {
        ProfileAchievementRecord(
            id: id,
            type: type,
            scope: .global,
            metric: .steps,
            climbId: nil,
            periodKey: nil,
            periodStartAt: nil,
            periodEndAt: nil,
            earnedAt: Date(timeIntervalSince1970: 1_754_000_000),
            rank: rank,
            value: 12_000,
            valueUnit: "steps"
        )
    }
}
