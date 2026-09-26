import Foundation

/// Bucket-indexed cumulative step curve for a live session, and the one place the bucket
/// contract is stated.
///
/// `steps[i]` is the latest cumulative step count sampled anywhere inside
/// `[i * intervalSeconds, (i + 1) * intervalSeconds)`, and is interpreted at that window's
/// **end**: index `i` sits at `(i + 1) * intervalSeconds` on a time axis. There is no leading
/// zero-steps entry - index 0 already carries the first interval's progress.
///
/// The interval is whatever the sampler ended on: 10 seconds for a climb inside an hour, doubled
/// each time the curve fills (`LiveReplaySplitSampler`), so every consumer reads it from the curve
/// and never assumes 10.
///
/// Summary display, Best Efforts segment math, and the server's `normalizeReplaySplitSteps`
/// all depend on this same end anchoring. Re-basing the buckets on one side only
/// silently desynchronizes the others rather than failing loudly, which is why the two
/// normalizers are pinned together by
/// `SharedTestVectors/live-replay-split-normalization-vector.json`.
struct LiveReplaySplitCurve: Codable, Equatable, Sendable {
    /// The pre-fix sampler (1.0 through 1.1) held 360 checkpoints at 10 seconds and clamped every
    /// later sample into the last one, so a curve it wrote for a climb past the hour carries the
    /// finish in bucket 359 and nothing about the climb after 59:50. Those curves are still
    /// stored on devices and in backups, and old builds keep writing them.
    static let preFixSamplerCheckpoints = 360
    static let preFixSamplerIntervalSeconds = 10

    let intervalSeconds: Int
    let steps: [Int]

    var latestBucketIndex: Int {
        max(steps.count - 1, 0)
    }

    /// Whether a stored curve is the pre-fix sampler's clamp: its full 360 checkpoints at the only
    /// interval it ever wrote, 10 seconds, with the last window closing no later than the finish.
    /// The current sampler compacts before a sample could land past its last checkpoint, so a
    /// 10-second curve it wrote always runs past the finish. A compacted curve can end before the
    /// finish (a recovered draft, or steps that stopped before the timer), but its last bucket is
    /// still a real sample, so the interval rules it out.
    static func isPreFixSamplerClamp(
        stepCount: Int,
        intervalSeconds: Int,
        finalDurationSeconds: Int
    ) -> Bool {
        stepCount == preFixSamplerCheckpoints
            && intervalSeconds == preFixSamplerIntervalSeconds
            && stepCount * max(intervalSeconds, 1) <= finalDurationSeconds
    }
}

/// Samples a live session into a `LiveReplaySplitCurve` of at most `maxCheckpoints` buckets,
/// however long the session runs.
///
/// A sample that would land past the last checkpoint doubles the interval and merges each pair
/// of buckets into one, rather than being clamped into the last bucket. A climb inside an hour
/// therefore records exactly as it always has - 10-second buckets - and a ten-hour climb records
/// at 160 seconds, keeping the backup document's `sourceMetadata` inside its fixed budget. The
/// board a live race reads is published on its own 10-second grid by the server, which resamples
/// whatever interval a curve arrives at.
struct LiveReplaySplitSampler: Equatable, Sendable {
    static let defaultIntervalSeconds = 10
    static let defaultMaxCheckpoints = 360

    /// The interval a fresh session starts at, and returns to on `reset()`.
    let baseIntervalSeconds: Int
    let maxCheckpoints: Int

    private(set) var intervalSeconds: Int
    private(set) var checkpointSteps: [Int] = []

    init(
        intervalSeconds: Int = Self.defaultIntervalSeconds,
        maxCheckpoints: Int = Self.defaultMaxCheckpoints
    ) {
        self.baseIntervalSeconds = max(intervalSeconds, 1)
        // Two checkpoints is the least a merge can halve and still leave room for the next.
        self.maxCheckpoints = max(maxCheckpoints, 2)
        self.intervalSeconds = baseIntervalSeconds
    }

    /// Resumes sampling a persisted curve at the interval it was recorded at, so an interrupted
    /// session picks up where it stopped instead of re-bucketing what it already holds.
    init(
        restoring curve: LiveReplaySplitCurve,
        baseIntervalSeconds: Int = Self.defaultIntervalSeconds,
        maxCheckpoints: Int = Self.defaultMaxCheckpoints
    ) {
        self.init(intervalSeconds: baseIntervalSeconds, maxCheckpoints: maxCheckpoints)
        intervalSeconds = max(curve.intervalSeconds, 1)
        checkpointSteps = curve.steps.map { max($0, 0) }
        while checkpointSteps.count > self.maxCheckpoints {
            compact()
        }
    }

    var latestBucketIndex: Int {
        max(checkpointSteps.count - 1, 0)
    }

    mutating func record(elapsedSeconds: Int, steps: Int) -> LiveReplaySplitCurve {
        let elapsedSeconds = max(elapsedSeconds, 0)
        while elapsedSeconds / intervalSeconds >= maxCheckpoints {
            compact()
        }

        let bucketIndex = elapsedSeconds / intervalSeconds
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
        intervalSeconds = baseIntervalSeconds
        checkpointSteps.removeAll(keepingCapacity: true)
    }

    var curve: LiveReplaySplitCurve {
        LiveReplaySplitCurve(
            intervalSeconds: intervalSeconds,
            steps: checkpointSteps
        )
    }

    /// Doubles the interval. Bucket `j` of the new curve spans old buckets `2j` and `2j + 1`, and
    /// its latest sample is the later bucket's - the larger, since a bucket never moves backward.
    private mutating func compact() {
        checkpointSteps = stride(from: 0, to: checkpointSteps.count, by: 2).map { index in
            max(
                checkpointSteps[index],
                index + 1 < checkpointSteps.count ? checkpointSteps[index + 1] : 0
            )
        }
        intervalSeconds *= 2
    }
}
