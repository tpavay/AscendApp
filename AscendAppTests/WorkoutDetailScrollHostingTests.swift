import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Drives a real scroll on the real activity detail screen.
///
/// The screen is hosted in a `UIHostingController` on the test host app's live
/// window scene - a detached window has no display link, so SwiftUI never runs its
/// update loop in one and every measurement taken there reads as free - and the
/// `UIScrollView` SwiftUI created is driven a display frame's worth at a time.
///
/// What this covers: the screen still builds and scrolls for the shape of activity
/// that stuttered (43 minutes, nine pace splits, a per-second heart-rate trace), and
/// a whole drag stays far inside a loose wall-clock bound.
///
/// What it cannot cover: the frame drops the captain saw are rasterization cost on
/// device, and neither this harness nor any other test in this target observes the
/// render server. `HeartRateChartDownsamplingTests` pins the mark count that drives
/// that cost instead.
@MainActor
@Suite(.hostsAWindow)
struct WorkoutDetailScrollHostingTests {
    /// Two seconds of 60 Hz scrolling - the length of the drag in the recording.
    private static let scrollTickCount = 120

    /// Loose on purpose: it guards the order of magnitude, not a machine's speed, so
    /// it cannot flake on a loaded CI runner. Measured well under 100 ms locally.
    private static let scrollBudget: Duration = .milliseconds(1_500)

    @Test
    func theScreenScrollsWithoutPerTickWork() throws {
        let container = try ModelContainer(
            for: Workout.self,
            WorkoutSourceLink.self,
            WorkoutParticipation.self,
            BestEffortCacheEntry.self,
            BestEffortCacheMetadata.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        let workout = Self.thresholdIntervalsWorkout()
        container.mainContext.insert(workout)

        let host = UIHostingController(
            rootView: WorkoutDetailView(workout: workout, embedsInNavigationStack: false)
                .environment(AuthenticationViewModel())
                .environment(MediaUploadManager.shared)
                .modelContainer(container)
        )

        let scene = try #require(
            UIApplication.shared.connectedScenes.first as? UIWindowScene,
            "test host app should expose a live UIWindowScene"
        )
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.makeKeyAndVisible()
        // Detaching from the scene is what dismantles the content. Hiding is not enough: a window
        // still attached keeps `WorkoutDetailView`'s `@Query` observing SwiftData after the
        // container declared above has gone, and that observer then traps on the next save any
        // other suite performs, taking the whole test process down.
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
            window.rootViewController = nil
            window.windowScene = nil
        }
        Self.flush(window)

        let scrollView = try #require(
            Self.firstScrollView(in: window),
            "the no-photo layout should render a ScrollView"
        )
        Self.flush(window)

        // Every section of the recording's screen has to be laid out for this to be
        // a fair drive; a blank or truncated hierarchy would scroll for free.
        #expect(
            scrollView.contentSize.height > 1_400,
            "expected the full detail content, got \(scrollView.contentSize)"
        )

        let pointsPerTick: CGFloat = 6
        let elapsed = ContinuousClock().measure {
            for tick in 1...Self.scrollTickCount {
                scrollView.contentOffset = CGPoint(x: 0, y: CGFloat(tick) * pointsPerTick)
                Self.flush(window)
            }
        }

        #expect(
            elapsed < Self.scrollBudget,
            """
            \(Self.scrollTickCount) scroll ticks took \(elapsed), over the \
            \(Self.scrollBudget) budget - the screen is doing per-tick work again. \
            Check for scroll position written into view state on every tick, and for \
            derived values (pace splits, heart-rate series, chart data set) rebuilt \
            inside the view body rather than resolved once per pass.
            """
        )
    }

    // MARK: - Fixtures

    /// The activity from the recording: a 43:23 headphone-motion session with nine
    /// pace splits and a full per-second heart-rate trace.
    ///
    /// `.routine` with no template id renders every section the recording shows while
    /// resolving to a nil leaderboard context, so `.task` never reaches for the
    /// network and the drive stays deterministic.
    private static func thresholdIntervalsWorkout() -> Workout {
        let start = Date(timeIntervalSince1970: 1_750_300_000)
        let durationSeconds = 2_603
        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: durationSeconds * 50,
            trackingMode: .routine,
            climbId: nil,
            targetStepCount: 4_134,
            stopReason: .userStopped,
            splitCurve: LiveReplaySplitCurve(
                intervalSeconds: 300,
                steps: [370, 876, 1_383, 1_840, 2_375, 2_835, 3_361, 3_895, 4_134]
            )
        )

        return Workout(
            name: "Threshold Intervals",
            date: start,
            duration: TimeInterval(durationSeconds),
            steps: 4_134,
            floors: 258,
            avgHeartRate: 154,
            maxHeartRate: 177,
            caloriesBurned: 669,
            heartRateTimeSeries: (0..<durationSeconds).map { second in
                HeartRateDataPoint(
                    timestamp: start.addingTimeInterval(TimeInterval(second)),
                    heartRate: 150 + Int((sin(Double(second) / 90) * 20).rounded())
                )
            },
            averageMETs: 11.4,
            source: .headphoneMotion,
            sourceMetadata: metadata.jsonString
        )
    }

    // MARK: - Hosting helpers

    /// Runs the render loop far enough that SwiftUI has applied the invalidations the
    /// tick produced, so the loop measures the work rather than the queuing of it.
    private static func flush(_ window: UIWindow) {
        window.layoutIfNeeded()
        CATransaction.flush()
        RunLoop.current.run(until: Date())
    }

    private static func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) {
                return found
            }
        }
        return nil
    }
}
