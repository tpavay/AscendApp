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

/**
 * The checkpoint cap of the pre-fix iOS sampler (1.0 through 1.1): 360
 * checkpoints at 10 seconds, with every later sample clamped into the last
 * bucket. A curve it wrote for a climb past 60 minutes therefore holds the
 * final step count in bucket 359 and nothing about the climb between 59:50 and
 * the finish. Every client still on those builds keeps writing that shape, so
 * it is repaired on read rather than rewritten. See `isPreFixSamplerClamp`.
 */
export const PRE_FIX_SAMPLER_CHECKPOINTS = 360;

/**
 * The live race's bucket grid. Every client, old and new, reads bucket
 * `floor(elapsed / 10)` on every board, so every attempt publishes onto this
 * grid whatever interval its curve was recorded at - the current sampler
 * doubles its interval past each 360th checkpoint instead of clamping.
 */
export const REPLAY_BOARD_INTERVAL_SECONDS = 10;

export interface NormalizeReplaySplitStepsInput {
  splitIntervalSeconds: number;
  splitSteps: number[];
  finalDurationSeconds: number;
  finalSteps: number;
}

/**
 * Normalizes a recorded split curve at its own interval.
 *
 * The iOS client should normally send a monotonic curve with steady progress.
 * This also repairs degenerate curves such as [0, 0, ..., finalSteps], which
 * can happen if live samples were not captured before the stop result, and a
 * curve the pre-fix sampler clamped at an hour (`isPreFixSamplerClamp`), whose
 * unrecorded tail runs straight from the last recorded bucket to the finish.
 *
 * The result runs through the finish at the input's interval, however long
 * the climb was. `replayBoardSplitSteps` is what a board publishes.
 * @param {NormalizeReplaySplitStepsInput} input Raw curve and final stats.
 * @return {number[]} Monotonic split steps at the input's interval.
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
  const splitSteps = isPreFixSamplerClamp(
    input.splitSteps.length,
    intervalSeconds,
    input.finalDurationSeconds
  ) ?
    withInterpolatedUnrecordedTail(
      input.splitSteps,
      intervalSeconds,
      input.finalDurationSeconds,
      finalSteps
    ) :
    input.splitSteps;
  const bucketCount = Math.max(
    splitSteps.length,
    expectedFinalBucketIndex + 1
  );
  const clampedSteps = monotonicClampedSteps(
    splitSteps,
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
 * The attempt's curve on the live race's grid (`REPLAY_BOARD_INTERVAL_SECONDS`)
 * - what its bucket entries publish and its stored attempt curve holds.
 *
 * A curve already on the grid is `normalizeReplaySplitSteps` exactly. A curve
 * the sampler compacted to a longer interval is read as the straight-line
 * polyline through its checkpoints and the finish, and sampled at the end of
 * every board bucket, so the rival moves through the race at the pace it was
 * recorded at rather than at a fraction of it.
 * @param {NormalizeReplaySplitStepsInput} input Raw curve and final stats.
 * @return {number[]} Monotonic split steps, bucket `j` at `(j + 1) * 10` s.
 */
export function replayBoardSplitSteps(
  input: NormalizeReplaySplitStepsInput
): number[] {
  const normalized = normalizeReplaySplitSteps(input);
  const intervalSeconds = Math.max(
    Math.floor(input.splitIntervalSeconds),
    1
  );
  if (intervalSeconds === REPLAY_BOARD_INTERVAL_SECONDS) {
    return normalized;
  }

  const finalSteps = Math.max(Math.floor(input.finalSteps), 0);
  const finishSeconds = Math.max(input.finalDurationSeconds, 0);
  const points = curvePolyline(
    normalized,
    intervalSeconds,
    finishSeconds,
    finalSteps
  );
  const finalBoardBucketIndex = Math.floor(
    finishSeconds / REPLAY_BOARD_INTERVAL_SECONDS
  );
  const boardSteps: number[] = [];
  let segment = 0;
  let lastStep = 0;

  for (let index = 0; index <= finalBoardBucketIndex; index += 1) {
    const seconds = (index + 1) * REPLAY_BOARD_INTERVAL_SECONDS;
    while (
      segment < points.length - 2 &&
      points[segment + 1].seconds < seconds
    ) {
      segment += 1;
    }
    const projectedStep = seconds >= finishSeconds ?
      finalSteps :
      Math.round(
        interpolatedSteps(points[segment], points[segment + 1], seconds)
      );
    lastStep = Math.min(Math.max(projectedStep, lastStep), finalSteps);
    boardSteps.push(lastStep);
  }

  return boardSteps;
}

/**
 * Whether a curve is the pre-fix sampler's clamp: its full 360 checkpoints,
 * with the last window closing no later than the finish. That sampler put
 * every sample from checkpoint 359 onward into bucket 359, so the bucket
 * holds the finish rather than the moment it is read at. The current sampler
 * compacts before a sample could land past its last checkpoint, so a curve it
 * wrote always runs past the finish instead.
 * @param {number} stepCount Checkpoints in the stored curve.
 * @param {number} intervalSeconds Stored interval.
 * @param {number} finalDurationSeconds Final duration.
 * @return {boolean} True when the last bucket cannot be trusted.
 */
export function isPreFixSamplerClamp(
  stepCount: number,
  intervalSeconds: number,
  finalDurationSeconds: number
): boolean {
  return stepCount === PRE_FIX_SAMPLER_CHECKPOINTS &&
    stepCount * Math.max(Math.floor(intervalSeconds), 1) <=
      finalDurationSeconds;
}

/**
 * A clamped curve with its last bucket dropped and the unrecorded time from
 * the last trusted bucket to the finish drawn as a straight line. The total
 * and the clock are the only evidence left about that stretch, so an even
 * pace between them is the most the curve can honestly say.
 * @param {number[]} splitSteps Clamped raw curve.
 * @param {number} intervalSeconds Stored interval.
 * @param {number} finalDurationSeconds Final duration.
 * @param {number} finalSteps Final steps.
 * @return {number[]} Curve through the finish bucket.
 */
function withInterpolatedUnrecordedTail(
  splitSteps: number[],
  intervalSeconds: number,
  finalDurationSeconds: number,
  finalSteps: number
): number[] {
  const steps = monotonicClampedSteps(
    splitSteps,
    splitSteps.length - 1,
    finalSteps
  );
  const anchorSeconds = steps.length * intervalSeconds;
  const anchorSteps = steps[steps.length - 1] ?? 0;
  const tailSeconds = Math.max(finalDurationSeconds - anchorSeconds, 1);
  const finalBucketIndex = Math.floor(finalDurationSeconds / intervalSeconds);

  for (let index = steps.length; index <= finalBucketIndex; index += 1) {
    const seconds = (index + 1) * intervalSeconds;
    const projectedStep = seconds >= finalDurationSeconds ?
      finalSteps :
      Math.round(
        anchorSteps +
          ((finalSteps - anchorSteps) * (seconds - anchorSeconds)) /
            tailSeconds
      );
    steps.push(Math.min(Math.max(projectedStep, anchorSteps), finalSteps));
  }

  return steps;
}

/** One point on a curve's time axis. */
interface CurvePolylinePoint {
  seconds: number;
  steps: number;
}

/**
 * A normalized curve as points from the start to the finish, dropping any
 * checkpoint read at or past the finish clock.
 * @param {number[]} steps Normalized curve.
 * @param {number} intervalSeconds Its interval.
 * @param {number} finishSeconds Final duration.
 * @param {number} finalSteps Final steps.
 * @return {CurvePolylinePoint[]} Points strictly increasing in time.
 */
function curvePolyline(
  steps: number[],
  intervalSeconds: number,
  finishSeconds: number,
  finalSteps: number
): CurvePolylinePoint[] {
  const points: CurvePolylinePoint[] = [{seconds: 0, steps: 0}];

  for (let index = 0; index < steps.length; index += 1) {
    const seconds = (index + 1) * intervalSeconds;
    if (seconds >= finishSeconds) {
      break;
    }
    points.push({seconds, steps: steps[index]});
  }

  points.push({seconds: finishSeconds, steps: finalSteps});
  return points;
}

/**
 * Linear interpolation between two points on the time axis.
 * @param {CurvePolylinePoint} from Earlier point.
 * @param {CurvePolylinePoint} to Later point.
 * @param {number} seconds Moment between them.
 * @return {number} Steps at that moment.
 */
function interpolatedSteps(
  from: CurvePolylinePoint,
  to: CurvePolylinePoint,
  seconds: number
): number {
  if (to.seconds <= from.seconds) {
    return to.steps;
  }
  const fraction = Math.min(
    Math.max((seconds - from.seconds) / (to.seconds - from.seconds), 0),
    1
  );
  return from.steps + (to.steps - from.steps) * fraction;
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
