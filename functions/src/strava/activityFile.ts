/**
 * Turns one canonical Ascend climb into what Strava receives: a TCX file, a
 * title, and a description.
 *
 * Everything here is derived on the server from `users/{uid}/workouts` and
 * its heart-rate sidecar, never from a file the app sends, so the only thing
 * that can reach a climber's Strava is a climb Ascend itself recorded.
 */

export interface StravaActivityWorkout {
  workoutId: string;
  name: string;
  startedAtMillis: number;
  durationSeconds: number;
  steps: number;
  floors: number;
  notes: string;
  caloriesBurned: number | null;
  avgHeartRateBpm: number | null;
  maxHeartRateBpm: number | null;
}

export interface HeartRateSample {
  timestampMillis: number;
  bpm: number;
}

/**
 * Seconds between the Unix epoch and 2001-01-01, the reference date Swift's
 * default JSONEncoder writes a `Date` against. The heart-rate sidecar is
 * encoded that way (`WorkoutHeartRateStorageRepository`).
 */
export const APPLE_REFERENCE_DATE_OFFSET_SECONDS = 978_307_200;

const MIN_PLAUSIBLE_BPM = 25;
const MAX_PLAUSIBLE_BPM = 250;
// A live recorder's first sample can land a moment before the climb's own
// start, and a watch can flush one just after it ends.
const SAMPLE_WINDOW_SLACK_MS = 60 * 1000;
const MAX_TITLE_LENGTH = 120;
const DEFAULT_TITLE = "Stair climb";

/**
 * Decodes the gunzipped heart-rate sidecar into samples inside the climb.
 *
 * The sidecar is best-effort enrichment, so an unreadable one yields no
 * samples rather than failing the upload.
 * @param {string} json The sidecar's JSON text.
 * @param {StravaActivityWorkout} workout The climb it belongs to.
 * @return {Array<HeartRateSample>} Plausible samples, oldest first.
 */
export function parseHeartRateSidecar(
  json: string,
  workout: StravaActivityWorkout
): HeartRateSample[] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(json);
  } catch {
    return [];
  }
  const samples = (parsed as {samples?: unknown})?.samples;
  if (!Array.isArray(samples)) {
    return [];
  }
  const windowStart = workout.startedAtMillis - SAMPLE_WINDOW_SLACK_MS;
  const windowEnd = workout.startedAtMillis +
    workout.durationSeconds * 1000 + SAMPLE_WINDOW_SLACK_MS;
  const result: HeartRateSample[] = [];
  for (const sample of samples) {
    const timestamp = (sample as {timestamp?: unknown})?.timestamp;
    const heartRate = (sample as {heartRate?: unknown})?.heartRate;
    if (typeof timestamp !== "number" || !Number.isFinite(timestamp) ||
      typeof heartRate !== "number" || !Number.isFinite(heartRate)) {
      continue;
    }
    const timestampMillis = Math.round(
      (timestamp + APPLE_REFERENCE_DATE_OFFSET_SECONDS) * 1000
    );
    const bpm = Math.round(heartRate);
    if (timestampMillis < windowStart || timestampMillis > windowEnd ||
      bpm < MIN_PLAUSIBLE_BPM || bpm > MAX_PLAUSIBLE_BPM) {
      continue;
    }
    result.push({timestampMillis, bpm});
  }
  return result.sort((a, b) => a.timestampMillis - b.timestampMillis);
}

/**
 * Builds the TCX document for one climb.
 *
 * Strava requires a time on every trackpoint and nothing else, so a climb
 * with no heart rate still gets a start and an end point. Distance is zero on
 * purpose: a stair stepper covers no ground, and reporting climbed height as
 * distance would put a false number on the athlete's Strava totals.
 * @param {StravaActivityWorkout} workout The climb.
 * @param {Array<HeartRateSample>} samples Its heart-rate series.
 * @return {string} TCX XML.
 */
export function buildTcx(
  workout: StravaActivityWorkout,
  samples: HeartRateSample[]
): string {
  const start = isoTime(workout.startedAtMillis);
  const endMillis = workout.startedAtMillis +
    Math.round(workout.durationSeconds * 1000);
  const lapSummary: string[] = [
    `<TotalTimeSeconds>${Math.round(workout.durationSeconds)}` +
      "</TotalTimeSeconds>",
    "<DistanceMeters>0</DistanceMeters>",
  ];
  // The TCX schema fixes this order, and Calories is required.
  lapSummary.push(
    `<Calories>${Math.max(0, Math.round(workout.caloriesBurned ?? 0))}` +
      "</Calories>"
  );
  if (workout.avgHeartRateBpm !== null) {
    lapSummary.push(
      "<AverageHeartRateBpm><Value>" +
        `${Math.round(workout.avgHeartRateBpm)}</Value></AverageHeartRateBpm>`
    );
  }
  if (workout.maxHeartRateBpm !== null) {
    lapSummary.push(
      "<MaximumHeartRateBpm><Value>" +
        `${Math.round(workout.maxHeartRateBpm)}</Value></MaximumHeartRateBpm>`
    );
  }
  lapSummary.push("<Intensity>Active</Intensity>");
  lapSummary.push("<TriggerMethod>Manual</TriggerMethod>");

  const trackpoints = samples.length > 0 ?
    samples.map((sample) => trackpoint(sample.timestampMillis, sample.bpm)) :
    [
      trackpoint(workout.startedAtMillis, workout.avgHeartRateBpm),
      trackpoint(endMillis, workout.avgHeartRateBpm),
    ];

  return [
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
    "<TrainingCenterDatabase " +
      "xmlns=\"http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2\">",
    "<Activities>",
    "<Activity Sport=\"Other\">",
    `<Id>${start}</Id>`,
    `<Lap StartTime="${start}">`,
    ...lapSummary,
    "<Track>",
    ...trackpoints,
    "</Track>",
    "</Lap>",
    "</Activity>",
    "</Activities>",
    "</TrainingCenterDatabase>",
    "",
  ].join("\n");
}

/**
 * The Strava activity title: the climb's own name.
 * @param {StravaActivityWorkout} workout The climb.
 * @return {string} A non-empty title.
 */
export function buildStravaTitle(workout: StravaActivityWorkout): string {
  const name = workout.name.trim();
  if (!name) {
    return DEFAULT_TITLE;
  }
  return name.length > MAX_TITLE_LENGTH ?
    name.slice(0, MAX_TITLE_LENGTH).trimEnd() :
    name;
}

/**
 * The Strava activity description: the climb's numbers, the climber's own
 * notes, then where it was climbed.
 * @param {StravaActivityWorkout} workout The climb.
 * @return {string} Description text.
 */
export function buildStravaDescription(
  workout: StravaActivityWorkout
): string {
  const lines = [
    `${formatCount(workout.steps)} steps · ` +
      `${formatCount(workout.floors)} floors`,
  ];
  const minutes = workout.durationSeconds / 60;
  if (minutes > 0 && workout.steps > 0) {
    lines.push(`${Math.round(workout.steps / minutes)} steps/min`);
  }
  const notes = workout.notes.trim();
  if (notes) {
    lines.push("", notes);
  }
  lines.push("", "Climbed in Ascend");
  return lines.join("\n");
}

/**
 * Strava's `external_id` for a climb. Stable per climb, so a retried upload
 * is recognisable as the same activity.
 * @param {string} workoutId Canonical workout id.
 * @return {string} External id.
 */
export function stravaExternalId(workoutId: string): string {
  return `ascend-${workoutId}`;
}

/**
 * One TCX trackpoint.
 * @param {number} millis Epoch millis.
 * @param {number | null} bpm Heart rate, when known.
 * @return {string} Trackpoint XML.
 */
function trackpoint(millis: number, bpm: number | null): string {
  const heartRate = bpm === null ?
    "" :
    `<HeartRateBpm><Value>${Math.round(bpm)}</Value></HeartRateBpm>`;
  return `<Trackpoint><Time>${isoTime(millis)}</Time>${heartRate}</Trackpoint>`;
}

/**
 * ISO-8601 UTC with whole seconds.
 * @param {number} millis Epoch millis.
 * @return {string} Timestamp.
 */
function isoTime(millis: number): string {
  return new Date(Math.round(millis / 1000) * 1000)
    .toISOString()
    .replace(".000Z", "Z");
}

/**
 * Thousands-separated integer.
 * @param {number} value Count.
 * @return {string} Formatted count.
 */
function formatCount(value: number): string {
  return Math.round(value).toLocaleString("en-US");
}
