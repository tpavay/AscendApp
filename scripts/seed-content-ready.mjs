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

import {spawnSync} from "node:child_process";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {applicationDefault, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
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
  seed    Seed the world, then the one named account, then verify. The default.
          Idempotent: running it twice leaves the same state.
  verify  Read-only. Re-check the content-ready contract and report.
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
    await verify(account);
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

  seedWorld(projectId, args);
  seedAccount(projectId, args, account);

  if (args.dryRun) {
    console.log("\nDry run only. Nothing was written, so there is nothing to verify.");
    return;
  }

  runAudit(projectId);
  if (!await verify(account)) {
    return;
  }

  console.log(
    "\nStaging is content-ready. Reinstall or sign out and back in on the " +
    "capture device so it hydrates the new state."
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

function runAudit(projectId) {
  runScript("audit-seed-data.mjs", ["--project", projectId, "--target", "all"]);
}

/**
 * Runs one composed script, failing this command when it fails.
 * @param {string} script Script filename under `scripts/`.
 * @param {string[]} scriptArgs Arguments to pass through.
 */
function runScript(script, scriptArgs) {
  console.log(`\n> node ${script} ${scriptArgs.join(" ")}`);
  const result = spawnSync(
    process.execPath,
    [resolve(SCRIPT_DIR, script), ...scriptArgs],
    {cwd: SCRIPT_DIR, stdio: "inherit"}
  );

  if (result.status !== 0) {
    throw new Error(`${script} exited ${result.status}`);
  }
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
  const rows = await sampleSeededRows(summaries.docs);

  return {
    hasPublicProfile: publicProfile.exists,
    hasProfileStats: profileStats.exists,
    accountDisplayName: publicProfile.data()?.displayName ?? null,
    seededRowsSampled: rows.sampled,
    seededRowsWithoutPhoto: rows.withoutPhoto,
    seededRowsWithPlaceholderName: rows.withPlaceholderName,
    rowsWithoutPhotoExamples: rows.withoutPhotoExamples,
    workoutCount: workouts.size,
    climbsCompleted: numberValue(stats.total_climbs_completed) ?? 0,
    firstAscentsHeld: heldFirstAscents.length,
    firstAscentBoards: heldFirstAscents.map((document) => ({
      contextKey: document.id,
      completedCount: numberValue(document.data().completedCount) ?? 0,
      totalClimbers: numberValue(document.data().totalClimbers) ?? 0,
    })),
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
