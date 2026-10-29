import Foundation
import Testing
@testable import AscendApp

struct ShareBestEffortDisplayTests {
    private let one = [ShareSheetSubject.effort("fastest3000Steps", rank: 2, title: "FASTEST 3,000 STEPS")]
    private let many = [
        ShareSheetSubject.effort("mostSteps"),
        ShareSheetSubject.effort("fastest500Steps"),
        ShareSheetSubject.effort("mostStepsIn5Min")
    ]

    @Test
    func noneEarnedShowsNothing() {
        #expect(ShareBestEffortDisplay.resolve(efforts: [], isOn: true, pickedID: nil) == .none)
    }

    @Test
    func theChipSwitchedOffShowsNothing() {
        #expect(ShareBestEffortDisplay.resolve(efforts: many, isOn: false, pickedID: nil) == .none)
    }

    @Test
    func oneEffortShowsItsLineNotACountOfOne() {
        #expect(ShareBestEffortDisplay.resolve(efforts: one, isOn: true, pickedID: nil) == .line(one[0]))
    }

    @Test
    func severalShowTheRealCount() {
        #expect(ShareBestEffortDisplay.resolve(efforts: many, isOn: true, pickedID: nil) == .count(3))
    }

    @Test
    func pickingOneShowsItsLineInsteadOfTheCount() {
        let display = ShareBestEffortDisplay.resolve(efforts: many, isOn: true, pickedID: "fastest500Steps")
        #expect(display == .line(many[1]))
    }

    @Test
    func aPickThatNoLongerExistsFallsBackToTheCount() {
        #expect(ShareBestEffortDisplay.resolve(efforts: many, isOn: true, pickedID: "gone") == .count(3))
    }

    private func ranked(_ metric: BestEffortMetric, rank: Int, scope: BestEffortScope) -> RankedBestEffort {
        let workout = Workout(duration: 3_770, steps: 5_004, floors: 0, source: .manual)
        return RankedBestEffort(
            metric: metric,
            rank: rank,
            scope: scope,
            context: .all,
            performance: BestEffortPerformance(
                metric: metric,
                workout: workout,
                value: 5_004,
                steps: 5_004,
                duration: 3_770,
                segmentStartElapsedSeconds: nil,
                segmentEndElapsedSeconds: nil
            )
        )
    }

    @Test
    func aMeasureThatIsARecordTwiceCountsOnceAtItsBestRanking() {
        let resolved = ShareSheetBestEffortResolver.resolve([
            ranked(.mostSteps, rank: 2, scope: .allTime),
            ranked(.mostSteps, rank: 1, scope: .thisYear),
            ranked(.longestClimb, rank: 3, scope: .allTime)
        ])

        #expect(resolved.count == 2)
        #expect(resolved[0].id == "mostSteps")
        #expect(resolved[0].rankText == "1ST")
        #expect(resolved[0].scopeText == "THIS YEAR")
        #expect(resolved[1].title == "LONGEST CLIMB")
    }

    @Test
    func theResolverKeepsTheOrderItWasGivenSoTheMostSignificantStaysFirst() {
        let resolved = ShareSheetBestEffortResolver.resolve([
            ranked(.fastestStepTarget(steps: 3_000), rank: 2, scope: .allTime),
            ranked(.mostSteps, rank: 1, scope: .allTime)
        ])

        #expect(resolved.map(\.id) == ["fastest3000Steps", "mostSteps"])
        #expect(resolved[0].title == "FASTEST 3,000 STEPS")
        #expect(resolved[0].detailText == "2ND ALL-TIME")
    }
}
