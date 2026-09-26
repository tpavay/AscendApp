import Foundation
import Testing
@testable import AscendApp

/// Climbs longer than an hour, end to end through the summary's split math.
///
/// The pre-fix sampler clamped every sample after 59:50 into bucket 359, so the captain's steady
/// 1:30:07 climb summarised as 3,514 steps at 351 spm for 50:00-1:00:00 and 0 steps for every
/// segment after it. These tests replay that exact stored curve, and sessions recorded through the
/// real recorder, into `LiveClimbWorkoutSummaryData` - the one path the completion summary, Workout
/// Detail, the share card and Best Efforts all read.
struct LiveClimbLongClimbSummaryTests {
    @Test
    func thePreFixNinetyMinuteClimbNoLongerPilesItsLastHalfHourIntoOneSegment() throws {
        let climb = try Self.preFixSamplerClimb(named: "steady-84-spm-1h30m")
        let workout = Self.workout(
            duration: climb.durationSeconds,
            steps: climb.steps,
            curve: LiveReplaySplitCurve(
                intervalSeconds: climb.splitIntervalSeconds,
                steps: climb.splitSteps
            )
        )

        let splits = LiveClimbWorkoutSummaryData.paceSplits(for: workout, targetSteps: climb.steps)

        #expect(splits.count == 10)
        #expect(splits.reduce(0) { $0 + $1.steps } == climb.steps)
        // The recorded first hour is untouched.
        #expect(splits.prefix(5).map(\.steps) == [833, 841, 843, 840, 837])
        // 50:00-1:00:00 holds what was climbed in it, not the whole last half hour.
        #expect((820...850).contains(splits[5].steps))
        // The recorder kept nothing between 59:50 and the finish except the total, so the
        // unrecorded tail is spread at its true average pace rather than drawn as zero.
        for split in splits[6...8] {
            #expect((880...900).contains(split.steps))
        }
        #expect(splits.allSatisfy { $0.steps > 0 })
        #expect(splits.allSatisfy { $0.stepsPerMinute < 100 })
    }

    @Test
    func aNinetyMinuteSessionRecordedTodayKeepsEverySegmentsOwnSteps() {
        let workout = Self.recordedSteadySession(
            durationSeconds: 5_408,
            stepsPerMinute: 84
        )

        let splits = LiveClimbWorkoutSummaryData.paceSplits(for: workout, targetSteps: workout.steps)

        #expect(splits.count == 10)
        #expect(splits.reduce(0) { $0 + $1.steps } == workout.steps)
        for split in splits.dropLast() {
            #expect(abs(split.steps - 840) <= 2, "split \(split.index) held \(split.steps) steps")
            #expect(abs(split.stepsPerMinute - 84) < 0.5)
        }
    }

    @Test(arguments: [3 * 3_600, 10 * 3_600])
    func multiHourSessionsKeepCorrectSplitsAndStayInsideTheMetadataBudget(durationSeconds: Int) throws {
        let workout = Self.recordedSteadySession(
            durationSeconds: durationSeconds,
            stepsPerMinute: 80
        )
        let metadata = try #require(LiveClimbWorkoutSummaryData.metadata(for: workout))

        let splits = LiveClimbWorkoutSummaryData.paceSplits(for: workout, targetSteps: workout.steps)

        #expect(splits.count == durationSeconds / 600)
        #expect(splits.reduce(0) { $0 + $1.steps } == workout.steps)
        for split in splits {
            #expect(abs(split.stepsPerMinute - 80) < 0.5, "split \(split.index) ran at \(split.stepsPerMinute)")
        }
        // The curve compacts rather than growing, so a ten-hour climb costs the backup
        // document no more than a one-hour climb does.
        #expect((metadata.splitSteps?.count ?? 0) <= 360)
        #expect((workout.sourceMetadata?.count ?? .max) < WorkoutRemoteSyncLimits.maximumSourceMetadataLength)
    }

    @Test
    func bestEffortsDoNotCreditTheLastHalfHourToTheFirstHour() throws {
        let climb = try Self.preFixSamplerClimb(named: "steady-84-spm-1h30m")
        let workout = Self.workout(
            duration: climb.durationSeconds,
            steps: climb.steps,
            curve: LiveReplaySplitCurve(
                intervalSeconds: climb.splitIntervalSeconds,
                steps: climb.splitSteps
            )
        )

        let points = LiveClimbWorkoutSummaryData.progressPoints(for: workout, targetSteps: climb.steps)

        // The clamped bucket put all 7,708 steps at 1:00:00. Nothing may stand there now
        // except what was actually climbed by then.
        let atOneHour = try #require(points.last { $0.elapsedSeconds <= 3_600 })
        #expect(atOneHour.steps < 5_100)
        #expect(points.last == LiveClimbProgressPoint(elapsedSeconds: 5_407, steps: climb.steps))
    }

    // MARK: - Helpers

    private struct PreFixSamplerClimbs: Decodable {
        let climbs: [PreFixSamplerClimb]
    }

    private struct PreFixSamplerClimb: Decodable {
        let name: String
        let steps: Int
        let durationSeconds: Double
        let splitIntervalSeconds: Int
        let splitSteps: [Int]
    }

    private static func preFixSamplerClimb(named name: String) throws -> PreFixSamplerClimb {
        let repoRoot = URL(filePath: #filePath)
            .deletingLastPathComponent() // AscendAppTests/
            .deletingLastPathComponent() // repo root
        let data = try Data(
            contentsOf: repoRoot.appending(path: "SharedTestVectors/pre-fix-sampler-long-climbs.json")
        )
        let climbs = try JSONDecoder().decode(PreFixSamplerClimbs.self, from: data).climbs
        return try #require(climbs.first { $0.name == name })
    }

    /// Drives the production recorder once a second at a steady pace, exactly as a live
    /// session feeds it, and saves the curve it ends on.
    private static func recordedSteadySession(durationSeconds: Int, stepsPerMinute: Int) -> Workout {
        var recorder = LiveClimbStepTimelineRecorder()
        func steps(at second: Int) -> Int { second * stepsPerMinute / 60 }

        for second in 0...durationSeconds {
            recorder.record(elapsedSeconds: second, cumulativeSteps: steps(at: second), source: .headphoneMotion)
        }

        return workout(
            duration: TimeInterval(durationSeconds),
            steps: steps(at: durationSeconds),
            curve: recorder.curve
        )
    }

    private static func workout(duration: TimeInterval, steps: Int, curve: LiveReplaySplitCurve) -> Workout {
        let metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: curve.steps.count,
            trackingMode: .justClimb,
            climbId: nil,
            targetStepCount: nil,
            stopReason: .userStopped,
            splitCurve: curve
        )

        return Workout(
            name: "Just Climb",
            duration: duration,
            steps: steps,
            floors: Workout.stepsToFloors(steps, stepsPerFloor: 16),
            stepsPerFloor: 16,
            source: .headphoneMotion,
            sourceMetadata: metadata.jsonString
        )
    }
}
