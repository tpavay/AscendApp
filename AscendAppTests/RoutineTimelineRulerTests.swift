import Foundation
import Testing
@testable import AscendApp

struct RoutineTimelineRulerTests {
    /// The whole routine, which is what the strip draws while the intervals still fit.
    private func labels(_ totalDuration: TimeInterval) -> [String] {
        RoutineTimelineRuler.labels(startTime: 0, endTime: totalDuration)
    }

    private func ticks(_ totalDuration: TimeInterval) -> [RoutineTimelineRuler.Tick] {
        RoutineTimelineRuler.ticks(startTime: 0, endTime: totalDuration)
    }

    @Test
    func anEighteenMinuteRoutineReadsTheWayTheBoardDrewIt() {
        #expect(labels(1_080) == ["0", "5", "10", "15", "18 MIN"])
    }

    @Test
    func aThirtyMinuteRoutineStepsInTensSoTheTicksStayReadable() {
        #expect(labels(1_800) == ["0", "10", "20", "30 MIN"])
    }

    @Test
    func aTwoMinuteRoutineStepsInSingleMinutes() {
        #expect(labels(120) == ["0", "1", "2 MIN"])
    }

    @Test
    func aTwentyMinuteRoutineDropsTheTickThatWouldSitOnTheEndLabel() {
        let labels = labels(1_200)

        #expect(labels == ["0", "5", "10", "15", "20 MIN"])
        #expect(labels.filter { $0.hasPrefix("20") }.count == 1)
    }

    /// The ruler is the thing that still tells the truth where the width floor has overstated
    /// a short block, so a half minute has to show as a half minute - and the unit stays on it,
    /// because it is the only place the strip names its unit at all.
    @Test
    func aHalfMinuteShowsOnTheEndLabelRatherThanRoundingAway() {
        #expect(labels(1_110).last == "18.5 MIN")
    }

    @Test
    func everyEndLabelCarriesTheUnitWhicheverSideOfTheMinuteItLandsOn() {
        for seconds in stride(from: 30.0, through: 3_600.0, by: 30.0) {
            #expect(labels(seconds).last?.hasSuffix(" MIN") == true)
        }
    }

    // MARK: - Tick positions

    /// The labels index the blocks above them, so a tick sits at its own fraction of the
    /// routine rather than at an equal share of the strip.
    @Test
    func ticksSitAtTheirTrueFractionOfTheRoutine() {
        let ticks = ticks(1_080)

        #expect(ticks.map(\.text) == ["0", "5", "10", "15", "18 MIN"])
        #expect(ticks[0].fraction == 0)
        #expect(abs(ticks[1].fraction - 5.0 / 18.0) < 0.0001)
        #expect(abs(ticks[3].fraction - 15.0 / 18.0) < 0.0001)
        #expect(ticks[4].fraction == 1)
    }

    @Test
    func everyTickIsInsideTheStripAndOrderedAlongIt() {
        for seconds in stride(from: 30.0, through: 7_200.0, by: 30.0) {
            let fractions = ticks(seconds).map(\.fraction)

            #expect(fractions.allSatisfy { $0 >= 0 && $0 <= 1 })
            #expect(zip(fractions, fractions.dropFirst()).allSatisfy { $0 < $1 })
            #expect(fractions.last == 1)
        }
    }

    @Test
    func noTickEverLandsOnTopOfTheEndLabel() {
        for seconds in stride(from: 30.0, through: 7_200.0, by: 30.0) {
            let labels = labels(seconds)
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
        let labels = labels(25 * 1_800)

        #expect(labels.count <= 6)
        #expect(labels.last == "750 MIN")
    }

    @Test
    func anEmptyRoutineHasNoRuler() {
        #expect(labels(0).isEmpty)
    }

    // MARK: - The working window

    /// The strip above the ruler is the window once the routine outgrows the screen, so the
    /// ruler has to name where in the routine that window is. A window opening six minutes in
    /// is labelled from six - labelling it from zero would put every block at the wrong minute.
    @Test
    func aWindowIsLabelledWhereItSitsOnTheRoutinesClockRatherThanFromZero() {
        let labels = RoutineTimelineRuler.labels(startTime: 360, endTime: 570)

        #expect(labels == ["6", "7", "8", "9.5 MIN"])
    }

    @Test
    func aWindowThatOpensOnAHalfMinuteSaysSo() {
        #expect(RoutineTimelineRuler.labels(startTime: 90, endTime: 300).first == "1.5")
    }

    /// The ruler is scaled to the strip it sits under, so its fractions are of the window, not
    /// of the routine - otherwise every tick would be crushed against the leading edge.
    @Test
    func aWindowsTicksSpanTheStripItSitsUnder() {
        let ticks = RoutineTimelineRuler.ticks(startTime: 360, endTime: 570)

        #expect(ticks.first?.fraction == 0)
        #expect(ticks.last?.fraction == 1)
        #expect(zip(ticks, ticks.dropFirst()).allSatisfy { $0.fraction < $1.fraction })
    }

    /// A window covering the whole routine is the whole routine, so nothing below this has to
    /// know whether a window exists.
    @Test
    func aWindowOverTheWholeRoutineReadsExactlyAsTheWholeRoutineDoes() {
        for seconds in stride(from: 30.0, through: 3_600.0, by: 30.0) {
            #expect(RoutineTimelineRuler.labels(startTime: 0, endTime: seconds) == labels(seconds))
        }
    }

    @Test
    func aWindowWithNoSpanHasNoRuler() {
        #expect(RoutineTimelineRuler.labels(startTime: 360, endTime: 360).isEmpty)
        #expect(RoutineTimelineRuler.labels(startTime: 360, endTime: 120).isEmpty)
    }
}
