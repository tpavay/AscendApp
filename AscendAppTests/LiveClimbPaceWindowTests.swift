import Foundation
import Testing

@testable import AscendApp

/// The PACE card's two numbers: the whole-climb average and the trailing-window current pace.
struct LiveClimbPaceWindowTests {
    @Test("Average pace is total steps over elapsed minutes")
    func averageIsStepsOverElapsedMinutes() {
        #expect(LiveClimbPaceWindow.averageStepsPerMinute(steps: 300, elapsedSeconds: 754) == 24)
        #expect(LiveClimbPaceWindow.averageStepsPerMinute(steps: 120, elapsedSeconds: 60) == 120)
        #expect(LiveClimbPaceWindow.averageStepsPerMinute(steps: 0, elapsedSeconds: 60) == 0)
    }

    @Test(
        "The average answers from the start: zero before a full second, the real ratio after",
        arguments: [
            (elapsed: 0.0, steps: 0, expected: 0),
            (elapsed: 0.4, steps: 1, expected: 0),
            (elapsed: 1, steps: 1, expected: 60),
            (elapsed: 4.9, steps: 6, expected: 73),
            (elapsed: 12, steps: 16, expected: 80),
        ]
    )
    func averageAnswersFromTheStart(elapsed: TimeInterval, steps: Int, expected: Int) {
        #expect(LiveClimbPaceWindow.averageStepsPerMinute(steps: steps, elapsedSeconds: elapsed) == expected)
    }

    @Test("The average never divides by a bad clock")
    func averageSurvivesABadClock() {
        #expect(LiveClimbPaceWindow.averageStepsPerMinute(steps: 10, elapsedSeconds: -5) == 0)
        #expect(LiveClimbPaceWindow.averageStepsPerMinute(steps: 10, elapsedSeconds: .nan) == 0)
        #expect(LiveClimbPaceWindow.averageStepsPerMinute(steps: 10, elapsedSeconds: .infinity) == 0)
    }

    @Test("Current pace states nothing until the window spans a full thirty seconds, then a number")
    func currentWaitsForTheWholeWindow() {
        var window = LiveClimbPaceWindow()
        window.record(elapsedSeconds: 0, steps: 0)
        for second in 1...29 {
            window.record(elapsedSeconds: TimeInterval(second), steps: second * 2)
            #expect(
                window.currentStepsPerMinute(elapsedSeconds: TimeInterval(second), steps: second * 2) == nil,
                "a CURRENT number at \(second)s would describe a window the climb has not had"
            )
        }

        window.record(elapsedSeconds: 30, steps: 60)
        #expect(window.currentStepsPerMinute(elapsedSeconds: 30, steps: 60) == 120)
    }

    @Test("A window with no samples states no current pace, never a division by zero")
    func emptyWindowStatesNothing() {
        let window = LiveClimbPaceWindow()

        #expect(window.currentStepsPerMinute(elapsedSeconds: 0, steps: 0) == nil)
        #expect(window.currentStepsPerMinute(elapsedSeconds: 30, steps: 45) == nil)
        #expect(window.currentStepsPerMinute(elapsedSeconds: .nan, steps: 45) == nil)
    }

    @Test("Current pace follows the trailing window while the average follows the whole climb")
    func currentFollowsTheTrailingWindow() {
        var window = LiveClimbPaceWindow()
        // One step a second for a minute, then two a second for the next thirty.
        for second in 0...60 {
            window.record(elapsedSeconds: TimeInterval(second), steps: second)
        }
        for second in 61...90 {
            window.record(elapsedSeconds: TimeInterval(second), steps: 60 + (second - 60) * 2)
        }

        #expect(window.currentStepsPerMinute(elapsedSeconds: 90, steps: 120) == 120)
        #expect(LiveClimbPaceWindow.averageStepsPerMinute(steps: 120, elapsedSeconds: 90) == 80)
    }

    @Test("A climber who stops stepping reads zero, not the pace they had")
    func stoppingReadsZero() {
        var window = LiveClimbPaceWindow()
        for second in 0...60 {
            window.record(elapsedSeconds: TimeInterval(second), steps: second)
        }
        for second in 61...100 {
            window.record(elapsedSeconds: TimeInterval(second), steps: 60)
        }

        #expect(window.currentStepsPerMinute(elapsedSeconds: 100, steps: 60) == 0)
    }

    @Test("The window keeps its anchor and drops what is older, so memory stays bounded")
    func trimsToTheWindow() {
        var window = LiveClimbPaceWindow(windowSeconds: 30)
        for second in 0...600 {
            window.record(elapsedSeconds: TimeInterval(second), steps: second)
        }

        #expect(window.samples.count == 31)
        #expect(window.samples.first?.elapsedSeconds == 570)
        #expect(window.currentStepsPerMinute(elapsedSeconds: 600, steps: 600) == 60)
    }

    @Test("A sample from an earlier clock restarts the window rather than spanning two clocks")
    func clockGoingBackwardsRestartsTheWindow() {
        var window = LiveClimbPaceWindow()
        for second in 0...60 {
            window.record(elapsedSeconds: TimeInterval(second), steps: second * 2)
        }

        window.record(elapsedSeconds: 5, steps: 0)

        #expect(window.samples.count == 1)
        #expect(window.currentStepsPerMinute(elapsedSeconds: 6, steps: 3) == nil)
        #expect(window.currentStepsPerMinute(elapsedSeconds: 34, steps: 58) == nil, "the restarted window is only 29 seconds long")
        #expect(window.currentStepsPerMinute(elapsedSeconds: 35, steps: 60) == 120)
    }

    @Test("Reset forgets every sample")
    func resetForgetsEverything() {
        var window = LiveClimbPaceWindow()
        window.record(elapsedSeconds: 0, steps: 0)
        window.record(elapsedSeconds: 40, steps: 40)

        window.reset()

        #expect(window.samples.isEmpty)
        #expect(window.currentStepsPerMinute(elapsedSeconds: 41, steps: 41) == nil, "after a reset the window starts over")
    }

    @Test("A count that fell below the anchor never reads as a negative pace")
    func neverNegative() {
        var window = LiveClimbPaceWindow()
        window.record(elapsedSeconds: 0, steps: 100)

        #expect(window.currentStepsPerMinute(elapsedSeconds: 30, steps: 40) == 0)
    }
}
