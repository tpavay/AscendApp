#!/usr/bin/env node

/**
 * Profile Test User Seeder
 *
 * Seeds or clears public profile data for dev/staging QA. Uses Firebase Admin SDK
 * and refuses production.
 *
 * Usage:
 *   node scripts/seed-test-users.mjs seed --project dev
 *   node scripts/seed-test-users.mjs clear --project staging
 *   node scripts/seed-test-users.mjs seed --project dev --dry-run
 */

import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {applicationDefault, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";

const DEV_PROJECT_ID = "ascend-f2e4f";
const STAGING_PROJECT_ID = "ascend-staging-fa7d5";
const SEED_PACK_ID = "v1-profile-test";
const SEED_SOURCE = "seed-test-users";
const SCHEMA_VERSION = 2;
const BATCH_LIMIT = 450;

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(SCRIPT_DIR, "..");

const ALLOWED_PROJECTS = new Set([DEV_PROJECT_ID, STAGING_PROJECT_ID]);

const PERSONAS = [
  {id: "profile_veteran_champion", name: "Tyler R.", age: 32, gender: "man", weightLb: 178, country: "US", region: "IL", climbs: 47, firstAscents: 4, top1: 3, top3: 11, top10: 18, top100: 31, streak: 15, weeklySteps: 42000, climbIds: ["empire-state-building", "space-needle", "statue-of-liberty", "burj-khalifa", "eiffel-tower"]},
  {id: "profile_newcomer", name: "Jonas B.", age: 27, gender: "man", weightLb: 165, country: "DE", region: "BE", climbs: 0, firstAscents: 0, top1: 0, top3: 0, top10: 0, top100: 0, streak: 0, joinedOffsetDays: -1, climbIds: []},
  {id: "profile_active_recent", name: "Mara S.", age: 41, gender: "woman", weightLb: 145, country: "AU", region: "NSW", climbs: 6, firstAscents: 0, top1: 0, top3: 0, top10: 0, top100: 0, streak: 3, climbIds: ["sydney-tower", "space-needle", "statue-of-liberty"]},
  {id: "profile_fa_collector", name: "Ren K.", age: 28, gender: "non_binary", weightLb: 152, country: "JP", region: "13", climbs: 8, firstAscents: 5, top1: 0, top3: 0, top10: 0, top100: 0, streak: 4, climbIds: ["tokyo-tower", "tokyo-skytree", "cairo-tower", "gateway-arch"]},
  {id: "profile_medal_heavy", name: "Naledi M.", age: 55, gender: "woman", weightLb: 168, country: "ZA", region: "WC", climbs: 22, firstAscents: 0, top1: 1, top3: 6, top10: 14, top100: 22, streak: 8, climbIds: ["table-mountain", "eiffel-tower", "cn-tower", "gateway-arch"]},
  {id: "profile_peer_veteran", name: "Caleb H.", age: 27, gender: "man", weightLb: 175, country: "US", region: "TX", climbs: 5, firstAscents: 0, top1: 0, top3: 1, top10: 2, top100: 5, streak: 2, climbIds: ["empire-state-building", "space-needle", "statue-of-liberty"]},
  {id: "profile_no_overlap_peer", name: "Dayo A.", age: 27, gender: "man", weightLb: 180, country: "NG", region: "LA", climbs: 4, firstAscents: 0, top1: 0, top3: 0, top10: 1, top100: 4, streak: 1, climbIds: ["cairo-tower", "sagrada-familia", "colosseum", "leaning-tower-of-pisa"]},
  {id: "profile_tied_gold", name: "Mateo G.", age: 30, gender: "man", weightLb: 170, country: "ES", region: "MD", climbs: 12, firstAscents: 1, top1: 1, top3: 2, top10: 6, top100: 12, streak: 5, weeklySteps: 42000, climbIds: ["sagrada-familia", "gateway-arch", "eiffel-tower"]},
  {id: "profile_streak_heavy", name: "Hana W.", age: 35, gender: "woman", weightLb: 138, country: "NZ", region: "AUK", climbs: 33, firstAscents: 1, top1: 0, top3: 4, top10: 9, top100: 20, streak: 28, climbIds: ["sky-tower-auckland", "sydney-tower", "space-needle"]},
  {id: "profile_privacy_edge", name: "Anika P.", age: 19, gender: "woman", weightLb: 110, country: "IN", region: "MH", climbs: 3, firstAscents: 0, top1: 0, top3: 0, top10: 0, top100: 1, streak: 1, climbIds: ["gateway-arch", "statue-of-liberty"]},
  {id: "profile_older_athlete", name: "Victor P.", age: 68, gender: "man", weightLb: 195, country: "US", region: "AZ", climbs: 18, firstAscents: 1, top1: 0, top3: 2, top10: 8, top100: 18, streak: 9, climbIds: ["willis-tower", "one-world-trade-center", "empire-state-building"]},
  {id: "profile_empty_achievements", name: "Linnea S.", age: 24, gender: "non_binary", weightLb: 160, country: "SE", region: "AB", climbs: 2, firstAscents: 0, top1: 0, top3: 0, top10: 0, top100: 0, streak: 1, climbIds: ["space-needle", "statue-of-liberty"]},
];

function parseArgs(argv) {
  const args = {command: argv[2] ?? "help", project: "dev", dryRun: false};
  for (let index = 3; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--project") args.project = requireValue(argv, ++index, value);
    else if (value === "--dry-run") args.dryRun = true;
    else if (value === "--help" || value === "-h") args.command = "help";
    else throw new Error(`Unknown argument: ${value}`);
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
  node scripts/seed-test-users.mjs seed --project dev
  node scripts/seed-test-users.mjs clear --project staging
  node scripts/seed-test-users.mjs seed --project dev --dry-run
`);
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.command === "help") {
    printHelp();
    return;
  }
  if (!["seed", "clear"].includes(args.command)) {
    throw new Error("Command must be seed, clear, or help");
  }

  const projectId = resolveProjectId(args.project);
  if (!ALLOWED_PROJECTS.has(projectId)) {
    throw new Error(`Refusing to write ${projectId}. Only ${DEV_PROJECT_ID} and ${STAGING_PROJECT_ID} are allowed.`);
  }

  initializeApp({credential: applicationDefault(), projectId});
  const db = getFirestore();
  const catalog = loadCatalog();

  console.log(`Project: ${projectId}`);
  console.log(`Seed pack: ${SEED_PACK_ID}`);
  console.log(`Command: ${args.command}${args.dryRun ? " (dry run)" : ""}`);
  console.log(`Personas: ${PERSONAS.length}`);

  if (args.dryRun) return;

  if (args.command === "clear") {
    const deleted = await clearSeedPack(db);
    console.log(`Deleted ${deleted} seeded documents.`);
    return;
  }

  await clearSeedPack(db);
  const writes = buildWrites(db, catalog);
  await commitWrites(db, writes);
  console.log(`Wrote ${writes.length} seeded documents.`);
}

function resolveProjectId(alias) {
  if (ALLOWED_PROJECTS.has(alias)) return alias;
  const rc = JSON.parse(readFileSync(resolve(REPO_ROOT, ".firebaserc"), "utf-8"));
  const projectId = rc.projects?.[alias];
  if (!projectId) throw new Error(`No project alias "${alias}" found in .firebaserc`);
  return projectId;
}

function loadCatalog() {
  const raw = JSON.parse(readFileSync(resolve(REPO_ROOT, "web/public/climbs/catalog-v1.json"), "utf-8"));
  const climbs = Array.isArray(raw) ? raw : raw.climbs;
  return new Map(climbs.map((climb) => [climb.id, climb]));
}

function buildWrites(db, catalog) {
  const writes = [];
  const now = new Date();
  const periods = currentPeriods(now);

  for (const persona of PERSONAS) {
    const joinedAt = daysFromNow(persona.joinedOffsetDays ?? -60);
    const userRef = db.collection("users").doc(persona.id);
    const publicRef = userRef.collection("public_profile").doc("current");
    const statsRef = userRef.collection("profile_stats").doc("current");
    const workouts = buildWorkouts(persona, catalog, now);
    const stats = statsFor(persona, workouts);

    writes.push([userRef, {
      email: `${persona.id}@example.invalid`,
      firstName: persona.name.split(" ")[0],
      lastName: persona.name.split(" ").slice(1).join(" "),
      displayName: persona.name,
      profilePictureURL: avatarURL(persona.name),
      age: persona.age,
      gender: persona.gender,
      weight_kg: poundsToKg(persona.weightLb),
      location_country: persona.country,
      location_region: persona.region,
      joined_at: Timestamp.fromDate(joinedAt),
      createdAt: Timestamp.fromDate(joinedAt),
      lastUpdated: FieldValue.serverTimestamp(),
      isSynthetic: true,
      source: SEED_SOURCE,
      seedPackId: SEED_PACK_ID,
    }]);

    writes.push([publicRef, {
      userId: persona.id,
      displayName: persona.name,
      photoURL: avatarURL(persona.name),
      age: persona.age,
      gender: persona.gender,
      weight_kg: poundsToKg(persona.weightLb),
      location_country: persona.country,
      location_region: persona.region,
      joined_at: Timestamp.fromDate(joinedAt),
      lastUpdated: FieldValue.serverTimestamp(),
      isSynthetic: true,
      source: SEED_SOURCE,
      seedPackId: SEED_PACK_ID,
    }]);

    writes.push([statsRef, {
      ...stats,
      lastUpdated: FieldValue.serverTimestamp(),
      isSynthetic: true,
      source: SEED_SOURCE,
      seedPackId: SEED_PACK_ID,
    }]);

    for (const workout of workouts) {
      writes.push([userRef.collection("profile_workouts").doc(workout.id), workout]);
    }

    for (const achievement of buildAchievements(persona, now)) {
      writes.push([userRef.collection("achievements").doc(achievement.id), achievement]);
    }

    for (const [timeFrame, period] of Object.entries(periods)) {
      const steps = leaderboardSteps(persona, timeFrame, stats.total_climbs_completed);
      writes.push([db.collection("leaderboard_stats").doc(`${persona.id}_${timeFrame}`), {
        userId: persona.id,
        displayName: persona.name,
        photoURL: avatarURL(persona.name),
        timeFrame,
        schemaVersion: SCHEMA_VERSION,
        periodKey: period.key,
        periodStartAt: Timestamp.fromDate(period.startAt),
        totalSteps: steps,
        totalFloors: Math.floor(steps / 16),
        totalWorkouts: Math.max(1, Math.ceil(steps / 2200)),
        totalDuration: Math.max(900, Math.floor(steps / 78 * 60)),
        stepsPerMinute: 78,
        lastUpdated: FieldValue.serverTimestamp(),
        isSynthetic: true,
        source: SEED_SOURCE,
        seedPackId: SEED_PACK_ID,
      }]);
    }
  }

  return writes;
}

function buildWorkouts(persona, catalog, now) {
  const workouts = [];
  for (let index = 0; index < persona.climbs; index += 1) {
    const climbId = persona.climbIds[index % Math.max(persona.climbIds.length, 1)];
    const climb = catalog.get(climbId);
    const steps = climb?.realStairCount ?? climb?.totalSteps ?? 1000 + index * 50;
    const durationSeconds = Math.max(360, Math.floor(steps / (72 + (index % 16)) * 60));
    const date = new Date(now.getTime() - index * 2 * 24 * 60 * 60 * 1000);
    workouts.push({
      id: deterministicUUID(`${persona.id}-${index}`),
      name: climb ? `${climb.name} Climb` : "Stair Climb",
      startedAt: Timestamp.fromDate(date),
      durationSeconds,
      steps,
      source: climb ? "headphone_motion" : "manual",
      climbId: climb?.id ?? "",
      climbTier: climb?.tier ?? "common",
      lastUpdated: FieldValue.serverTimestamp(),
      isSynthetic: true,
      sourceLabel: SEED_SOURCE,
      seedPackId: SEED_PACK_ID,
    });
  }
  return workouts;
}

function statsFor(persona, workouts) {
  const mostCompleted = persona.climbIds[0] ?? "";
  const maxSteps = Math.max(0, ...workouts.map((workout) => workout.steps));
  const maxDuration = Math.max(0, ...workouts.map((workout) => workout.durationSeconds));
  const maxSpm = Math.max(0, ...workouts.map((workout) => workout.durationSeconds > 0 ? workout.steps / (workout.durationSeconds / 60) : 0));
  return {
    total_climbs_completed: persona.climbs,
    total_first_ascents: persona.firstAscents,
    top_1_weeks: persona.top1,
    top_3_weeks: persona.top3,
    top_10_weeks: persona.top10,
    top_100_weeks: persona.top100,
    most_completed_climb_id: mostCompleted,
    current_streak_weeks: persona.streak,
    best_streak_weeks: Math.max(persona.streak, persona.streak + 3),
    pr_most_steps: maxSteps,
    pr_longest_climb_seconds: maxDuration,
    pr_highest_spm: maxSpm,
  };
}

function buildAchievements(persona, now) {
  const achievements = [];
  addAchievements(achievements, persona, "weekly_top_1", persona.top1, now);
  addAchievements(achievements, persona, "weekly_top_3", persona.top3 - persona.top1, now);
  addAchievements(achievements, persona, "weekly_top_10", persona.top10 - persona.top3, now);
  addAchievements(achievements, persona, "weekly_top_100", persona.top100 - persona.top10, now);
  for (let index = 0; index < persona.firstAscents; index += 1) {
    achievements.push({
      id: `${persona.id}_first_ascent_${index}`,
      type: "first_ascent",
      climbId: persona.climbIds[index % persona.climbIds.length] ?? "unknown",
      earnedAt: Timestamp.fromDate(daysFromNow(-90 - index, now)),
      rank: 1,
      isSynthetic: true,
      source: SEED_SOURCE,
      seedPackId: SEED_PACK_ID,
    });
  }
  return achievements;
}

function addAchievements(items, persona, type, count, now) {
  for (let index = 0; index < Math.max(count, 0); index += 1) {
    items.push({
      id: `${persona.id}_${type}_${index}`,
      type,
      periodKey: `2026-W${String(20 - (index % 10)).padStart(2, "0")}`,
      earnedAt: Timestamp.fromDate(daysFromNow(-7 * (index + 1), now)),
      rank: rankForType(type),
      isSynthetic: true,
      source: SEED_SOURCE,
      seedPackId: SEED_PACK_ID,
    });
  }
}

function rankForType(type) {
  if (type.endsWith("top_1")) return 1;
  if (type.endsWith("top_3")) return 3;
  if (type.endsWith("top_10")) return 7;
  return 42;
}

async function clearSeedPack(db) {
  const refs = [];
  for (const persona of PERSONAS) {
    const userRef = db.collection("users").doc(persona.id);
    refs.push(userRef);
    refs.push(userRef.collection("public_profile").doc("current"));
    refs.push(userRef.collection("profile_stats").doc("current"));
    const workouts = await userRef.collection("profile_workouts").get();
    const achievements = await userRef.collection("achievements").get();
    workouts.docs.forEach((doc) => refs.push(doc.ref));
    achievements.docs.forEach((doc) => refs.push(doc.ref));
    ["weekly", "monthly", "yearly"].forEach((timeFrame) => {
      refs.push(db.collection("leaderboard_stats").doc(`${persona.id}_${timeFrame}`));
    });
  }
  await commitDeletes(db, refs);
  return refs.length;
}

async function commitWrites(db, writes) {
  for (let index = 0; index < writes.length; index += BATCH_LIMIT) {
    const batch = db.batch();
    for (const [ref, data] of writes.slice(index, index + BATCH_LIMIT)) {
      batch.set(ref, data, {merge: true});
    }
    await batch.commit();
  }
}

async function commitDeletes(db, refs) {
  for (let index = 0; index < refs.length; index += BATCH_LIMIT) {
    const batch = db.batch();
    refs.slice(index, index + BATCH_LIMIT).forEach((ref) => batch.delete(ref));
    await batch.commit();
  }
}

function currentPeriods(now) {
  return {
    weekly: weeklyPeriod(now),
    monthly: {key: `${now.getUTCFullYear()}-M${String(now.getUTCMonth() + 1).padStart(2, "0")}`, startAt: new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1))},
    yearly: {key: `${now.getUTCFullYear()}`, startAt: new Date(Date.UTC(now.getUTCFullYear(), 0, 1))},
  };
}

function weeklyPeriod(date) {
  const start = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const daysSinceMonday = (start.getUTCDay() + 6) % 7;
  start.setUTCDate(start.getUTCDate() - daysSinceMonday);
  const yearStart = new Date(Date.UTC(start.getUTCFullYear(), 0, 1));
  const firstMondayOffset = (yearStart.getUTCDay() + 6) % 7;
  yearStart.setUTCDate(yearStart.getUTCDate() - firstMondayOffset);
  const week = Math.floor((start - yearStart) / (7 * 24 * 60 * 60 * 1000)) + 1;
  return {key: `${start.getUTCFullYear()}-W${String(week).padStart(2, "0")}`, startAt: start};
}

function leaderboardSteps(persona, timeFrame, climbs) {
  if (persona.weeklySteps && timeFrame === "weekly") return persona.weeklySteps;
  const base = Math.max(climbs, 1) * 1400;
  if (timeFrame === "monthly") return base * 4;
  if (timeFrame === "yearly") return base * 32;
  return base;
}

function poundsToKg(value) {
  return Math.round(value * 0.453592 * 10) / 10;
}

function daysFromNow(days, base = new Date()) {
  return new Date(base.getTime() + days * 24 * 60 * 60 * 1000);
}

function avatarURL(name) {
  return `https://ui-avatars.com/api/?name=${encodeURIComponent(name)}&size=200&background=1D4ED8&color=fff&bold=true&format=png`;
}

function deterministicUUID(input) {
  let hash = 0;
  for (let index = 0; index < input.length; index += 1) {
    hash = (hash * 31 + input.charCodeAt(index)) >>> 0;
  }
  const hex = hash.toString(16).padStart(8, "0");
  return `${hex.slice(0, 8)}-0000-4000-8000-${hex}${hex}`.slice(0, 36);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
