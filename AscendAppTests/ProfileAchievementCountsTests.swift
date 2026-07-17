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

    @Test
    func statsDocumentReadsRenamedFinishCounters() {
        let counts = ProfileAchievementCounts(statsDocument: [
            "top_1_finishes": 4,
            "top_3_finishes": 6,
            "top_10_finishes": 8,
            "top_100_finishes": 10
        ])

        #expect(counts.top1 == 4)
        #expect(counts.top3 == 6)
        #expect(counts.top10 == 8)
        #expect(counts.top100 == 10)
    }

    @Test
    func statsDocumentFallsBackToLegacyWeeksCounters() {
        let counts = ProfileAchievementCounts(statsDocument: [
            "top_1_weeks": 1,
            "top_3_weeks": 2,
            "top_10_weeks": 3,
            "top_100_weeks": 4
        ])

        #expect(counts.top1 == 1)
        #expect(counts.top3 == 2)
        #expect(counts.top10 == 3)
        #expect(counts.top100 == 4)
    }

    @Test
    func statsDocumentPrefersRenamedCountersOverLegacyWeeks() {
        let counts = ProfileAchievementCounts(statsDocument: [
            "top_1_finishes": 4,
            "top_3_finishes": 6,
            "top_10_finishes": 8,
            "top_100_finishes": 10,
            "top_1_weeks": 1,
            "top_3_weeks": 2,
            "top_10_weeks": 3,
            "top_100_weeks": 4
        ])

        #expect(counts.top1 == 4)
        #expect(counts.top3 == 6)
        #expect(counts.top10 == 8)
        #expect(counts.top100 == 10)
    }

    @Test
    func statsDocumentWithoutCountersIsZero() {
        let counts = ProfileAchievementCounts(statsDocument: ["total_climbs": 12])

        #expect(counts == .zero)
    }
}
