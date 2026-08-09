import Foundation
import SwiftUI
import Testing
@testable import AscendApp

/// The activity detail screen's per-scroll and per-render work contracts.
struct WorkoutDetailScrollWorkTests {
    /// The nav-bar title reveal is the only thing the detail screen derives from the
    /// scroll position. Fed a whole drag, the value it keys on must change once per
    /// threshold crossing - not once per tick, which is what the replaced
    /// `GeometryReader` + `onChange(of: minY)` overlay produced.
    @Test
    func aFullScrollFlipsTheNavigationTitleOnlyAtTheCrossings() {
        // Scroll down past the threshold, then back up: 200 ticks, two crossings.
        let downwards = stride(from: CGFloat(0), through: 600, by: 6)
        let upwards = stride(from: CGFloat(600), through: 0, by: -6)
        let trace = Array(downwards) + Array(upwards)

        let reveals = trace.map { WorkoutDetailView.revealsNavigationTitle(scrolledDistance: $0) }
        let changes = zip(reveals, reveals.dropFirst()).count { $0 != $1 }

        #expect(trace.count == 202)
        #expect(changes == 2)
    }

    @Test
    func theTitleStaysHiddenWhileTheInlineTitleIsStillOnScreen() {
        #expect(WorkoutDetailView.revealsNavigationTitle(scrolledDistance: 0) == false)
        #expect(WorkoutDetailView.revealsNavigationTitle(scrolledDistance: -40) == false)
        #expect(
            WorkoutDetailView.revealsNavigationTitle(
                scrolledDistance: WorkoutDetailView.navigationTitleRevealOffset
            ) == false
        )
        #expect(
            WorkoutDetailView.revealsNavigationTitle(
                scrolledDistance: WorkoutDetailView.navigationTitleRevealOffset + 1
            )
        )
    }

    // MARK: - Derived content

    /// `WorkoutDetailDerivedContent` exists so one render pass decodes the
    /// headphone-motion metadata and the heart-rate blob once each. That "once" is
    /// carried by the initialiser's shape rather than by a counter, so what is
    /// asserted here is that it answers everything the body needs - if any of these
    /// were missing, the body would have to re-derive it per reader again.
    @Test
    func derivedContentAnswersEverythingTheBodyNeedsForALiveSession() throws {
        let workout = Self.thresholdIntervalsWorkout()
        let derived = WorkoutDetailDerivedContent(workout: workout)

        #expect(derived.liveClimbMetadata != nil)
        #expect(derived.canOpenLiveClimbSummary)
        #expect(derived.heartRateSeries.isEmpty == false)
        #expect(derived.heartRateSeries.count == 2_603)
        #expect(derived.showsPaceSplits)
        #expect(derived.paceSplits.count == 9)
    }

    @Test
    func derivedContentIsEmptyForAManualEntry() {
        let workout = Workout(
            name: "Manual Session",
            duration: 1_800,
            steps: 2_000,
            floors: 125,
            source: .headphoneMotion
        )
        let derived = WorkoutDetailDerivedContent(workout: workout)

        #expect(derived.liveClimbMetadata == nil)
        #expect(derived.canOpenLiveClimbSummary == false)
        #expect(derived.heartRateSeries.isEmpty)
        #expect(derived.showsPaceSplits == false)
        #expect(derived.paceSplits.isEmpty)
    }

    /// A session whose recorder never captured intermediate checkpoints must not get
    /// a splits section - those "splits" would be a straight line reconstructed from
    /// the final total. This is the rule the view used to own inline.
    @Test
    func derivedContentHidesSplitsWhenNoIntermediateCheckpointsWereRecorded() {
        let workout = Self.thresholdIntervalsWorkout(splitSteps: [0, 0, 4_134])
        let derived = WorkoutDetailDerivedContent(workout: workout)

        #expect(derived.canOpenLiveClimbSummary)
        #expect(derived.showsPaceSplits == false)
    }

    // MARK: - Fixtures

    private static func thresholdIntervalsWorkout(
        splitSteps: [Int] = [370, 876, 1_383, 1_840, 2_375, 2_835, 3_361, 3_895, 4_134]
    ) -> Workout {
        let start = Date(timeIntervalSince1970: 1_750_300_000)
        let durationSeconds = 2_603
        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: durationSeconds * 50,
            trackingMode: .routine,
            climbId: nil,
            targetStepCount: 4_134,
            stopReason: .userStopped,
            splitCurve: LiveReplaySplitCurve(intervalSeconds: 300, steps: splitSteps)
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
}
