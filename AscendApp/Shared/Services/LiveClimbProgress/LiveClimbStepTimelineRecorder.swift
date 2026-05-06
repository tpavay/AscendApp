import Foundation

enum LiveClimbStepSource: String, Codable, Sendable {
    case headphoneMotion = "headphone_motion"
    case externalWearable = "external_wearable"
    case debugFixture = "debug_fixture"
    case unknown = "unknown"
}

struct LiveClimbStepSample: Equatable, Sendable {
    let elapsedSeconds: Int
    let cumulativeSteps: Int
    let source: LiveClimbStepSource

    init(
        elapsedSeconds: Int,
        cumulativeSteps: Int,
        source: LiveClimbStepSource
    ) {
        self.elapsedSeconds = max(elapsedSeconds, 0)
        self.cumulativeSteps = max(cumulativeSteps, 0)
        self.source = source
    }
}

@MainActor
protocol LiveClimbStepSampleProducing: AnyObject {
    func setStepSampleHandler(_ handler: ((LiveClimbStepSample) -> Void)?)
}

struct LiveClimbStepTimelineRecorder: Equatable, Sendable {
    private var splitSampler: LiveReplaySplitSampler

    init(intervalSeconds: Int = 10, maxCheckpoints: Int = 360) {
        self.splitSampler = LiveReplaySplitSampler(
            intervalSeconds: intervalSeconds,
            maxCheckpoints: maxCheckpoints
        )
    }

    var curve: LiveReplaySplitCurve {
        splitSampler.curve
    }

    mutating func reset() {
        splitSampler.reset()
    }

    @discardableResult
    mutating func record(_ sample: LiveClimbStepSample) -> LiveReplaySplitCurve {
        splitSampler.record(
            elapsedSeconds: sample.elapsedSeconds,
            steps: sample.cumulativeSteps
        )
    }

    @discardableResult
    mutating func record(
        elapsedSeconds: Int,
        cumulativeSteps: Int,
        source: LiveClimbStepSource = .unknown
    ) -> LiveReplaySplitCurve {
        record(
            LiveClimbStepSample(
                elapsedSeconds: elapsedSeconds,
                cumulativeSteps: cumulativeSteps,
                source: source
            )
        )
    }
}
