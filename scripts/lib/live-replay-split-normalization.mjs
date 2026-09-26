/**
 * The scripts' mirror of `functions/src/liveReplaySplitNormalization.ts`: how a
 * stored split curve becomes the curve an attempt publishes onto a Live Replay
 * board.
 *
 * A backfill that rewrites bucket entries has to write exactly what the
 * trigger would, so this module repeats the Cloud Function's rules rather than
 * approximating them, and `scripts/test/live-replay-split-normalization.test.mjs`
 * pins it to `SharedTestVectors/live-replay-split-normalization-vector.json`,
 * the same vector the function and the iOS twin read.
 *
 * `splitSteps[i]` is the latest cumulative step count sampled inside
 * `[i * interval, (i + 1) * interval)` and is read at that window's end.
 */

/**
 * The pre-fix iOS sampler's checkpoint cap (1.0 through 1.1): 360 checkpoints
 * at 10 seconds, every later sample clamped into the last one.
 */
export const PRE_FIX_SAMPLER_CHECKPOINTS = 360;

/** The only interval the pre-fix iOS sampler ever wrote. */
export const PRE_FIX_SAMPLER_INTERVAL_SECONDS = 10;

/** The live race's bucket grid: every client reads `floor(elapsed / 10)`. */
export const REPLAY_BOARD_INTERVAL_SECONDS = 10;

/**
 * Normalizes a recorded split curve at its own interval, through the finish.
 * @param {{splitIntervalSeconds: number, splitSteps: number[],
 *   finalDurationSeconds: number, finalSteps: number}} input Raw curve.
 * @return {number[]} Monotonic split steps at the input's interval.
 */
export function normalizeReplaySplitSteps(input) {
  const finalSteps = Math.max(Math.floor(input.finalSteps), 0);
  const intervalSeconds = Math.max(Math.floor(input.splitIntervalSeconds), 1);
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
  const bucketCount = Math.max(splitSteps.length, expectedFinalBucketIndex + 1);
  const clampedSteps = monotonicClampedSteps(splitSteps, bucketCount, finalSteps);

  if (shouldReconstructCurve(
    clampedSteps,
    expectedFinalBucketIndex,
    intervalSeconds,
    input.finalDurationSeconds,
    finalSteps
  )) {
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
 * The attempt's curve on the live race's 10-second grid - what its bucket
 * entries publish and its stored attempt curve holds.
 * @param {{splitIntervalSeconds: number, splitSteps: number[],
 *   finalDurationSeconds: number, finalSteps: number}} input Raw curve.
 * @return {number[]} Monotonic split steps, bucket `j` at `(j + 1) * 10` s.
 */
export function replayBoardSplitSteps(input) {
  const normalized = normalizeReplaySplitSteps(input);
  const intervalSeconds = Math.max(Math.floor(input.splitIntervalSeconds), 1);
  if (intervalSeconds === REPLAY_BOARD_INTERVAL_SECONDS) {
    return normalized;
  }

  const finalSteps = Math.max(Math.floor(input.finalSteps), 0);
  const finishSeconds = Math.max(input.finalDurationSeconds, 0);
  const points = curvePolyline(normalized, intervalSeconds, finishSeconds, finalSteps);
  const finalBoardBucketIndex = Math.floor(finishSeconds / REPLAY_BOARD_INTERVAL_SECONDS);
  const boardSteps = [];
  let segment = 0;
  let lastStep = 0;

  for (let index = 0; index <= finalBoardBucketIndex; index += 1) {
    const seconds = (index + 1) * REPLAY_BOARD_INTERVAL_SECONDS;
    while (segment < points.length - 2 && points[segment + 1].seconds < seconds) {
      segment += 1;
    }
    const projectedStep = seconds >= finishSeconds ?
      finalSteps :
      Math.round(interpolatedSteps(points[segment], points[segment + 1], seconds));
    lastStep = Math.min(Math.max(projectedStep, lastStep), finalSteps);
    boardSteps.push(lastStep);
  }

  return boardSteps;
}

/**
 * Whether a curve is the pre-fix sampler's clamp: its full 360 checkpoints
 * at the only interval it ever wrote, 10 seconds, with the last window closing
 * no later than the finish. A compacted curve can end before the finish, but
 * its last bucket is still a real sample, so the interval rules it out.
 * @param {number} stepCount Checkpoints in the stored curve.
 * @param {number} intervalSeconds Stored interval.
 * @param {number} finalDurationSeconds Final duration.
 * @return {boolean} True when the last bucket cannot be trusted.
 */
export function isPreFixSamplerClamp(stepCount, intervalSeconds, finalDurationSeconds) {
  return stepCount === PRE_FIX_SAMPLER_CHECKPOINTS &&
    intervalSeconds === PRE_FIX_SAMPLER_INTERVAL_SECONDS &&
    stepCount * Math.max(Math.floor(intervalSeconds), 1) <= finalDurationSeconds;
}

function withInterpolatedUnrecordedTail(splitSteps, intervalSeconds, finalDurationSeconds, finalSteps) {
  const steps = monotonicClampedSteps(splitSteps, splitSteps.length - 1, finalSteps);
  const anchorSeconds = steps.length * intervalSeconds;
  const anchorSteps = steps[steps.length - 1] ?? 0;
  const tailSeconds = Math.max(finalDurationSeconds - anchorSeconds, 1);
  const finalBucketIndex = Math.floor(finalDurationSeconds / intervalSeconds);

  for (let index = steps.length; index <= finalBucketIndex; index += 1) {
    const seconds = (index + 1) * intervalSeconds;
    const projectedStep = seconds >= finalDurationSeconds ?
      finalSteps :
      Math.round(
        anchorSteps + ((finalSteps - anchorSteps) * (seconds - anchorSeconds)) / tailSeconds
      );
    steps.push(Math.min(Math.max(projectedStep, anchorSteps), finalSteps));
  }

  return steps;
}

function monotonicClampedSteps(splitSteps, bucketCount, finalSteps) {
  const steps = [];
  let lastStep = 0;

  for (let index = 0; index < bucketCount; index += 1) {
    const rawStep = splitSteps[index] ?? lastStep;
    const parsedStep = Number.isFinite(rawStep) ? Math.floor(rawStep) : lastStep;
    lastStep = Math.min(Math.max(parsedStep, lastStep, 0), finalSteps);
    steps.push(lastStep);
  }

  return steps;
}

function shouldReconstructCurve(steps, expectedFinalBucketIndex, intervalSeconds, finalDurationSeconds, finalSteps) {
  if (finalSteps <= 0 || finalDurationSeconds < intervalSeconds * 2 || steps.length < 3) {
    return false;
  }

  const finalBucketIndex = Math.min(expectedFinalBucketIndex, steps.length - 1);
  const hasIntermediateProgress = steps.slice(0, finalBucketIndex).some((step) => {
    return step > 0 && step < finalSteps;
  });

  return !hasIntermediateProgress && steps[finalBucketIndex] >= finalSteps;
}

function reconstructedLinearCurve(bucketCount, intervalSeconds, finalDurationSeconds, finalSteps) {
  const safeDurationSeconds = Math.max(finalDurationSeconds, 1);
  const steps = [];
  let lastStep = 0;

  for (let index = 0; index < bucketCount; index += 1) {
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

function curvePolyline(steps, intervalSeconds, finishSeconds, finalSteps) {
  const points = [{seconds: 0, steps: 0}];
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

function interpolatedSteps(from, to, seconds) {
  if (to.seconds <= from.seconds) {
    return to.steps;
  }
  const fraction = Math.min(Math.max((seconds - from.seconds) / (to.seconds - from.seconds), 0), 1);
  return from.steps + (to.steps - from.steps) * fraction;
}
