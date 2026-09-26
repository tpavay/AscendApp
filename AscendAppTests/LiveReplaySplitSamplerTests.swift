import Foundation
import Testing
@testable import AscendApp

struct LiveReplaySplitSamplerTests {
    @Test
    func samplesStepsIntoFixedTimeBuckets() {
        var sampler = LiveReplaySplitSampler(intervalSeconds: 10)

        _ = sampler.record(elapsedSeconds: 4, steps: 12)
        _ = sampler.record(elapsedSeconds: 12, steps: 25)
        let curve = sampler.record(elapsedSeconds: 35, steps: 90)

        #expect(curve.intervalSeconds == 10)
        #expect(curve.steps == [12, 25, 25, 90])
        #expect(curve.latestBucketIndex == 3)
    }

    @Test
    func neverMovesABucketBackwardWhenStepEstimateDrops() {
        var sampler = LiveReplaySplitSampler(intervalSeconds: 10)

        _ = sampler.record(elapsedSeconds: 15, steps: 60)
        let curve = sampler.record(elapsedSeconds: 18, steps: 54)

        #expect(curve.steps == [0, 60])
    }

    @Test
    func doublesTheIntervalInsteadOfClampingWhenTheCurveFills() {
        var sampler = LiveReplaySplitSampler(intervalSeconds: 10, maxCheckpoints: 4)

        for second in stride(from: 5, through: 35, by: 10) {
            _ = sampler.record(elapsedSeconds: second, steps: second)
        }
        let curve = sampler.record(elapsedSeconds: 45, steps: 45)

        // Buckets 0+1 and 2+3 merge into two 20-second buckets, and the sample that would
        // have been clamped into the last 10-second bucket opens a third.
        #expect(curve.intervalSeconds == 20)
        #expect(curve.steps == [15, 35, 45])
    }

    @Test
    func aSessionInsideAnHourRecordsExactlyAsItAlwaysHas() {
        var sampler = LiveReplaySplitSampler()

        var curve = sampler.curve
        for second in 0..<3_600 {
            curve = sampler.record(elapsedSeconds: second, steps: second)
        }

        #expect(curve.intervalSeconds == 10)
        #expect(curve.steps.count == 360)
        #expect(curve.steps.last == 3_599)
    }

    @Test
    func aNinetyMinuteSessionKeepsEveryBucketItRecorded() {
        var sampler = LiveReplaySplitSampler()

        var curve = sampler.curve
        for second in 0...5_408 {
            curve = sampler.record(elapsedSeconds: second, steps: second * 84 / 60)
        }

        #expect(curve.intervalSeconds == 20)
        #expect(curve.steps.count == 5_408 / 20 + 1)
        // Each bucket holds the latest sample inside its own window - the 59:50 bucket did not
        // swallow the last half hour.
        for (index, steps) in curve.steps.enumerated().dropLast() {
            #expect(steps == (index * 20 + 19) * 84 / 60)
        }
        #expect(curve.steps.last == 5_408 * 84 / 60)
    }

    @Test(arguments: [(3 * 3_600, 40), (10 * 3_600, 160)])
    func multiHourSessionsStayInsideTheCheckpointBudget(durationSeconds: Int, expectedInterval: Int) {
        var sampler = LiveReplaySplitSampler()

        var curve = sampler.curve
        for second in stride(from: 0, through: durationSeconds, by: 5) {
            curve = sampler.record(elapsedSeconds: second, steps: second)
        }

        #expect(curve.intervalSeconds == expectedInterval)
        #expect(curve.steps.count == durationSeconds / expectedInterval + 1)
        #expect(curve.steps.count <= 360)
        #expect(curve.steps.last == durationSeconds)
    }

    @Test
    func restoringResumesAtTheIntervalTheCurveWasRecordedAt() {
        var original = LiveReplaySplitSampler()
        for second in 0...4_000 {
            _ = original.record(elapsedSeconds: second, steps: second)
        }

        var restored = LiveReplaySplitSampler(restoring: original.curve)
        let resumed = restored.record(elapsedSeconds: 4_100, steps: 4_100)
        let uninterrupted = original.record(elapsedSeconds: 4_100, steps: 4_100)

        #expect(resumed == uninterrupted)
        #expect(resumed.intervalSeconds == 20)
    }

    @Test
    func resetStartsTheNextSessionAtTheBaseInterval() {
        var sampler = LiveReplaySplitSampler()
        _ = sampler.record(elapsedSeconds: 7_200, steps: 9_000)

        sampler.reset()
        let curve = sampler.record(elapsedSeconds: 12, steps: 20)

        #expect(curve.intervalSeconds == 10)
        #expect(curve.steps == [0, 20])
    }

    @Test
    func recognisesOnlyTheClampThePreFixSamplerWrote() {
        // The 1:30:07 climb the pre-fix sampler clamped.
        #expect(LiveReplaySplitCurve.isPreFixSamplerClamp(stepCount: 360, intervalSeconds: 10, finalDurationSeconds: 5_407))
        // The same curve for a climb that ended inside its last window is honest.
        #expect(!LiveReplaySplitCurve.isPreFixSamplerClamp(stepCount: 360, intervalSeconds: 10, finalDurationSeconds: 3_599))
        // A compacted curve always runs past its finish.
        #expect(!LiveReplaySplitCurve.isPreFixSamplerClamp(stepCount: 271, intervalSeconds: 20, finalDurationSeconds: 5_407))
    }
}
