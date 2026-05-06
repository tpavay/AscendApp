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
}
