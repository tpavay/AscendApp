import Foundation

enum LiveClimbStepSource: String, Codable, Sendable {
    case headphoneMotion = "headphone_motion"
    case manualCorrection = "manual_correction"
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

    mutating func restore(curve: LiveReplaySplitCurve) {
        splitSampler.reset()

        for (bucketIndex, steps) in curve.steps.enumerated() {
            record(
                elapsedSeconds: bucketIndex * curve.intervalSeconds,
                cumulativeSteps: steps,
                source: .unknown
            )
        }
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

    @discardableResult
    mutating func recordCorrection(_ correction: HeadphoneMotionStepCorrection) -> LiveReplaySplitCurve {
        if correction.deltaSteps < 0 {
            scaleExistingCurve(for: correction)
        } else if correction.deltaSteps > 0 {
            interpolateCorrectionGap(correction)
        }

        return record(
            elapsedSeconds: correction.elapsedSeconds,
            cumulativeSteps: correction.correctedSteps,
            source: .manualCorrection
        )
    }

    private mutating func interpolateCorrectionGap(_ correction: HeadphoneMotionStepCorrection) {
        let gapSeconds = max(Int(correction.trackingGapDurationSeconds.rounded()), 0)
        guard gapSeconds > 0 else { return }

        let startElapsedSeconds = max(correction.elapsedSeconds - gapSeconds, 0)
        let endElapsedSeconds = max(correction.elapsedSeconds, startElapsedSeconds)
        let elapsedSpan = max(endElapsedSeconds - startElapsedSeconds, 1)
        let startSteps = correction.detectedSteps
        let addedSteps = max(correction.deltaSteps, 0)
        guard addedSteps > 0 else { return }

        let intervalSeconds = splitSampler.intervalSeconds
        let startBucket = startElapsedSeconds / intervalSeconds
        let endBucket = endElapsedSeconds / intervalSeconds
        guard endBucket >= startBucket else { return }

        for bucket in startBucket...endBucket {
            let bucketElapsedSeconds = bucket * intervalSeconds
            guard bucketElapsedSeconds >= startElapsedSeconds,
                  bucketElapsedSeconds <= endElapsedSeconds else {
                continue
            }

            let progress = Double(bucketElapsedSeconds - startElapsedSeconds) / Double(elapsedSpan)
            let interpolatedSteps = startSteps + Int((Double(addedSteps) * progress).rounded())
            record(
                elapsedSeconds: bucketElapsedSeconds,
                cumulativeSteps: interpolatedSteps,
                source: .manualCorrection
            )
        }
    }

    private mutating func scaleExistingCurve(for correction: HeadphoneMotionStepCorrection) {
        let existingSteps = splitSampler.curve.steps
        guard !existingSteps.isEmpty,
              correction.detectedSteps > 0 else {
            return
        }

        let ratio = Double(correction.correctedSteps) / Double(correction.detectedSteps)
        splitSampler.reset()

        for (bucket, steps) in existingSteps.enumerated() {
            let scaledSteps = min(
                correction.correctedSteps,
                max(Int((Double(steps) * ratio).rounded()), 0)
            )
            record(
                elapsedSeconds: bucket * splitSampler.intervalSeconds,
                cumulativeSteps: scaledSteps,
                source: .manualCorrection
            )
        }
    }
}
