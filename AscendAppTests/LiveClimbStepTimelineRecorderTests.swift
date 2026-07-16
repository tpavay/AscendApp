import Testing
@testable import AscendApp

struct LiveClimbStepTimelineRecorderTests {
    @Test
    func recordsCumulativeStepsIntoFixedBuckets() {
        var recorder = LiveClimbStepTimelineRecorder(intervalSeconds: 10)

        recorder.record(
            LiveClimbStepSample(
                elapsedSeconds: 0,
                cumulativeSteps: 0,
                source: .debugFixture
            )
        )
        recorder.record(
            LiveClimbStepSample(
                elapsedSeconds: 11,
                cumulativeSteps: 24,
                source: .debugFixture
            )
        )
        recorder.record(
            LiveClimbStepSample(
                elapsedSeconds: 27,
                cumulativeSteps: 71,
                source: .debugFixture
            )
        )

        #expect(recorder.curve.intervalSeconds == 10)
        #expect(recorder.curve.steps == [0, 24, 71])
    }

    @Test
    func keepsHighestStepCountWithinABucket() {
        var recorder = LiveClimbStepTimelineRecorder(intervalSeconds: 10)

        recorder.record(elapsedSeconds: 15, cumulativeSteps: 40, source: .debugFixture)
        recorder.record(elapsedSeconds: 19, cumulativeSteps: 55, source: .debugFixture)
        recorder.record(elapsedSeconds: 18, cumulativeSteps: 50, source: .debugFixture)

        #expect(recorder.curve.steps == [0, 55])
    }

    @Test
    func interpolatesPositiveStepCorrectionAcrossGap() {
        var recorder = LiveClimbStepTimelineRecorder(intervalSeconds: 10)

        recorder.record(elapsedSeconds: 20, cumulativeSteps: 40, source: .headphoneMotion)
        recorder.recordCorrection(
            HeadphoneMotionStepCorrection(
                elapsedSeconds: 50,
                detectedSteps: 40,
                correctedSteps: 100,
                deltaSteps: 60,
                trackingGapDurationSeconds: 30,
                totalUnavailableDurationSeconds: 30,
                interruptionCount: 1
            )
        )

        #expect(recorder.curve.steps == [0, 0, 40, 60, 80, 100])
    }

    @Test
    func scalesExistingSplitsWhenCorrectionMovesStepsDown() {
        var recorder = LiveClimbStepTimelineRecorder(intervalSeconds: 10)

        recorder.record(elapsedSeconds: 0, cumulativeSteps: 0, source: .headphoneMotion)
        recorder.record(elapsedSeconds: 10, cumulativeSteps: 100, source: .headphoneMotion)
        recorder.record(elapsedSeconds: 20, cumulativeSteps: 200, source: .headphoneMotion)
        recorder.recordCorrection(
            HeadphoneMotionStepCorrection(
                elapsedSeconds: 30,
                detectedSteps: 200,
                correctedSteps: 100,
                deltaSteps: -100,
                trackingGapDurationSeconds: 10,
                totalUnavailableDurationSeconds: 10,
                interruptionCount: 1
            )
        )

        #expect(recorder.curve.steps == [0, 50, 100, 100])
    }
}
