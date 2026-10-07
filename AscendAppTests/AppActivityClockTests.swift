import Foundation
import Testing
@testable import AscendApp

@MainActor
struct AppActivityClockTests {
    private let launch = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test
    func aProcessThatNeverLeftTheForegroundCountsBothFromLaunch() {
        let clock = AppActivityClock(launchedAt: launch)
        let now = launch.addingTimeInterval(42.9)

        #expect(clock.secondsSinceLaunch(at: now) == 42)
        #expect(clock.secondsSinceForeground(at: now) == 42)
    }

    /// The resume is the moment Firestore's stream is most likely to be down, so it is counted
    /// apart from the launch.
    @Test
    func aResumeRestartsTheForegroundCountAndLeavesTheLaunchCountRunning() {
        let clock = AppActivityClock(launchedAt: launch)

        clock.recordWillEnterForeground(at: launch.addingTimeInterval(600))
        let now = launch.addingTimeInterval(603)

        #expect(clock.secondsSinceLaunch(at: now) == 603)
        #expect(clock.secondsSinceForeground(at: now) == 3)
    }

    @Test
    func aClockReadBeforeItsOwnStartNeverGoesNegative() {
        let clock = AppActivityClock(launchedAt: launch)

        #expect(clock.secondsSinceLaunch(at: launch.addingTimeInterval(-5)) == 0)
    }
}
