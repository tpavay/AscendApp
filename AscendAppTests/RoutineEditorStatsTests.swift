import Foundation
import Testing
@testable import AscendApp

struct RoutineEditorStatsTests {
    /// The routine drawn on the design board: 3:00 at 16, 4:00 at 7, 4:00 at 6, 3:00 at 20,
    /// 4:00 at 4 - which reads 18 min, 5 intervals, avg 10, peak 20.
    private let boardRoutine = [
        RoutineInterval(duration: 180, intensityValue: 16, order: 0),
        RoutineInterval(duration: 240, intensityValue: 7, order: 1),
        RoutineInterval(duration: 240, intensityValue: 6, order: 2),
        RoutineInterval(duration: 180, intensityValue: 20, order: 3),
        RoutineInterval(duration: 240, intensityValue: 4, order: 4)
    ]

    @Test
    func theHeaderReadsWhatTheBoardDrew() {
        let stats = RoutineEditorStats(intervals: boardRoutine)

        #expect(stats.totalMinutes == 18)
        #expect(stats.intervalCount == 5)
        #expect(stats.averageLevel == 10)
        #expect(stats.peakLevel == 20)
    }

    /// Unweighted this routine averages 10.6 and would read 11. Five minutes at level 20 has
    /// to count for more than thirty seconds at level 4.
    @Test
    func theAverageIsWeightedByHowLongEachIntervalLasts() {
        let stats = RoutineEditorStats(intervals: [
            RoutineInterval(duration: 1_500, intensityValue: 20, order: 0),
            RoutineInterval(duration: 30, intensityValue: 4, order: 1)
        ])

        #expect(stats.averageLevel == 20)
    }

    @Test
    func aRoutineAtEighteenAndAHalfMinutesStillReadsEighteen() {
        var intervals = boardRoutine
        intervals[0].duration = 210

        #expect(RoutineEditorStats(intervals: intervals).totalMinutes == 18)
    }

    @Test
    func anEmptyRoutineHasNothingToReport() {
        let stats = RoutineEditorStats(intervals: [])

        #expect(stats == .empty)
        #expect(stats.isEmpty)
        #expect(stats.totalMinutes == 0)
    }

    @Test
    func peakIsTheHardestIntervalNotTheLastOne() {
        #expect(RoutineEditorStats(intervals: boardRoutine).peakLevel == 20)
    }

    // MARK: - What draws live during a drag

    @Test
    func draggingAnIntervalLongerLightsUpTheTotalAndTheAverage() {
        let before = RoutineEditorStats(intervals: boardRoutine)

        // The hardest interval taken from 3:00 to 10:00 pulls the whole routine up with it.
        var after = boardRoutine
        after[0].duration = 600

        let changed = RoutineEditorStats(intervals: after).changedKeys(comparedTo: before)

        #expect(changed.contains(.total))
        #expect(changed.contains(.averageLevel))
        #expect(!changed.contains(.intervalCount))
        #expect(!changed.contains(.peakLevel))
    }

    @Test
    func draggingAnIntervalPastThePeakLightsUpThePeak() {
        let before = RoutineEditorStats(intervals: boardRoutine)

        var after = boardRoutine
        after[0].intensityValue = 24

        let changed = RoutineEditorStats(intervals: after).changedKeys(comparedTo: before)

        #expect(changed.contains(.peakLevel))
        #expect(changed.contains(.averageLevel))
        #expect(!changed.contains(.total))
    }

    @Test
    func addingAnIntervalLightsUpTheCountAndTheTotal() {
        let before = RoutineEditorStats(intervals: boardRoutine)

        let after = RoutineEditorStats(
            intervals: boardRoutine + [RoutineInterval(duration: 120, intensityValue: 1, order: 5)]
        )

        #expect(after.changedKeys(comparedTo: before).contains(.intervalCount))
        #expect(after.changedKeys(comparedTo: before).contains(.total))
    }

    @Test
    func aDragThatHasNotYetMovedAnythingLightsUpNothing() {
        let stats = RoutineEditorStats(intervals: boardRoutine)

        #expect(stats.changedKeys(comparedTo: stats).isEmpty)
    }

    /// A block growing by 30 seconds inside an 18-minute routine does not change the whole
    /// minute count, and nothing should flash for a number that did not move.
    @Test
    func aChangeTooSmallToShowInTheHeaderDoesNotFlashTheHeader() {
        let before = RoutineEditorStats(intervals: boardRoutine)

        var after = boardRoutine
        after[0].duration = 210

        #expect(!RoutineEditorStats(intervals: after).changedKeys(comparedTo: before).contains(.total))
    }
}
