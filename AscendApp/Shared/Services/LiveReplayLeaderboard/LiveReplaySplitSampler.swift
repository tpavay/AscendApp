import Foundation

/// Bucket-indexed cumulative step curve for a live session, and the one place the bucket
/// contract is stated.
///
/// `steps[i]` is the latest cumulative step count sampled anywhere inside
/// `[i * intervalSeconds, (i + 1) * intervalSeconds)`, and is interpreted at that window's
/// **end**: index `i` sits at `(i + 1) * intervalSeconds` on a time axis. There is no leading
/// zero-steps entry - index 0 already carries the first interval's progress.
///
/// Summary display, Best Efforts segment math, and the server's `normalizeReplaySplitSteps`
/// all depend on this same end anchoring. Re-basing the buckets on one side only
/// silently desynchronizes the others rather than failing loudly, which is why the two
/// normalizers are pinned together by
/// `SharedTestVectors/live-replay-split-normalization-vector.json`.
struct LiveReplaySplitCurve: Codable, Equatable, Sendable {
    let intervalSeconds: Int
    let steps: [Int]

    var latestBucketIndex: Int {
        max(steps.count - 1, 0)
    }
}

struct LiveReplaySplitSampler: Equatable, Sendable {
    let intervalSeconds: Int
    let maxCheckpoints: Int

    private(set) var checkpointSteps: [Int] = []

    init(intervalSeconds: Int = 10, maxCheckpoints: Int = 360) {
        self.intervalSeconds = max(intervalSeconds, 1)
        self.maxCheckpoints = max(maxCheckpoints, 1)
    }

    var latestBucketIndex: Int {
        max(checkpointSteps.count - 1, 0)
    }

    mutating func record(elapsedSeconds: Int, steps: Int) -> LiveReplaySplitCurve {
        let bucketIndex = min(max(elapsedSeconds, 0) / intervalSeconds, maxCheckpoints - 1)
        let normalizedSteps = max(steps, 0)
        let lastRecordedSteps = checkpointSteps.last ?? 0

        while checkpointSteps.count < bucketIndex {
            checkpointSteps.append(lastRecordedSteps)
        }

        if checkpointSteps.count == bucketIndex {
            checkpointSteps.append(normalizedSteps)
        } else {
            checkpointSteps[bucketIndex] = max(checkpointSteps[bucketIndex], normalizedSteps)
        }

        return curve
    }

    mutating func reset() {
        checkpointSteps.removeAll(keepingCapacity: true)
    }

    var curve: LiveReplaySplitCurve {
        LiveReplaySplitCurve(
            intervalSeconds: intervalSeconds,
            steps: checkpointSteps
        )
    }
}
