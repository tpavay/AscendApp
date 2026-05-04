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
}
