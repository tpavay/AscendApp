import Foundation
import Testing
@testable import AscendApp

struct LiveClimbWorkoutSummaryDataTests {
    @Test
    func paceSplitsAssignsStepsToPartialFinalInterval() {
        let workout = makeLiveClimbWorkout(
            duration: 65,
            steps: 65,
            splitSteps: [0, 10, 20, 30, 40, 50, 65]
        )

        let splits = LiveClimbWorkoutSummaryData.paceSplits(
            for: workout,
            targetSteps: 65
        )

        #expect(splits.count == 2)
        #expect(splits[0].startElapsedSeconds == 0)
        #expect(splits[0].endElapsedSeconds == 60)
        #expect(splits[0].steps == 60)
        #expect(splits[1].startElapsedSeconds == 60)
        #expect(splits[1].endElapsedSeconds == 65)
        #expect(splits[1].steps == 5)
        #expect(abs(splits[1].stepsPerMinute - 60) < 0.001)
        #expect(splits.reduce(0) { $0 + $1.steps } == workout.steps)
    }

    @Test
    func paceSplitsUsesWorkoutTotalForShortFinalOnlyClimb() throws {
        let workout = makeLiveClimbWorkout(
            duration: 56,
            steps: 143,
            splitSteps: [0, 24, 48, 72, 96, 121]
        )

        let splits = LiveClimbWorkoutSummaryData.paceSplits(
            for: workout,
            targetSteps: 143
        )

        let split = try #require(splits.first)
        #expect(splits.count == 1)
        #expect(split.startElapsedSeconds == 0)
        #expect(split.endElapsedSeconds == 56)
        #expect(split.steps == 143)
        #expect(abs(split.stepsPerMinute - (143.0 / (56.0 / 60.0))) < 0.001)
    }

    @Test
    func paceSplitsReconcileWithWorkoutWhenFirstBucketContainsSteps() throws {
        let durationSeconds = 15 * 60 + 30
        let workoutSteps = 1_240
        let splitSteps = (0...93).map { bucket in
            min(14 + bucket * 13, workoutSteps)
        }
        let workout = makeLiveClimbWorkout(
            duration: TimeInterval(durationSeconds),
            steps: workoutSteps,
            splitSteps: splitSteps
        )

        let splits = LiveClimbWorkoutSummaryData.paceSplits(
            for: workout,
            targetSteps: workoutSteps
        )

        let firstSplit = try #require(splits.first)
        let lastSplit = try #require(splits.last)
        #expect(splits.count == 8)
        #expect(firstSplit.startElapsedSeconds == 0)
        #expect(lastSplit.endElapsedSeconds == durationSeconds)
        #expect(splits.reduce(0) { $0 + $1.durationSeconds } == durationSeconds)
        #expect(splits.reduce(0) { $0 + $1.steps } == workoutSteps)
        for (split, nextSplit) in zip(splits, splits.dropFirst()) {
            #expect(split.endElapsedSeconds == nextSplit.startElapsedSeconds)
        }
    }

    private func makeLiveClimbWorkout(
        duration: TimeInterval,
        steps: Int,
        splitSteps: [Int]
    ) -> Workout {
        let splitCurve = LiveReplaySplitCurve(
            intervalSeconds: 10,
            steps: splitSteps
        )
        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: splitSteps.count,
            climbId: "test-climb",
            targetStepCount: steps,
            stopReason: .targetReached,
            splitCurve: splitCurve
        )

        return Workout(
            name: "Live Climb",
            duration: duration,
            steps: steps,
            floors: Workout.stepsToFloors(steps, stepsPerFloor: 16),
            stepsPerFloor: 16,
            source: .headphoneMotion,
            sourceMetadata: metadata.jsonString
        )
    }
}
