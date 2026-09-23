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

    @Test("Neither pace answers before the clock has run five seconds", arguments: [0.0, 0.4, 1, 4.9])
    func nothingIsStatedBeforeEnoughClock(elapsed: TimeInterval) {
        var window = LiveClimbPaceWindow()
        window.record(elapsedSeconds: 0, steps: 0)

        #expect(LiveClimbPaceWindow.averageStepsPerMinute(steps: 3, elapsedSeconds: elapsed) == nil)
        #expect(window.currentStepsPerMinute(elapsedSeconds: elapsed, steps: 3) == nil)
    }

    @Test("A window with no samples still answers the climb-so-far pace, never a division by zero")
    func emptyWindowFallsBackToTheAverage() {
        let window = LiveClimbPaceWindow()

        #expect(window.currentStepsPerMinute(elapsedSeconds: 0, steps: 0) == nil)
        #expect(window.currentStepsPerMinute(elapsedSeconds: 30, steps: 45) == 90)
    }

    @Test("Current pace equals the average until the window has elapsed")
    func currentMatchesAverageInsideTheFirstWindow() {
        var window = LiveClimbPaceWindow()
        window.record(elapsedSeconds: 0, steps: 0)
        for second in 1...20 {
            window.record(elapsedSeconds: TimeInterval(second), steps: second * 2)
        }

        #expect(window.currentStepsPerMinute(elapsedSeconds: 20, steps: 40) == 120)
        #expect(LiveClimbPaceWindow.averageStepsPerMinute(steps: 40, elapsedSeconds: 20) == 120)
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
        #expect(window.currentStepsPerMinute(elapsedSeconds: 15, steps: 20) == 120)
    }

    @Test("Reset forgets every sample")
    func resetForgetsEverything() {
        var window = LiveClimbPaceWindow()
        window.record(elapsedSeconds: 0, steps: 0)
        window.record(elapsedSeconds: 40, steps: 40)

        window.reset()

        #expect(window.samples.isEmpty)
        #expect(window.currentStepsPerMinute(elapsedSeconds: 41, steps: 41) == 60)
    }

    @Test("A count that fell below the anchor never reads as a negative pace")
    func neverNegative() {
        var window = LiveClimbPaceWindow()
        window.record(elapsedSeconds: 0, steps: 100)

        #expect(window.currentStepsPerMinute(elapsedSeconds: 30, steps: 40) == 0)
    }
}
