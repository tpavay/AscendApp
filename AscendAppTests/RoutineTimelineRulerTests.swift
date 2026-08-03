import Foundation
import Testing
@testable import AscendApp

struct RoutineTimelineRulerTests {
    @Test
    func anEighteenMinuteRoutineReadsTheWayTheBoardDrewIt() {
        #expect(RoutineTimelineRuler.labels(totalDuration: 1_080) == ["0", "5", "10", "15", "18 MIN"])
    }

    @Test
    func aThirtyMinuteRoutineStepsInTensSoTheTicksStayReadable() {
        #expect(RoutineTimelineRuler.labels(totalDuration: 1_800) == ["0", "10", "20", "30 MIN"])
    }

    @Test
    func aTwoMinuteRoutineStepsInSingleMinutes() {
        #expect(RoutineTimelineRuler.labels(totalDuration: 120) == ["0", "1", "2 MIN"])
    }

    @Test
    func aTwentyMinuteRoutineDropsTheTickThatWouldSitOnTheEndLabel() {
        let labels = RoutineTimelineRuler.labels(totalDuration: 1_200)

        #expect(labels == ["0", "5", "10", "15", "20 MIN"])
        #expect(labels.filter { $0.hasPrefix("20") }.count == 1)
    }

    /// The ruler is the thing that still tells the truth where the width floor has overstated
    /// a short block, so a half minute has to show as a half minute.
    @Test
    func aHalfMinuteShowsOnTheEndLabelRatherThanRoundingAway() {
        #expect(RoutineTimelineRuler.labels(totalDuration: 1_110).last == "18.5")
    }

    @Test
    func noTickEverLandsOnTopOfTheEndLabel() {
        for seconds in stride(from: 30.0, through: 7_200.0, by: 30.0) {
            let labels = RoutineTimelineRuler.labels(totalDuration: seconds)
            let leadingTicks = labels.dropLast().compactMap(Double.init)
            let totalMinutes = seconds / 60

            #expect(!labels.isEmpty)
            #expect(leadingTicks.allSatisfy { $0 < totalMinutes })
            #expect(Set(labels).count == labels.count)
        }
    }

    @Test
    func aVeryLongRoutineStillFitsAHandfulOfTicks() {
        // 25 intervals at the 30-minute ceiling is the worst case the editor can build.
        let labels = RoutineTimelineRuler.labels(totalDuration: 25 * 1_800)

        #expect(labels.count <= 6)
        #expect(labels.last == "750 MIN")
    }

    @Test
    func anEmptyRoutineHasNoRuler() {
        #expect(RoutineTimelineRuler.labels(totalDuration: 0).isEmpty)
    }
}
