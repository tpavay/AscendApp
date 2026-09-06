#!/usr/bin/env node

/**
 * Read-only seed audit for dev/staging Firebase data.
 *
 * Usage:
 *   node scripts/audit-seed-data.mjs --project staging --target all
 *   node scripts/dev-db.mjs audit --project staging --target profiles,leaderboard
 */

import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {applicationDefault, initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp, FieldValue} from "firebase-admin/firestore";
import {runPool, withRetry} from "./lib/firestore-bulk.mjs";

/** Reads in flight at once during an audit. */
const AUDIT_READ_CONCURRENCY = 32;
import {
  assertSeedableProject,
  defaultSeedPackId,
  resolveProjectId,
} from "./seed/lib/environments.mjs";
import {
  firstAscentInvariantFailure,
  isOpenFirstAscentSummary,
  summaryHasFirstAscent,
} from "./seed/lib/live-replay-first-ascent.mjs";
import {
  buildLeaderboardSeedWrites,
  currentPeriod,
  expectedLeaderboardDocIds,
  expectedProfileUserIds,
  leaderboardDocId,
  legacyLeaderboardDocIds,
  PROFILE_SEED_PERSONAS,
  publicIdentityMismatchFields,
  publishedPublicIdentity,
  seedAsOfInstant,
  statsFromWorkoutDocuments,
  validateDocumentKeys,
} from "./seed/fixtures/profile-fixtures.mjs";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(SCRIPT_DIR, "..");
const TARGET_ORDER = ["profiles", "leaderboard", "live-replay", "routine-templates"];
const TARGET_ALIASES = new Map([
  ["all", "all"],
  ["profile", "profiles"],
  ["profiles", "profiles"],
  ["users", "profiles"],
  ["leaderboard", "leaderboard"],
  ["leaderboards", "leaderboard"],
  ["replay", "live-replay"],
  ["live-replay", "live-replay"],
  ["live_replay", "live-replay"],
  ["routine-template", "routine-templates"],
  ["routine-templates", "routine-templates"],
  ["routine_templates", "routine-templates"],
  ["routines", "routine-templates"],
]);

const LIVE_REPLAY_COLLECTION = "live_replay_leaderboards";
const LIVE_CLIMB_CONTEXT_TYPE = "live_climb";
const LEGACY_LEADERBOARD_USER_IDS = Array.from({length: 40}, (_, index) => `test_user_${index + 1}`);
const LEGACY_TIME_FRAMES = ["daily", "weekly", "monthly", "yearly", "all_time"];

function parseArgs(argv) {
  const args = {project: "dev", targets: ["all"]};
  for (let index = 2; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--project") args.project = requireValue(argv, ++index, value);
    else if (value === "--target" || value === "--targets") {
      args.targets = requireValue(argv, ++index, value).split(",").map((target) => target.trim());
    } else if (value === "--help" || value === "-h") {
      args.help = true;
    } else {
      throw new Error(`Unknown argument: ${value}`);
    }
  }
  return args;
}

function requireValue(argv, index, flag) {
  const value = argv[index];
  if (!value || value.startsWith("--")) throw new Error(`${flag} requires a value`);
  return value;
}

function printHelp() {
  console.log(`
Usage:
  node scripts/audit-seed-data.mjs --project staging --target all
  node scripts/audit-seed-data.mjs --project dev --target profiles,leaderboard
`);
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    printHelp();
    return;
  }

  const projectId = resolveProjectId(args.project, REPO_ROOT);
  assertSeedableProject(projectId, "audit");
  const targets = resolveTargets(args.targets);

  initializeApp({credential: applicationDefault(), projectId});
  const db = getFirestore();
  const catalog = loadCatalog();
  const failures = [];
  const summaries = [];

  console.log(`Project: ${projectId}`);
  console.log(`Audit targets: ${targets.join(", ")}`);

  if (targets.includes("profiles")) {
    summaries.push(await auditProfiles(db, failures));
  }
  if (targets.includes("leaderboard")) {
    summaries.push(await auditLeaderboard(db, catalog, failures));
  }
  if (targets.includes("live-replay")) {
    summaries.push(await auditLiveReplay(db, projectId, failures));
  }
  if (targets.includes("routine-templates")) {
    summaries.push(await auditRoutineTemplates(db, projectId, failures));
  }

  console.log("\nAudit summary:");
  summaries.forEach((summary) => console.log(`  ${summary}`));

  if (failures.length > 0) {
    console.error("\nSeed audit failed:");
    failures.slice(0, 80).forEach((failure) => console.error(`  - ${failure}`));
    if (failures.length > 80) {
      console.error(`  ...and ${failures.length - 80} more`);
    }
    process.exit(1);
  }

  console.log("\nSeed audit passed.");
}

function resolveTargets(rawTargets) {
  const selected = new Set();
  for (const rawTarget of rawTargets) {
    const target = TARGET_ALIASES.get(rawTarget);
    if (!target) {
      throw new Error(`Unknown target "${rawTarget}". Use profiles, leaderboard, live-replay, routine-templates, or all.`);
    }
    if (target === "all") {
      TARGET_ORDER.forEach((item) => selected.add(item));
    } else {
      selected.add(target);
    }
  }
  return TARGET_ORDER.filter((target) => selected.has(target));
}

function loadCatalog() {
  const raw = JSON.parse(readFileSync(resolve(REPO_ROOT, "web/public/climbs/catalog-v1.json"), "utf-8"));
  const climbs = Array.isArray(raw) ? raw : raw.climbs;
  return new Map(climbs.map((climb) => [climb.id, climb]));
}

async function auditProfiles(db, failures) {
  let documentsChecked = 0;

  // Read every persona's four documents at once. Serially this was 48 round
  // trips before the audit reported anything, on a command whose whole job is to
  // answer quickly enough that people run it.
  const personas = await inOrder(expectedProfileUserIds(), async (userId) => {
    const userRef = db.collection("users").doc(userId);
    const [userSnapshot, publicSnapshot, statsSnapshot, workoutsSnapshot] = await Promise.all([
      read(userRef), read(userRef.collection("public_profile").doc("current")),
      read(userRef.collection("profile_stats").doc("current")),
      read(userRef.collection("profile_workouts")),
    ]);
    return {userId, userRef, userSnapshot, publicSnapshot, statsSnapshot, workoutsSnapshot};
  });

  for (const {userId, userSnapshot, publicSnapshot, statsSnapshot, workoutsSnapshot} of personas) {

    documentsChecked += 3 + workoutsSnapshot.size;

    const user = expectDocument(userSnapshot, `users/${userId}`, failures);
    const publicProfile = expectDocument(publicSnapshot, `users/${userId}/public_profile/current`, failures);
    const stats = expectDocument(statsSnapshot, `users/${userId}/profile_stats/current`, failures);

    if (user) {
      validateDocumentKeys(`users/${userId}`, user, "user", failures);
      requirePresent(user, "height_cm", `users/${userId}`, failures);
      requirePresent(user, "weight_kg", `users/${userId}`, failures);
    }
    if (publicProfile) {
      validateDocumentKeys(`users/${userId}/public_profile/current`, publicProfile, "publicProfile", failures);
      requirePresent(publicProfile, "height_cm", `users/${userId}/public_profile/current`, failures);
      requirePresent(publicProfile, "weight_kg", `users/${userId}/public_profile/current`, failures);
    }
    if (stats) {
      validateDocumentKeys(`users/${userId}/profile_stats/current`, stats, "profileStats", failures);
    }

    const workouts = workoutsSnapshot.docs.map((doc) => {
      const data = doc.data();
      const path = `users/${userId}/profile_workouts/${doc.id}`;
      validateDocumentKeys(path, data, "profileWorkout", failures);
      if (data.climbId === "") failures.push(`${path} has empty climbId`);
      if (data.climbCompletionStatus === "completed") {
        requirePresent(data, "climbId", path, failures);
        if (!positiveNumber(data.climbCompletionDurationSeconds)) {
          failures.push(`${path} completed climb is missing positive climbCompletionDurationSeconds`);
        }
      }
      return data;
    });

    if (stats) {
      compareDerivedStats(userId, stats, statsFromWorkoutDocuments(workouts), failures);
    }
  }

  return `profiles: ${PROFILE_SEED_PERSONAS.length} users, ${documentsChecked} profile documents checked`;
}

async function auditLeaderboard(db, catalog, failures) {
  const {identities: publicIdentities, joinedAt} = await readPublishedPublicIdentities(db, failures);
  if (publicIdentities.size !== PROFILE_SEED_PERSONAS.length) {
    return "leaderboard: 0 rows checked; public identity prerequisites failed";
  }

  // Period keys are pinned to when the pack was seeded, not to when it is read,
  // so a seed and the audit that follows it can straddle UTC midnight.
  const seededAt = seedAsOfInstant(joinedAt) ?? new Date();
  const expectedWrites = buildLeaderboardSeedWrites({
    db,
    catalog,
    Timestamp,
    FieldValue,
    publicIdentities,
    now: seededAt,
  });
  const expectedIds = new Set(expectedWrites.map((item) => item.ref.id));
  let checked = 0;

  const expectedSnapshots = await inOrder(expectedWrites, (writeItem) => read(writeItem.ref));

  for (const [writeIndex, writeItem] of expectedWrites.entries()) {
    const snapshot = expectedSnapshots[writeIndex];
    const path = `leaderboard_stats/${writeItem.ref.id}`;
    const data = expectDocument(snapshot, path, failures);
    if (!data) continue;
    checked += 1;

    validateDocumentKeys(path, data, "leaderboardStats", failures);
    if (data.userId && !expectedProfileUserIds().includes(data.userId)) {
      failures.push(`${path} points at non-profile fixture user ${data.userId}`);
    }
    if (
      data.userId &&
      data.periodKey &&
      writeItem.ref.id !== leaderboardDocId(data.userId, data.timeFrame, data.periodKey)
    ) {
      failures.push(`${path} id does not match timeFrame/period/userId`);
    }
    if (data.schemaVersion !== 2) {
      failures.push(`${path} schemaVersion must be 2`);
    }
    if (data.timeFrame) {
      const period = currentPeriod(data.timeFrame, seededAt);
      if (data.periodKey !== period.key) {
        failures.push(`${path} has stale periodKey ${data.periodKey}; expected ${period.key}`);
      }
    }
    if (data.userId) {
      auditLeaderboardIdentity(
        data,
        publicIdentities.get(data.userId),
        path,
        failures
      );
    }
  }

  const mustNotExist = [
    ...expectedLeaderboardDocIds(seededAt)
      .filter((docId) => !expectedIds.has(docId))
      .map((docId) => [docId, "should not exist for a zero-step seeded user"]),
    ...LEGACY_LEADERBOARD_USER_IDS.flatMap((userId) => LEGACY_TIME_FRAMES.map((timeFrame) =>
      [`${userId}_${timeFrame}`, "is legacy orphan leaderboard data; clear/reseed leaderboard"])),
    ...legacyLeaderboardDocIds()
      .map((docId) => [docId, "is legacy profile leaderboard data; clear/reseed leaderboard"]),
  ];
  const orphanSnapshots = await inOrder(
    mustNotExist,
    ([docId]) => read(db.collection("leaderboard_stats").doc(docId))
  );

  for (const [index, [docId, complaint]] of mustNotExist.entries()) {
    if (orphanSnapshots[index].exists) {
      failures.push(`leaderboard_stats/${docId} ${complaint}`);
    }
  }

  return `leaderboard: ${checked} persona rows checked, seeded ${seededAt.toISOString()}`;
}

async function readPublishedPublicIdentities(db, failures) {
  const identities = new Map();
  const joinedAt = new Map();
  const snapshots = await Promise.all(
    PROFILE_SEED_PERSONAS.map((persona) =>
      db
        .collection("users")
        .doc(persona.id)
        .collection("public_profile")
        .doc("current")
        .get()
    )
  );

  for (let index = 0; index < snapshots.length; index += 1) {
    const snapshot = snapshots[index];
    const userId = PROFILE_SEED_PERSONAS[index].id;
    if (!snapshot.exists) {
      failures.push(
        `users/${userId}/public_profile/current is required for leaderboard audit`
      );
      continue;
    }

    joinedAt.set(userId, snapshot.data()?.joined_at);

    try {
      identities.set(
        userId,
        publishedPublicIdentity(userId, snapshot.data())
      );
    } catch (error) {
      failures.push(error.message);
    }
  }

  return {identities, joinedAt};
}

function auditLeaderboardIdentity(data, identity, path, failures) {
  if (!identity) {
    failures.push(`${path} has no current public identity to compare`);
    return;
  }

  for (const field of publicIdentityMismatchFields(data, identity)) {
    failures.push(
      `${path} ${field} differs from ` +
      `users/${data.userId}/public_profile/current`
    );
  }
}

async function auditLiveReplay(db, projectId, failures) {
  const seedPackId = defaultSeedPackId("live-replay", projectId);
  const snapshot = await db
    .collection(LIVE_REPLAY_COLLECTION)
    .where("seedPackId", "==", seedPackId)
    .get();

  if (snapshot.empty) {
    failures.push(`live replay seed pack ${seedPackId} has no summaries`);
    return "live-replay: 0 summaries checked";
  }

  let bucketZeroEntries = 0;
  const bucketZeroByIndex = await inOrder(snapshot.docs, (doc) =>
    read(doc.ref.collection("splitBuckets").doc("0").collection("entries")));

  for (const [summaryIndex, doc] of snapshot.docs.entries()) {
    const data = doc.data();
    const path = `${LIVE_REPLAY_COLLECTION}/${doc.id}`;
    requirePresent(data, "contextType", path, failures);
    requirePresent(data, "contextId", path, failures);
    requirePresent(data, "completedCount", path, failures);
    requirePresent(data, "totalClimbers", path, failures);
    requirePresent(data, "replayEntryCount", path, failures);
    requirePresent(data, "bucketIntervalSeconds", path, failures);

    const bucketZero = bucketZeroByIndex[summaryIndex];
    bucketZeroEntries += bucketZero.size;

    // Read off the counts and the holder, never off activityTier: the seed
    // script is the only writer of that tier and the Cloud Function's summary
    // merge never resets it, so it stays "open" on a climb a real climber has
    // legitimately claimed. It records what the seed intended, not the state.
    const firstAscentState = {
      climbId: path,
      completedCount: numberValue(data.completedCount),
      hasFirstAscent: summaryHasFirstAscent(data),
    };

    // The global Just Climb context is exempt: First Ascent is per-landmark
    // prestige and nothing renders one there, so it keeps completions with no
    // holder on purpose.
    if (data.contextType === LIVE_CLIMB_CONTEXT_TYPE) {
      const invariantFailure = firstAscentInvariantFailure(firstAscentState);
      if (invariantFailure) failures.push(invariantFailure);

      if (isOpenFirstAscentSummary(firstAscentState)) {
        auditOpenFirstAscentSummary(data, path, bucketZero, failures);
        continue;
      }
    }

    if (!positiveNumber(data.completedCount)) failures.push(`${path} completedCount must be positive`);
    if (!positiveNumber(data.totalClimbers)) failures.push(`${path} totalClimbers must be positive`);
    auditSeededReplayRowCount(data, path, bucketZero, seedPackId, failures);

    if (bucketZero.empty) {
      failures.push(`${path}/splitBuckets/0 has no entries`);
      continue;
    }

    for (const entry of bucketZero.docs) {
      const entryData = entry.data();
      const entryPath = `${path}/splitBuckets/0/entries/${entry.id}`;
      ["completionDurationSeconds", "contextId", "contextType", "displayName", "finalSteps", "schemaVersion", "splitIntervalSeconds", "stepsAtBucket", "userId", "workoutId"].forEach((field) => {
        requirePresent(entryData, field, entryPath, failures);
      });
      if (entryData.stepsAtBucket !== 0) failures.push(`${entryPath} bucket 0 stepsAtBucket must be 0`);
      if (!positiveNumber(entryData.completionDurationSeconds)) failures.push(`${entryPath} completionDurationSeconds must be positive`);
      if (!positiveNumber(entryData.finalSteps)) failures.push(`${entryPath} finalSteps must be positive`);
    }
  }

  return `live-replay: ${snapshot.size} summaries, ${bucketZeroEntries} bucket-zero entries checked`;
}

/**
 * Audits a summary whose First Ascent slot is still open.
 *
 * An open slot is only claimable while the climb has zero completions, so these
 * summaries carry deliberate zeros rather than the seeded traffic every other
 * climb has. The rest of the summary has to agree with that: a climber count or
 * a replay row without a matching completion means the seed half-wrote the
 * fixture, and the climb no longer reads as the clean opportunity it promises.
 * @param {Record<string, unknown>} data Summary fields.
 * @param {string} path Summary document path, for failure messages.
 * @param {object} bucketZero Bucket-zero entries snapshot.
 * @param {string[]} failures Accumulated audit failures.
 */
function auditOpenFirstAscentSummary(data, path, bucketZero, failures) {
  for (const field of ["totalClimbers", "replayEntryCount"]) {
    if (numberValue(data[field]) !== 0) {
      failures.push(`${path} has an open First Ascent but ${field} is ${data[field]}`);
    }
  }

  if (!bucketZero.empty) {
    failures.push(`${path}/splitBuckets/0 has ${bucketZero.size} entries but the summary reports no completions`);
  }
}

/**
 * Audits the summary's seeded replay row count against the rows actually seeded.
 *
 * `replayEntryCount` counts the synthetic rows this seed pack wrote, and only the
 * seed maintains it - the Cloud Function's summary merge leaves it alone. So it
 * is checked against the seeded rows rather than required to be positive: a
 * climb seeded with an open slot legitimately keeps zero synthetic rows after a
 * real climber finishes it and pushes `completedCount` to 1, which is exactly
 * what those fixtures exist for.
 * @param {Record<string, unknown>} data Summary fields.
 * @param {string} path Summary document path, for failure messages.
 * @param {object} bucketZero Bucket-zero entries snapshot.
 * @param {string} seedPackId Seed pack being audited.
 * @param {string[]} failures Accumulated audit failures.
 */
function auditSeededReplayRowCount(data, path, bucketZero, seedPackId, failures) {
  const seededRows = bucketZero.docs.filter(
    (entry) => entry.data().seedPackId === seedPackId
  ).length;

  if (numberValue(data.replayEntryCount) !== seededRows) {
    failures.push(
      `${path} replayEntryCount is ${data.replayEntryCount} but ${seededRows} seeded bucket-zero entries exist`
    );
  }
}

async function auditRoutineTemplates(db, projectId, failures) {
  const seedPackId = defaultSeedPackId("routine-templates", projectId);
  const snapshot = await db
    .collection("routine_templates")
    .where("seedPackId", "==", seedPackId)
    .get();

  if (snapshot.empty) {
    failures.push(`routine template seed pack ${seedPackId} has no templates`);
  }

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const path = `routine_templates/${doc.id}`;
    ["templateId", "name", "status", "version", "intervals", "seedPackId", "updatedAt"].forEach((field) => {
      requirePresent(data, field, path, failures);
    });
    if (data.templateId !== doc.id) {
      failures.push(`${path} templateId does not match document ID`);
    }
    if (!Array.isArray(data.intervals) || data.intervals.length === 0) {
      failures.push(`${path} has no routine intervals`);
    }
  }

  return `routine-templates: ${snapshot.size} templates checked`;
}

function expectDocument(snapshot, path, failures) {
  if (!snapshot.exists) {
    failures.push(`${path} is missing`);
    return null;
  }
  return snapshot.data();
}

function requirePresent(data, field, path, failures) {
  if (data[field] === undefined || data[field] === null || data[field] === "") {
    failures.push(`${path} missing ${field}`);
  }
}

function compareDerivedStats(userId, actual, expected, failures) {
  const path = `users/${userId}/profile_stats/current`;
  [
    "total_climbs_completed",
    "lifetime_total_steps",
    "lifetime_duration_seconds",
    "total_climbs",
    "pr_most_steps",
    "pr_longest_climb_seconds",
  ].forEach((field) => {
    if (integerValue(actual[field]) !== integerValue(expected[field])) {
      failures.push(`${path} ${field}=${actual[field]} does not match workouts (${expected[field]})`);
    }
  });

  [
    "average_steps_per_minute",
    "pr_highest_spm",
  ].forEach((field) => {
    if (!nearlyEqual(numberValue(actual[field]), numberValue(expected[field]), 0.01)) {
      failures.push(`${path} ${field}=${actual[field]} does not match workouts (${expected[field]})`);
    }
  });
}

function positiveNumber(value) {
  return Number.isFinite(Number(value)) && Number(value) > 0;
}

function integerValue(value) {
  return Number.isFinite(Number(value)) ? Math.trunc(Number(value)) : 0;
}

function numberValue(value) {
  return Number.isFinite(Number(value)) ? Number(value) : 0;
}

function nearlyEqual(lhs, rhs, tolerance) {
  return Math.abs(lhs - rhs) <= tolerance;
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});

/**
 * Reads one document or collection under a deadline.
 *
 * The audit is a read-only command people are meant to run often, so it has the
 * same rule as the seeds: no call without a clock on it.
 * @param {object} ref Document or collection reference.
 * @return {Promise<object>} Snapshot.
 */
function read(ref) {
  return withRetry(() => ref.get(), {description: `get(${ref.path})`});
}

/**
 * Maps over items concurrently and returns the results in the original order.
 *
 * Order matters: the audit's value is a stable list of failures somebody can
 * diff between runs, and a pool that appends as it finishes reorders them.
 * @param {T[]} items Work items.
 * @param {(item: T, index: number) => Promise<R>} worker Per-item work.
 * @return {Promise<R[]>} Results, indexed as the input was.
 * @template T, R
 */
async function inOrder(items, worker) {
  const results = new Array(items.length);
  await runPool(items, AUDIT_READ_CONCURRENCY, async (item, index) => {
    results[index] = await worker(item, index);
  });
  return results;
}
