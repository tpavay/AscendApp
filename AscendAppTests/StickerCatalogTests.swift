import Foundation
import Testing
@testable import AscendApp

struct StickerCatalogTests {
    private static let climbOrder: [StickerKind] = [
        .stack, .strip, .list, .line, .personalRecord, .heartRate, .ticket, .pace,
        .splitsChart, .fastestSplit, .climbBellCurve, .climbRank
    ]

    private static let totalsOrder: [StickerKind] = [
        .calendar, .weeklySteps, .averagePace, .stepsAndTime, .floorsAndTime, .floors,
        .climbsAndDots, .stepsAndClimbs, .weeklyRank, .monthlyRank, .yearlyRank, .rankTrio,
        .weeklyBellCurve, .monthlyBellCurve, .yearlyBellCurve
    ]

    // MARK: Kinds

    @Test
    func everyKindBelongsToExactlyOneSetInTheDesignedOrder() {
        #expect(StickerKind.allCases.filter { !$0.isTotals } == Self.climbOrder)
        #expect(StickerKind.allCases.filter(\.isTotals) == Self.totalsOrder)
    }

    @Test
    func theAccessibilityLabelNamesTheStickerAndItsGestures() {
        #expect(StickerKind.stack.accessibilityLabel == "Stack sticker. Tap to copy, hold to save")
        #expect(StickerKind.personalRecord.title == "PR ring")
        for kind in StickerKind.allCases {
            #expect(kind.accessibilityLabel.hasSuffix("sticker. Tap to copy, hold to save"))
        }
    }

    // MARK: This climb

    @Test
    func aFullyPopulatedClimbOffersEverySticker() {
        let subject = ShareSheetSubject.fixture(bestEfforts: [ShareSheetSubject.effort("steps60", rank: 2)])
        #expect(StickerCatalog.climbStickers(for: subject) == Self.climbOrder)
    }

    @Test
    func theAlwaysOnClimbStickersSurviveAnEmptyClimb() {
        let subject = ShareSheetSubject.fixture(averageHeartRate: nil, rank: nil, splits: [])
        #expect(
            StickerCatalog.climbStickers(for: subject)
                == [.stack, .strip, .list, .line, .ticket, .pace]
        )
    }

    @Test
    func theRecordRingNeedsABestEffort() {
        let without = StickerCatalog.climbStickers(for: .fixture(bestEfforts: []))
        let with = StickerCatalog.climbStickers(for: .fixture(bestEfforts: [ShareSheetSubject.effort("steps60")]))
        #expect(!without.contains(.personalRecord))
        #expect(with.contains(.personalRecord))
    }

    @Test
    func heartRateNeedsAnAverageAndAtLeastTwoTracePoints() {
        let populated = ShareSheetSubject.fixture()
        #expect(StickerCatalog.climbStickers(for: populated).contains(.heartRate))

        let noHeartRate = ShareSheetSubject.fixture(averageHeartRate: nil)
        #expect(!StickerCatalog.climbStickers(for: noHeartRate).contains(.heartRate))

        let onePoint = ShareSheetSubject(
            kind: populated.kind,
            title: populated.title,
            label: populated.label,
            dateText: populated.dateText,
            stepsText: populated.stepsText,
            durationText: populated.durationText,
            stepsPerMinuteText: populated.stepsPerMinuteText,
            floorsText: populated.floorsText,
            averageHeartRate: populated.averageHeartRate,
            maxHeartRate: populated.maxHeartRate,
            heartRateTrace: [128],
            rank: populated.rank,
            splits: populated.splits,
            bestEfforts: populated.bestEfforts,
            landmark: populated.landmark
        )
        #expect(!StickerCatalog.climbStickers(for: onePoint).contains(.heartRate))
    }

    @Test
    func theSplitStickersNeedAtLeastTwoSplits() {
        let one = Array(ShareSheetSubject.sampleSplits.prefix(1))
        let two = Array(ShareSheetSubject.sampleSplits.prefix(2))

        let withOne = StickerCatalog.climbStickers(for: .fixture(splits: one))
        #expect(!withOne.contains(.splitsChart))
        #expect(!withOne.contains(.fastestSplit))

        let withTwo = StickerCatalog.climbStickers(for: .fixture(splits: two))
        #expect(withTwo.contains(.splitsChart))
        #expect(withTwo.contains(.fastestSplit))
    }

    @Test
    func theClimbBellCurveAndRankNeedARank() {
        let ranked = StickerCatalog.climbStickers(for: .fixture())
        #expect(ranked.contains(.climbBellCurve))
        #expect(ranked.contains(.climbRank))

        let unranked = StickerCatalog.climbStickers(for: .fixture(rank: nil))
        #expect(!unranked.contains(.climbBellCurve))
        #expect(!unranked.contains(.climbRank))
    }

    @Test
    func aClimbListNeverContainsATotalsSticker() {
        let stickers = StickerCatalog.climbStickers(for: .fixture(bestEfforts: [ShareSheetSubject.effort("steps60")]))
        #expect(stickers.allSatisfy { !$0.isTotals })
    }

    // MARK: Totals

    @Test
    func aFullyPopulatedPeriodOffersEveryTotalsSticker() {
        #expect(StickerCatalog.totalsStickers(for: Self.snapshot()) == Self.totalsOrder)
    }

    @Test
    func aPeriodWithNoClimbsKeepsOnlyTheCalendar() {
        let empty = Self.snapshot(climbs: 0)
        #expect(StickerCatalog.totalsStickers(for: empty) == [.calendar])
    }

    @Test
    func averagePaceNeedsAThirtyDayPace() {
        let without = StickerCatalog.totalsStickers(for: Self.snapshot(averagePace: nil))
        #expect(!without.contains(.averagePace))
        #expect(StickerCatalog.totalsStickers(for: Self.snapshot()).contains(.averagePace))
    }

    @Test
    func eachRankAndBellCurveNeedsItsOwnStanding() {
        let noWeek = StickerCatalog.totalsStickers(for: Self.snapshot(week: .some(nil)))
        #expect(!noWeek.contains(.weeklyRank))
        #expect(!noWeek.contains(.weeklyBellCurve))
        #expect(noWeek.contains(.monthlyRank))
        #expect(noWeek.contains(.yearlyBellCurve))

        let noMonth = StickerCatalog.totalsStickers(for: Self.snapshot(month: .some(nil)))
        #expect(!noMonth.contains(.monthlyRank))
        #expect(!noMonth.contains(.monthlyBellCurve))
        #expect(noMonth.contains(.weeklyRank))
        #expect(noMonth.contains(.yearlyRank))

        let noYear = StickerCatalog.totalsStickers(for: Self.snapshot(year: .some(nil)))
        #expect(!noYear.contains(.yearlyRank))
        #expect(!noYear.contains(.yearlyBellCurve))
        #expect(noYear.contains(.weeklyRank))
        #expect(noYear.contains(.monthlyBellCurve))
    }

    @Test
    func theRankTrioNeedsAllThreeStandings() {
        #expect(StickerCatalog.totalsStickers(for: Self.snapshot()).contains(.rankTrio))
        #expect(!StickerCatalog.totalsStickers(for: Self.snapshot(week: .some(nil))).contains(.rankTrio))
        #expect(!StickerCatalog.totalsStickers(for: Self.snapshot(month: .some(nil))).contains(.rankTrio))
        #expect(!StickerCatalog.totalsStickers(for: Self.snapshot(year: .some(nil))).contains(.rankTrio))
    }

    @Test
    func aTotalsListNeverContainsAClimbSticker() {
        let stickers = StickerCatalog.totalsStickers(for: Self.snapshot())
        #expect(stickers.allSatisfy { $0.isTotals })
    }

    // MARK: Fixtures

    /// The mockup's October: 31 days, three empty cells before the 1st, ten climb days.
    /// Pass `.some(nil)` to drop a standing; omitting it keeps the sample one.
    private static func snapshot(
        climbs: Int = 3,
        averagePace: Double? = 84.0,
        week: ShareTotalsSnapshot.Standing?? = nil,
        month: ShareTotalsSnapshot.Standing?? = nil,
        year: ShareTotalsSnapshot.Standing?? = nil
    ) -> ShareTotalsSnapshot {
        ShareTotalsSnapshot(
            period: .week,
            periodCaption: "THIS WEEK",
            steps: 8_240,
            durationSeconds: 3_600,
            floors: 515,
            climbs: climbs,
            calendarMonthName: "OCTOBER",
            calendarLeadingBlanks: 3,
            calendarDayCount: 31,
            calendarClimbDays: [3, 5, 9, 12, 14, 19, 21, 26, 27, 28],
            calendarClimbCount: climbs,
            weeklySteps: [4_000, 6_200, 3_500, 7_800, 8_800, 8_240],
            averagePace30Days: averagePace,
            weekDays: [true, false, true, false, true, true, false],
            weekStanding: week ?? ShareTotalsSnapshot.Standing(position: 3, field: 120),
            monthStanding: month ?? ShareTotalsSnapshot.Standing(position: 8, field: 340),
            yearStanding: year ?? ShareTotalsSnapshot.Standing(position: 21, field: 1_204)
        )
    }
}
