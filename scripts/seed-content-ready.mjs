#!/usr/bin/env node

/**
 * Staging Content-Ready Seed
 *
 * One command that puts a staging environment into the state described in
 * `docs/staging-content-capture.md`, so App Store screenshots, video and
 * marketing can be captured without performing every climb by hand.
 *
 * It composes the existing seed scripts rather than reimplementing them. What it
 * owns is the recipe: which of them run, in which order, against which account,
 * and what has to be true afterwards for the result to count as content-ready.
 *
 * Usage:
 *   node scripts/seed-content-ready.mjs --email you@example.com --dry-run
 *   node scripts/seed-content-ready.mjs --email you@example.com
 *   node scripts/seed-content-ready.mjs verify --email you@example.com
 *   node scripts/seed-content-ready.mjs clear --email you@example.com
 *
 * Prerequisites:
 *   Node.js 20+
 *   cd scripts && npm install
 *   gcloud auth application-default login
 *   The target account has signed into the target environment at least once.
 */

import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {applicationDefault, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {runSeedStep} from "./lib/seed-step-runner.mjs";
import {planIdentityRepair} from "./lib/staging-identity-repair.mjs";
import {PROFILE_SEED_PERSONAS} from "./seed/fixtures/profile-fixtures.mjs";
import {createBatchWriter, createProgressReporter, withRetry} from "./lib/firestore-bulk.mjs";
import {
  assertSeedableProject,
  resolveProjectId,
  seedEnvironmentName,
} from "./seed/lib/environments.mjs";
import {
  CONTENT_READY_THRESHOLDS,
  contentReadinessFailures,
  unphotographableDisplayName,
} from "./seed/lib/content-ready-contract.mjs";
import {FieldValue} from "firebase-admin/firestore";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(SCRIPT_DIR, "..");
const COMMANDS = new Set(["seed", "verify", "clear", "plan", "help"]);

/**
 * The seed steps, in the order the recipe depends on.
 *
 * The order is the whole point of this script, and two edges are load-bearing:
 *
 * - `leaderboard` reads the public identities `profiles` publishes, so it cannot
 *   run first against an empty environment.
 * - `live-replay` writes a synthetic First Ascent holder and a completion count
 *   onto the same summaries the account seed merges into, so the account must
 *   run *after* it. Reversed, the synthetic holder overwrites the account's
 *   claim and the account's own board reads as somebody else's.
 */
const WORLD_TARGETS = ["profiles", "leaderboard", "live-replay", "routine-templates"];

/** How long the recipe waits for a renamed identity to reach the boards. */
const IDENTITY_PROPAGATION_DEADLINE_MS = 45_000;

/** How often it re-reads while waiting. */
const IDENTITY_PROPAGATION_POLL_MS = 3_000;

function parseArgs(argv) {
  const first = argv[2];
  const args = {
    command: first && !first.startsWith("-") ? first : "seed",
    project: "staging",
    email: null,
    userId: null,
    displayName: null,
    dryRun: false,
  };
  const start = first && !first.startsWith("-") ? 3 : 2;

  for (let index = start; index < argv.length; index += 1) {
    const value = argv[index];
    switch (value) {
      case "--project":
        args.project = requireValue(argv, ++index, value);
        break;
      case "--email":
        args.email = requireValue(argv, ++index, value);
        break;
      case "--user":
      case "--uid":
        args.userId = requireValue(argv, ++index, value);
        break;
      case "--display-name":
        args.displayName = requireValue(argv, ++index, value);
        break;
      case "--dry-run":
        args.dryRun = true;
        break;
      case "--help":
      case "-h":
        args.command = "help";
        break;
      default:
        throw new Error(`Unknown argument: ${value}`);
    }
  }

  if (!COMMANDS.has(args.command)) {
    throw new Error(
      `Unknown command "${args.command}". Use seed, verify, clear, plan, or help.`
    );
  }

  return args;
}

function requireValue(argv, index, flag) {
  const value = argv[index];
  if (!value || value.startsWith("--")) {
    throw new Error(`${flag} requires a value`);
  }
  return value;
}

function printHelp() {
  console.log(`
Puts staging into the content-ready state documented in
docs/staging-content-capture.md.

Usage:
  node scripts/seed-content-ready.mjs [seed] --email you@example.com [--dry-run]
  node scripts/seed-content-ready.mjs verify --email you@example.com
  node scripts/seed-content-ready.mjs clear  --email you@example.com [--dry-run]
  node scripts/seed-content-ready.mjs plan

Commands:
  seed    Seed the world, then the one named account, then verify, then prove
          the app would render it. The default.
          Idempotent: running it twice leaves the same state.
  verify  Read-only. Re-check the content-ready contract, then run the filmable
          check that reads every surface the way the app reads it.
  clear   Take the state back out: the account's seeded documents first, then
          the world fixtures. Leaves account identity and any climb performed in
          the app alone - delete those in the app.
  plan    Print the recipe without touching an environment.

Options:
  --email <email>   The account to seed. Required for seed, verify, and clear.
  --user <uid>      Use a Firebase Auth uid instead of an email.
  --display-name <name>
                    The name published on leaderboards. Defaults to the
                    account's own. This name is what a screenshot shows, so it
                    has to read as a climber.
  --project <name>  staging (default) or dev. Production is refused outright.
  --dry-run         Print every step's plan and write nothing.

The account must already exist in the target environment's Firebase Auth: sign
into the app once with it before running this.
`);
}

async function main() {
  const args = parseArgs(process.argv);

  if (args.command === "help") {
    printHelp();
    return;
  }

  if (args.command === "plan") {
    printRecipe();
    return;
  }

  if (!args.email && !args.userId) {
    throw new Error(
      `seed-content-ready ${args.command} requires --email <email> or --user <uid>`
    );
  }

  const projectId = resolveProjectId(args.project, REPO_ROOT);
  assertSeedableProject(projectId, "seed content into");

  initializeApp({credential: applicationDefault(), projectId});
  const account = await resolveAccount(args);

  console.log(`Project:     ${projectId} (${seedEnvironmentName(projectId)})`);
  console.log(`Account:     ${account.uid} <${account.email ?? "no email"}>`);
  console.log(`Command:     ${args.command}${args.dryRun ? " (dry run)" : ""}`);

  if (args.command === "verify") {
    const ready = await verify(account);
    const filmable = runFilmableCheck(projectId, account);
    reportVerdict(ready, filmable);
    return;
  }

  if (args.command === "clear") {
    clearAccount(projectId, args, account);
    clearWorld(projectId, args);
    console.log(
      args.dryRun ?
        "\nDry run only. Nothing was cleared." :
        "\nStaging content cleared. Re-run without a command to rebuild it."
    );
    return;
  }

  const startedAt = Date.now();
  seedWorld(projectId, args);
  seedAccount(projectId, args, account);
  const repair = await repairBoardIdentities(getFirestore(), account, args, stepSeconds);

  if (args.dryRun) {
    printTimings(startedAt);
    console.log("\nDry run only. Nothing was written, so there is nothing to verify.");
    return;
  }

  await awaitIdentityPropagation(getFirestore(), repair.renames, stepSeconds);

  runAudit(projectId);
  const ready = await verify(account);
  const filmable = runFilmableCheck(projectId, account);
  printTimings(startedAt);

  if (!reportVerdict(ready, filmable)) {
    return;
  }

  console.log(
    "\nStaging is content-ready and every surface renders it. Reinstall or sign " +
    "out and back in on the capture device so it hydrates the new state."
  );
}

/**
 * Resolves the one account this run is allowed to touch.
 *
 * Looked up rather than created, and looked up before anything is written, so a
 * typo fails the command instead of leaving a seeded world around an account
 * that does not exist.
 * @param {object} args Parsed CLI arguments.
 * @return {Promise<object>} Firebase Auth user record.
 */
async function resolveAccount(args) {
  const auth = getAuth();
  try {
    return args.userId ?
      await auth.getUser(args.userId) :
      await auth.getUserByEmail(args.email);
  } catch {
    const lookup = args.userId ? `uid ${args.userId}` : `email ${args.email}`;
    throw new Error(
      `No Firebase Auth user for ${lookup} in this environment. ` +
      "Sign into the app once with that account, then rerun."
    );
  }
}

function printRecipe() {
  console.log("Content-ready recipe:\n");
  console.log("  1. dev-db seed --target " + WORLD_TARGETS.join(","));
  console.log("     Competitors, global standings, replay boards, routines.");
  console.log("  2. seed-demo-user seed --email <account>");
  console.log("     The named account's climbs, records, standings, First Ascent.");
  console.log("  3. audit-seed-data --target all");
  console.log("     The existing fixture audit.");
  console.log("  4. content-ready verification");
  console.log("     " + Object.entries(CONTENT_READY_THRESHOLDS)
    .map(([key, value]) => `${key}=${value}`).join(", "));
  console.log("  5. verify-filmable --project <project> --user <account>");
  console.log("     Reads every surface the way the app reads it, and refuses to");
  console.log("     let this command report success when one of them would not film.");
  console.log("\nClear reverses 2 then 1. Full definition: docs/staging-content-capture.md");
}

function seedWorld(projectId, args) {
  runScript("dev-db.mjs", [
    "seed",
    "--project", projectId,
    "--target", WORLD_TARGETS.join(","),
    ...(args.dryRun ? ["--dry-run"] : []),
  ]);
}

function clearWorld(projectId, args) {
  runScript("dev-db.mjs", [
    "clear",
    "--project", projectId,
    "--target", WORLD_TARGETS.join(","),
    ...(args.dryRun ? ["--dry-run"] : []),
  ]);
}

function seedAccount(projectId, args, account) {
  runScript("seed-demo-user.mjs", [
    "seed",
    "--project", projectId,
    "--user", account.uid,
    ...(args.displayName ? ["--display-name", args.displayName] : []),
    ...(args.dryRun ? ["--dry-run"] : []),
  ]);
}

function clearAccount(projectId, args, account) {
  runScript("seed-demo-user.mjs", [
    "clear",
    "--project", projectId,
    "--user", account.uid,
    ...(args.dryRun ? ["--dry-run"] : []),
  ]);
}

/**
 * Gives every other account on the boards a name fit to photograph.
 *
 * Runs after the two seeds because it has to see the identities they publish
 * before it can avoid colliding with them. What it repairs is the population
 * neither seed owns: the QA and tester accounts that signed into staging and
 * left "CHANGE ME", "Content Capture" and "Climber 6J84R7" on the boards.
 *
 * It writes only the account's own public profile mirror. The deployed
 * `onPublicProfileIdentityWritten` trigger carries the new name to
 * `leaderboard_stats` and to every replay projection, which is the one path
 * allowed to publish account-authored identity.
 * @param {object} db Firestore instance.
 * @param {object} account The account being captured.
 * @param {object} args Parsed CLI arguments.
 * @param {Array} timings Per-step wall clocks to append to.
 * @return {Promise<object>} The plan that was applied.
 */
async function repairBoardIdentities(db, account, args, timings) {
  const startedAt = Date.now();
  const identities = await readPublishedIdentities(db);
  const {renames, photoless, seedOwnedFailures} = planIdentityRepair(identities, {
    protectedUid: account.uid,
    seedOwnedUids: new Set(PROFILE_SEED_PERSONAS.map((persona) => persona.id)),
  });

  if (seedOwnedFailures.length > 0) {
    throw new Error(
      "These identities come from scripts/seed/fixtures/profile-fixtures.mjs, so " +
      "renaming them here would last exactly until the next seed. Fix the " +
      "fixture:\n" +
      seedOwnedFailures
        .map((failure) => `  ${failure.uid}: ${failure.reason}`)
        .join("\n")
    );
  }

  console.log(`\n> repair board identities (${identities.length} published)`);
  if (renames.length === 0) {
    console.log("  Every published name already reads as a climber.");
  }

  for (const rename of renames) {
    console.log(`  ${rename.uid}: ${JSON.stringify(rename.from)} -> "${rename.to}"  (${rename.reason})`);
  }

  if (photoless.length > 0) {
    console.log(
      `  ${photoless.length} published identit${photoless.length === 1 ? "y has" : "ies have"} ` +
      "no photo and will render as a lettered circle. A face has to be a picture " +
      "somebody chose, so this is reported rather than invented - give one with " +
      `node dev-db.mjs hydrate-user --project ${args.project} --user <uid> --photo-url <storage url>.`
    );
    photoless.forEach((uid) => console.log(`    ${uid}`));
  }

  if (args.dryRun || renames.length === 0) {
    timings.push(["repair-identities", (Date.now() - startedAt) / 1000]);
    return {renames, photoless};
  }

  const progress = createProgressReporter({label: "Identities", total: renames.length, quiet: true});
  const writer = createBatchWriter(db, {progress});
  for (const rename of renames) {
    writer.set(db.collection("users").doc(rename.uid).collection("public_profile").doc("current"), {
      displayName: rename.to,
      identityPolicyVersion: 1,
      identityChangedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  await writer.drain();
  const seconds = progress.finish(`${renames.length} identit${renames.length === 1 ? "y" : "ies"} republished`);
  timings.push(["repair-identities", (Date.now() - startedAt) / 1000]);
  void seconds;

  console.log(
    "  onPublicProfileIdentityWritten carries these to leaderboard_stats and " +
    "the replay projections."
  );
  return {renames, photoless};
}

/**
 * Every identity this environment publishes, as the boards see it.
 * @param {object} db Firestore instance.
 * @return {Promise<object[]>} `{uid, displayName, photoURL}` per published mirror.
 */
async function readPublishedIdentities(db) {
  const snapshot = await db.collectionGroup("public_profile").get();
  return snapshot.docs
    .filter((document) => document.id === "current")
    .map((document) => ({
      uid: document.ref.parent.parent.id,
      displayName: document.data().displayName ?? null,
      photoURL: document.data().photoURL ?? null,
    }));
}

function runAudit(projectId) {
  runScript("audit-seed-data.mjs", ["--project", projectId, "--target", "all"]);
}

/**
 * Proves the app would render what the seed just wrote.
 *
 * This is the step whose absence made the whole process untrustworthy. Every
 * other check here - the seed's own summary, the fixture audit, the content-ready
 * contract - answers a question about Firestore, and the captain kept
 * discovering afterwards that it had not been a question about the screen: a
 * board whose summary claimed 85 finishers rendered "4 completed", and its
 * rivals were absent from the first half of the climb. `verify-filmable.mjs`
 * reads the same collections through the same aggregates the client uses, so a
 * pass here is a statement about what a camera would see.
 *
 * A failure is returned rather than thrown so the recipe still prints its
 * timings and its own verdict; the command still exits non-zero.
 * @param {string} projectId Environment that was seeded.
 * @param {object} account Firebase Auth user record.
 * @return {{ok: boolean, failure: ?string}} Whether every surface would film.
 */
function runFilmableCheck(projectId, account) {
  console.log(`\n> node verify-filmable.mjs --project ${projectId} --user ${account.uid}`);
  try {
    stepSeconds.push(["verify-filmable.mjs", runSeedStep(
      resolve(SCRIPT_DIR, "verify-filmable.mjs"),
      ["--project", projectId, "--user", account.uid],
      {cwd: SCRIPT_DIR, label: "verify-filmable.mjs", timeoutMs: 5 * 60 * 1000}
    )]);
    return {ok: true, failure: null};
  } catch (error) {
    return {ok: false, failure: error.message};
  }
}

/**
 * States the one verdict, and refuses to call a half-written environment done.
 *
 * A seed that stamps "done" on a board the app renders as empty is how this
 * became invisible for two days, so the recipe reports success only when both
 * the contract and the surfaces agree.
 * @param {boolean} ready Whether the content-ready contract holds.
 * @param {{ok: boolean, failure: ?string}} filmable Whether every surface would film.
 * @return {boolean} Whether the run may report success.
 */
function reportVerdict(ready, filmable) {
  if (ready && filmable.ok) {
    return true;
  }

  process.exitCode = 1;
  console.error("");
  if (!ready) {
    console.error("The content-ready contract is not satisfied (see the failures above).");
  }
  if (!filmable.ok) {
    console.error(`The filmable check did not pass: ${filmable.failure}`);
    console.error(
      "Everything was written. What did not hold is what the app would render " +
      "from it, which is the only claim that matters for a capture session."
    );
  }
  return false;
}

/**
 * Waits for the renamed identities to reach the boards, or says they did not.
 *
 * `repairBoardIdentities` writes only `users/{uid}/public_profile/current`, and
 * the deployed `onPublicProfileIdentityWritten` trigger carries the new name to
 * `leaderboard_stats` and the replay projections. That fan-out is asynchronous,
 * so a check run in the same second reads the old name and reports a placeholder
 * that has already been fixed. A check that cries wolf is a check nobody reads,
 * so the recipe waits - bounded, out loud, and it says so rather than waiting
 * longer when the trigger does not answer.
 * @param {object} db Firestore instance.
 * @param {object[]} renames Applied renames.
 * @param {Array} timings Per-step wall clocks to append to.
 * @return {Promise<void>} Resolves when the names have landed, or the wait is over.
 */
async function awaitIdentityPropagation(db, renames, timings) {
  if (renames.length === 0) {
    return;
  }

  const startedAt = Date.now();
  const deadline = startedAt + IDENTITY_PROPAGATION_DEADLINE_MS;
  console.log(`\n> wait for onPublicProfileIdentityWritten (${renames.length} renamed)`);

  let pending = renames;
  while (pending.length > 0 && Date.now() < deadline) {
    pending = (await Promise.all(pending.map(async (rename) => {
      const snapshot = await withRetry(
        () => db.collection("leaderboard_stats").where("userId", "==", rename.uid).limit(1).get(),
        {description: `query(leaderboard_stats userId=${rename.uid})`, timeoutMs: 15_000, attempts: 3}
      );
      // No standing to carry the name is not a wait: nothing will ever arrive.
      const landed = snapshot.empty || snapshot.docs[0].data().displayName === rename.to;
      return landed ? null : rename;
    }))).filter(Boolean);

    if (pending.length > 0) {
      await new Promise((settle) => setTimeout(settle, IDENTITY_PROPAGATION_POLL_MS));
    }
  }

  const seconds = (Date.now() - startedAt) / 1000;
  timings.push(["await-identity-propagation", seconds]);

  if (pending.length === 0) {
    console.log(`  Every renamed identity reached its board in ${seconds.toFixed(1)}s.`);
    return;
  }

  console.log(
    `  ${pending.length} renamed identit${pending.length === 1 ? "y" : "ies"} had not ` +
    `reached leaderboard_stats after ${seconds.toFixed(0)}s. The filmable check below ` +
    "reports what the boards actually carry; if it names these accounts, the " +
    "propagation trigger is the thing to look at, not the rename."
  );
  pending.forEach((rename) => console.log(`    ${rename.uid} -> "${rename.to}"`));
}

/**
 * Runs one composed script, failing this command when it fails.
 * @param {string} script Script filename under `scripts/`.
 * @param {string[]} scriptArgs Arguments to pass through.
 */
function runScript(script, scriptArgs) {
  console.log(`\n> node ${script} ${scriptArgs.join(" ")}`);
  stepSeconds.push([script, runSeedStep(resolve(SCRIPT_DIR, script), scriptArgs, {
    cwd: SCRIPT_DIR,
    label: script,
  })]);
}

/** Every step's wall clock, printed as one table when the recipe finishes. */
const stepSeconds = [];

/**
 * Prints where the time went.
 *
 * The recipe is four scripts deep, so "the seed is slow" is not actionable
 * without knowing which of them was slow. One line each, plus a total.
 * @param {number} startedAt Epoch milliseconds the recipe started.
 */
function printTimings(startedAt) {
  const total = (Date.now() - startedAt) / 1000;
  console.log("\nWhere the time went:");
  for (const [script, seconds] of stepSeconds) {
    console.log(`  ${script.padEnd(28)} ${seconds.toFixed(1).padStart(7)}s`);
  }
  console.log(`  ${"total".padEnd(28)} ${total.toFixed(1).padStart(7)}s`);
}

/**
 * Reads the environment back and reports whether it meets the contract.
 *
 * Separate from the seed so it can be re-run at any time - after a capture
 * session, after a real climb, after a week - to answer "is staging still worth
 * pointing a camera at" without writing anything.
 * @param {object} account Firebase Auth user record.
 * @return {Promise<boolean>} Whether the contract is satisfied.
 */
async function verify(account) {
  const observed = await observeContentState(getFirestore(), account.uid);
  const failures = contentReadinessFailures(observed);

  console.log("\nContent-ready state:");
  console.log(JSON.stringify(observed, null, 2));

  if (failures.length > 0) {
    console.error("\nStaging is NOT content-ready:");
    failures.forEach((failure) => console.error(`  - ${failure}`));
    process.exitCode = 1;
    return false;
  }

  console.log("\nContent-ready contract satisfied.");
  return true;
}

/**
 * Measures the content state of one environment and one account.
 *
 * Only reads, and reads the same documents the app renders from, so the report
 * is about what a screenshot would show rather than about what a seed intended.
 * @param {object} db Firestore instance.
 * @param {string} uid Account being measured.
 * @return {Promise<object>} Observed state for the contract to judge.
 */
async function observeContentState(db, uid) {
  const userRef = db.collection("users").doc(uid);
  const [profileStats, publicProfile, workouts, standings, summaries, routines] =
    await Promise.all([
      userRef.collection("profile_stats").doc("current").get(),
      userRef.collection("public_profile").doc("current").get(),
      userRef.collection("workouts").get(),
      db.collection("leaderboard_stats").where("userId", "==", uid).get(),
      db.collection("live_replay_leaderboards")
        .where("contextType", "==", "live_climb").get(),
      db.collection("routine_templates").get(),
    ]);

  const startedAtMs = workouts.docs
    .map((document) => millisecondsValue(document.data().startedAt))
    .filter((value) => value !== null);
  const now = Date.now();
  const stats = profileStats.data() ?? {};
  const heldFirstAscents = summaries.docs
    .filter((document) => document.data().firstAscentUserId === uid);
  const [firstAscentBoards, rows] = await Promise.all([
    Promise.all(heldFirstAscents.map(async (document) => {
      const finisher = await document.ref.collection("finishers").doc(uid).get();
      return {
        contextKey: document.id,
        completedCount: numberValue(document.data().completedCount) ?? 0,
        totalClimbers: numberValue(document.data().totalClimbers) ?? 0,
        holderCompletionOrder: numberValue(finisher.data()?.globalCompletionOrder),
      };
    })),
    sampleSeededRows(summaries.docs),
  ]);

  return {
    hasPublicProfile: publicProfile.exists,
    hasProfileStats: profileStats.exists,
    accountDisplayName: publicProfile.data()?.displayName ?? null,
    accountPhotoURL: publicProfile.data()?.photoURL ?? null,
    seededRowsSampled: rows.sampled,
    seededRowsWithoutPhoto: rows.withoutPhoto,
    seededRowsWithPlaceholderName: rows.withPlaceholderName,
    rowsWithoutPhotoExamples: rows.withoutPhotoExamples,
    workoutCount: workouts.size,
    climbsCompleted: numberValue(stats.total_climbs_completed) ?? 0,
    firstAscentsHeld: heldFirstAscents.length,
    firstAscentBoards,
    daysSinceNewestClimb: startedAtMs.length > 0 ?
      daysBetween(Math.max(...startedAtMs), now) :
      null,
    historyDepthDays: startedAtMs.length > 0 ?
      daysBetween(Math.min(...startedAtMs), now) :
      null,
    accountStandingRows: standings.size,
    contestedClimbBoards: summaries.docs.filter((document) =>
      (numberValue(document.data().completedCount) ?? 0) >=
        CONTENT_READY_THRESHOLDS.minimumCompetitorsPerContestedBoard).length,
    openFirstAscentBoards: summaries.docs.filter((document) =>
      (numberValue(document.data().completedCount) ?? 0) === 0 &&
        document.data().firstAscentUserId === undefined).length,
    routineTemplateCount: routines.size,
    incoherentBoards: summaries.docs
      .filter((document) => {
        const data = document.data();
        return (numberValue(data.completedCount) ?? 0) !==
          (numberValue(data.totalClimbers) ?? 0);
      })
      .map((document) => document.id),
  };
}

/**
 * Reads the seeded leaderboard rows back and reports what they would render as.
 *
 * Bucket zero only: every climber who has a row on a board has one there, and it
 * is the cheapest place to see the identity each row carries. What matters is
 * what is stored, not what the seed believed it stored - the avatar images live
 * in Storage and the rows only carry URLs into them, so a run that failed to
 * resolve the set still writes a complete-looking board of lettered circles.
 * @param {object[]} summaryDocs Live climb summary documents.
 * @return {Promise<object>} Row counts and a few offending examples.
 */
async function sampleSeededRows(summaryDocs) {
  let sampled = 0;
  let withoutPhoto = 0;
  let withPlaceholderName = 0;
  const withoutPhotoExamples = [];

  for (const summary of summaryDocs) {
    const entries = await summary.ref
      .collection("splitBuckets").doc("0").collection("entries").get();

    for (const entry of entries.docs) {
      const data = entry.data();
      if (data.isSynthetic !== true) {
        continue;
      }

      sampled += 1;
      if (typeof data.photoURL !== "string" || data.photoURL.length === 0) {
        withoutPhoto += 1;
        if (withoutPhotoExamples.length < 5) {
          withoutPhotoExamples.push(`${summary.id}/${data.displayName}`);
        }
      }
      if (unphotographableDisplayName(data.displayName) !== null) {
        withPlaceholderName += 1;
      }
    }
  }

  return {sampled, withoutPhoto, withPlaceholderName, withoutPhotoExamples};
}

function millisecondsValue(value) {
  if (value && typeof value.toDate === "function") {
    return value.toDate().getTime();
  }
  return null;
}

function numberValue(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function daysBetween(earlierMs, laterMs) {
  return Math.floor((laterMs - earlierMs) / 86_400_000);
}

main().catch((error) => {
  console.error(error.message);
  console.error(
    "\nNothing after that step ran. Every step is idempotent, so fix the error " +
    "and rerun the same command - a rerun repeats the recipe rather than " +
    "doubling it."
  );
  process.exit(1);
});
