import Foundation
import Testing
@testable import AscendApp

struct ProfileAchievementCountsTests {
    @Test
    func topOneCountsCumulativelyThroughAllBands() {
        let records = [
            ProfileAchievementRecord(
                id: "top1",
                type: .weeklyTop1,
                scope: .global,
                metric: .steps,
                climbId: nil,
                periodKey: "2026-W21",
                periodStartAt: nil,
                periodEndAt: nil,
                earnedAt: Date(),
                rank: 1,
                value: 12_000,
                valueUnit: "steps"
            )
        ]

        let counts = ProfileAchievementCounts(records: records)

        #expect(counts.top1 == 1)
        #expect(counts.top3 == 1)
        #expect(counts.top10 == 1)
        #expect(counts.top100 == 1)
    }

    @Test
    func topThreeCountsDoNotIncrementTopOne() {
        let records = [
            ProfileAchievementRecord(
                id: "top3",
                type: .monthlyTop3,
                scope: .global,
                metric: .steps,
                climbId: nil,
                periodKey: "2026-05",
                periodStartAt: nil,
                periodEndAt: nil,
                earnedAt: Date(),
                rank: 3,
                value: 32_000,
                valueUnit: "steps"
            )
        ]

        let counts = ProfileAchievementCounts(records: records)

        #expect(counts.top1 == 0)
        #expect(counts.top3 == 1)
        #expect(counts.top10 == 1)
        #expect(counts.top100 == 1)
    }
}
