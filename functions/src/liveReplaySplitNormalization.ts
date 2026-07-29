/*
 * Split curves are bucket-indexed, and every producer and consumer must agree
 * on the same anchoring:
 * `splitSteps[i]` is the latest cumulative step count sampled anywhere inside
 * `[i * splitIntervalSeconds, (i + 1) * splitIntervalSeconds)`, and is
 * interpreted at that window's *end* - index `i` sits at
 * `(i + 1) * splitIntervalSeconds` on a time axis. There is no leading
 * zero-steps entry; index 0 already carries the first interval's progress.
 *
 * The iOS producer (`LiveReplaySplitCurve`, which owns the full statement of
 * this contract), the workout summary chart, Best Efforts segment math, and the
 * replay bucket entries written from this output all assume that same end
 * anchoring. Re-basing buckets here alone silently desynchronizes the others
 * rather than failing loudly, so this module is pinned against the iOS twin
 * (`LiveClimbWorkoutSummaryData.normalizedSplitSteps`) by
 * `SharedTestVectors/live-replay-split-normalization-vector.json`.
 */

export const MAX_REPLAY_SPLIT_CHECKPOINTS = 360;

export interface NormalizeReplaySplitStepsInput {
  splitIntervalSeconds: number;
  splitSteps: number[];
  finalDurationSeconds: number;
  finalSteps: number;
}

/**
 * Normalizes replay split curves before they are published into public buckets.
 *
 * The iOS client should normally send a monotonic curve with steady progress.
 * This also repairs degenerate curves such as [0, 0, ..., finalSteps], which
 * can happen if live samples were not captured before the stop result.
 * @param {NormalizeReplaySplitStepsInput} input Raw curve and final stats.
 * @return {number[]} Monotonic split steps suitable for replay bucket entries.
 */
export function normalizeReplaySplitSteps(
  input: NormalizeReplaySplitStepsInput
): number[] {
  const finalSteps = Math.max(Math.floor(input.finalSteps), 0);
  const intervalSeconds = Math.max(
    Math.floor(input.splitIntervalSeconds),
    1
  );
  const expectedFinalBucketIndex = Math.max(
    Math.floor(input.finalDurationSeconds / intervalSeconds),
    0
  );
  const bucketCount = Math.min(
    Math.max(input.splitSteps.length, expectedFinalBucketIndex + 1),
    MAX_REPLAY_SPLIT_CHECKPOINTS
  );
  const clampedSteps = monotonicClampedSteps(
    input.splitSteps,
    bucketCount,
    finalSteps
  );

  if (
    shouldReconstructCurve(
      clampedSteps,
      expectedFinalBucketIndex,
      intervalSeconds,
      input.finalDurationSeconds,
      finalSteps
    )
  ) {
    const reconstructedSteps = reconstructedLinearCurve(
      bucketCount,
      intervalSeconds,
      input.finalDurationSeconds,
      finalSteps
    );
    if (expectedFinalBucketIndex < reconstructedSteps.length) {
      reconstructedSteps[expectedFinalBucketIndex] = finalSteps;
    }
    return reconstructedSteps;
  }

  if (expectedFinalBucketIndex < clampedSteps.length) {
    clampedSteps[expectedFinalBucketIndex] = Math.max(
      clampedSteps[expectedFinalBucketIndex],
      finalSteps
    );
  }

  return clampedSteps;
}

/**
 * Returns a monotonic, non-negative split list with missing buckets filled.
 * @param {number[]} splitSteps Raw split steps.
 * @param {number} bucketCount Desired output bucket count.
 * @param {number} finalSteps Final step cap.
 * @return {number[]} Clamped monotonic split steps.
 */
function monotonicClampedSteps(
  splitSteps: number[],
  bucketCount: number,
  finalSteps: number
): number[] {
  const steps: number[] = [];
  let lastStep = 0;

  for (let index = 0; index < bucketCount; index += 1) {
    const rawStep = splitSteps[index] ?? lastStep;
    const parsedStep = Number.isFinite(rawStep) ?
      Math.floor(rawStep) :
      lastStep;
    lastStep = Math.min(Math.max(parsedStep, lastStep, 0), finalSteps);
    steps.push(lastStep);
  }

  return steps;
}

/**
 * Returns true when the curve has no useful progress before completion.
 * @param {number[]} steps Monotonic split steps.
 * @param {number} expectedFinalBucketIndex Final duration bucket index.
 * @param {number} intervalSeconds Split interval.
 * @param {number} finalDurationSeconds Final duration.
 * @param {number} finalSteps Final step count.
 * @return {boolean} Whether a linear reconstruction is safer than raw data.
 */
function shouldReconstructCurve(
  steps: number[],
  expectedFinalBucketIndex: number,
  intervalSeconds: number,
  finalDurationSeconds: number,
  finalSteps: number
): boolean {
  if (
    finalSteps <= 0 ||
    finalDurationSeconds < intervalSeconds * 2 ||
    steps.length < 3
  ) {
    return false;
  }

  const finalBucketIndex = Math.min(
    expectedFinalBucketIndex,
    steps.length - 1
  );
  const stepsBeforeFinalBucket = steps.slice(0, finalBucketIndex);
  const hasIntermediateProgress = stepsBeforeFinalBucket.some((step) => {
    return step > 0 && step < finalSteps;
  });

  return !hasIntermediateProgress && steps[finalBucketIndex] >= finalSteps;
}

/**
 * Builds a conservative linear curve from final duration and final steps.
 * @param {number} bucketCount Number of buckets to emit.
 * @param {number} intervalSeconds Split interval.
 * @param {number} finalDurationSeconds Final duration.
 * @param {number} finalSteps Final step count.
 * @return {number[]} Reconstructed monotonic curve.
 */
function reconstructedLinearCurve(
  bucketCount: number,
  intervalSeconds: number,
  finalDurationSeconds: number,
  finalSteps: number
): number[] {
  const safeDurationSeconds = Math.max(finalDurationSeconds, 1);
  const steps: number[] = [];
  let lastStep = 0;

  for (let index = 0; index < bucketCount; index += 1) {
    // Bucket `index` is read at the end of its window, so it projects the
    // progress reached by `(index + 1) * intervalSeconds`.
    const elapsedSeconds = (index + 1) * intervalSeconds;
    const progress = Math.min(elapsedSeconds / safeDurationSeconds, 1);
    const projectedStep = elapsedSeconds >= safeDurationSeconds ?
      finalSteps :
      Math.round(finalSteps * progress);
    lastStep = Math.min(Math.max(projectedStep, lastStep), finalSteps);
    steps.push(lastStep);
  }

  return steps;
}
