#!/usr/bin/env node

/**
 * Remote Routine Template Seed Script
 *
 * Seeds or clears dev/staging routine template content in:
 *
 * routine_templates/{templateId}
 *
 * Usage:
 *   node scripts/seed-routine-templates.mjs seed --project dev
 *   node scripts/seed-routine-templates.mjs seed --project dev --dry-run
 *   node scripts/seed-routine-templates.mjs clear --project dev
 *   node scripts/seed-routine-templates.mjs seed --project staging --file scripts/fixtures/routine-templates.dev.json
 *
 * Prerequisites:
 *   Node.js 20+
 *   cd scripts && npm install
 *   gcloud auth application-default login
 */

import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {applicationDefault, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {createBatchWriter, createProgressReporter} from "./lib/firestore-bulk.mjs";

const DEV_PROJECT_ID = "ascend-f2e4f";
const STAGING_PROJECT_ID = "ascend-staging-fa7d5";
const PRODUCTION_PROJECT_ID = "ascend-prod-9c8f2";
const DEFAULT_DEV_SEED_PACK_ID = "routine-templates-v1-dev";
const DEFAULT_STAGING_SEED_PACK_ID = "routine-templates-v1-staging";
const COLLECTION_ID = "routine_templates";
const VALID_STATUSES = new Set(["draft", "published", "archived"]);
const VALID_BROWSE_SECTIONS = new Set(["getting_started", "gettingStarted"]);
const VALID_ZONES = new Set([
  "recovery",
  "warmup",
  "easy",
  "steady",
  "tempo",
  "threshold",
  "sprint",
  "allOut",
]);
const VALID_SIDEWAYS_DIRECTIONS = new Set(["left", "right"]);
const ALLOWED_SEED_PROJECTS = new Map([
  [DEV_PROJECT_ID, {defaultSeedPackId: DEFAULT_DEV_SEED_PACK_ID}],
  [STAGING_PROJECT_ID, {defaultSeedPackId: DEFAULT_STAGING_SEED_PACK_ID}],
]);

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(SCRIPT_DIR, "..");
const DEFAULT_TEMPLATE_FILE = resolve(SCRIPT_DIR, "fixtures/routine-templates.dev.json");

function parseArgs(argv) {
  const args = {
    command: argv[2] ?? "help",
    project: "dev",
    dryRun: false,
    skipClear: false,
    file: DEFAULT_TEMPLATE_FILE,
    seedPackId: null,
  };

  for (let index = 3; index < argv.length; index += 1) {
    const value = argv[index];
    switch (value) {
      case "--project":
        args.project = requireValue(argv, ++index, value);
        break;
      case "--file":
        args.file = resolve(REPO_ROOT, requireValue(argv, ++index, value));
        break;
      case "--seed-pack":
        args.seedPackId = requireValue(argv, ++index, value);
        break;
      case "--dry-run":
        args.dryRun = true;
        break;
      case "--skip-clear":
        args.skipClear = true;
        break;
      case "--help":
      case "-h":
        args.command = "help";
        break;
      default:
        throw new Error(`Unknown argument: ${value}`);
    }
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
Usage:
  node scripts/seed-routine-templates.mjs seed --project dev
  node scripts/seed-routine-templates.mjs seed --project dev --dry-run
  node scripts/seed-routine-templates.mjs clear --project dev
  node scripts/seed-routine-templates.mjs seed --project staging --file scripts/fixtures/routine-templates.dev.json

Options:
  --project <dev|staging|projectId>  Defaults to dev. Production is refused.
  --file <path>                      JSON file containing routine templates.
  --seed-pack <id>                   Seed pack marker. Defaults by project.
  --dry-run                          Print plans without writing.
  --skip-clear                       Seed without clearing this seed pack first.
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
  const projectConfig = ALLOWED_SEED_PROJECTS.get(projectId);
  if (!projectConfig || projectId === PRODUCTION_PROJECT_ID) {
    throw new Error(
      `Refusing to seed ${projectId}. This script only writes ${DEV_PROJECT_ID} or ${STAGING_PROJECT_ID}.`
    );
  }
  args.seedPackId = args.seedPackId ?? projectConfig.defaultSeedPackId;

  const templates = args.command === "seed" ? loadTemplates(args.file) : [];
  printPlan(projectId, args, templates);

  if (args.dryRun) {
    console.log("Dry run only. No Firestore writes were made.");
    return;
  }

  initializeApp({credential: applicationDefault(), projectId});
  const db = getFirestore();

  if (args.command === "clear") {
    const deleted = await clearSeedPack(db, args.seedPackId);
    console.log(`Cleared ${deleted.toLocaleString()} routine template document(s).`);
    return;
  }

  if (!args.skipClear) {
    const deleted = await clearSeedPack(db, args.seedPackId);
    console.log(`Cleared ${deleted.toLocaleString()} existing routine template document(s).`);
  }

  await seedTemplates(db, templates, args.seedPackId);
  console.log(`Seeded ${templates.length.toLocaleString()} routine template document(s).`);
}

function resolveProjectId(projectOrAlias) {
  const rc = JSON.parse(readFileSync(resolve(REPO_ROOT, ".firebaserc"), "utf-8"));
  return rc.projects?.[projectOrAlias] ?? projectOrAlias;
}

function loadTemplates(filePath) {
  const parsed = JSON.parse(readFileSync(filePath, "utf-8"));
  if (!Array.isArray(parsed)) {
    throw new Error("Routine template fixture must be a JSON array");
  }
  if (parsed.length === 0) {
    throw new Error("Routine template fixture must contain at least one template");
  }

  const seenIds = new Set();
  return parsed.map((template, index) => normalizeTemplate(template, index, seenIds));
}

function normalizeTemplate(template, index, seenIds) {
  const templateId = stringField(template, "templateId", index);
  if (!/^[A-Za-z0-9_-]{1,120}$/.test(templateId)) {
    throw new Error(`Template ${index} has invalid templateId "${templateId}"`);
  }
  if (seenIds.has(templateId)) {
    throw new Error(`Duplicate templateId "${templateId}"`);
  }
  seenIds.add(templateId);

  const status = stringField(template, "status", index);
  if (!VALID_STATUSES.has(status)) {
    throw new Error(`Template ${templateId} has invalid status "${status}"`);
  }

  const name = stringField(template, "name", index).trim();
  if (name.length === 0 || name.length > 120) {
    throw new Error(`Template ${templateId} name must be 1-120 characters`);
  }

  const intervals = arrayField(template, "intervals", index).map((interval, intervalIndex) =>
    normalizeInterval(interval, templateId, intervalIndex)
  );
  if (intervals.length === 0 || intervals.length > 80) {
    throw new Error(`Template ${templateId} must have 1-80 intervals`);
  }

  const browseSections = Array.isArray(template.browseSections)
    ? template.browseSections
    : (Array.isArray(template.browse_sections) ? template.browse_sections : []);
  for (const section of browseSections) {
    if (!VALID_BROWSE_SECTIONS.has(section)) {
      throw new Error(`Template ${templateId} has unsupported browse section "${section}"`);
    }
  }

  const version = optionalInteger(template.version, "version", templateId) ?? 1;
  if (version < 1) {
    throw new Error(`Template ${templateId} version must be at least 1`);
  }

  const difficulty = optionalInteger(template.difficulty, "difficulty", templateId);
  if (difficulty != null && (difficulty < 1 || difficulty > 5)) {
    throw new Error(`Template ${templateId} difficulty must be 1-5`);
  }

  const estimatedCalories = optionalInteger(
    template.estimatedCalories ?? template.estimated_calories,
    "estimatedCalories",
    templateId
  );
  if (estimatedCalories != null && estimatedCalories < 0) {
    throw new Error(`Template ${templateId} estimatedCalories must be non-negative`);
  }

  const normalized = {
    templateId,
    status,
    version,
    name,
    description: optionalString(
      template.description ?? template.routineDescription,
      "description",
      templateId
    ) ?? "",
    difficulty,
    estimatedCalories,
    isFeatured: Boolean(template.isFeatured ?? template.is_featured),
    displayOrder: optionalInteger(
      template.displayOrder ?? template.display_order,
      "displayOrder",
      templateId
    ) ?? index,
    featuredOrder: optionalInteger(
      template.featuredOrder ?? template.featured_order,
      "featuredOrder",
      templateId
    ),
    browseSections,
    intervals,
  };

  const minAppVersion = template.minAppVersion ?? template.min_app_version;
  if (minAppVersion != null) {
    normalized.minAppVersion = optionalString(minAppVersion, "minAppVersion", templateId);
  }

  return Object.fromEntries(
    Object.entries(normalized).filter(([, value]) => value !== undefined && value !== null)
  );
}

function normalizeInterval(interval, templateId, index) {
  if (!interval || typeof interval !== "object" || Array.isArray(interval)) {
    throw new Error(`Template ${templateId} interval ${index} must be an object`);
  }

  const durationSeconds = optionalNumber(interval.durationSeconds, "durationSeconds", templateId)
    ?? optionalNumber(interval.duration_seconds, "duration_seconds", templateId)
    ?? optionalNumber(interval.duration, "duration", templateId);
  if (!Number.isFinite(durationSeconds) || durationSeconds <= 0 || durationSeconds > 7200) {
    throw new Error(`Template ${templateId} interval ${index} needs durationSeconds from 1-7200`);
  }

  const normalized = {durationSeconds};
  const intensityKeys = ["zone", "level", "spm", "intensityType", "intensity_type"];
  const presentIntensityKeys = intensityKeys.filter((key) => interval[key] != null);
  if (presentIntensityKeys.length === 0) {
    throw new Error(`Template ${templateId} interval ${index} needs zone, level, or spm`);
  }

  if (interval.zone != null) {
    normalized.zone = optionalString(interval.zone, "zone", templateId);
    if (!VALID_ZONES.has(normalized.zone)) {
      throw new Error(`Template ${templateId} interval ${index} has unsupported zone "${normalized.zone}"`);
    }
  } else {
    const rawType = optionalString(
      interval.intensityType ?? interval.intensity_type,
      "intensityType",
      templateId
    ) ?? (interval.spm != null ? "spm" : "level");
    const normalizedType = rawType.toLowerCase();
    const intensityValue = optionalInteger(
      interval.intensityValue ?? interval.intensity_value,
      "intensityValue",
      templateId
    );

    switch (normalizedType) {
    case "stepsperminute":
    case "steps_per_minute":
    case "spm":
      normalized.intensityType = "spm";
      normalized.spm = intensityValue ?? optionalInteger(interval.spm, "spm", templateId);
      if (!Number.isInteger(normalized.spm) || normalized.spm < 1 || normalized.spm > 260) {
        throw new Error(`Template ${templateId} interval ${index} spm must be 1-260`);
      }
      break;
    case "level":
      normalized.level = intensityValue ?? optionalInteger(interval.level, "level", templateId);
      if (!Number.isInteger(normalized.level) || normalized.level < 1 || normalized.level > 25) {
        throw new Error(`Template ${templateId} interval ${index} level must be 1-25`);
      }
      break;
    default:
      throw new Error(`Template ${templateId} interval ${index} has unsupported intensity type "${rawType}"`);
    }
  }

  const modifiers = normalizeModifiers(interval.modifiers ?? interval);
  if (Object.keys(modifiers).length > 0) {
    normalized.modifiers = modifiers;
  }

  return normalized;
}

function normalizeModifiers(modifiers) {
  if (!modifiers || typeof modifiers !== "object" || Array.isArray(modifiers)) {
    throw new Error("Interval modifiers must be an object");
  }

  const normalized = {};
  const sidewaysDirection = modifiers.sidewaysDirection ?? modifiers.sideways_direction;
  if (sidewaysDirection != null) {
    if (!VALID_SIDEWAYS_DIRECTIONS.has(sidewaysDirection)) {
      throw new Error(`Unsupported sidewaysDirection "${sidewaysDirection}"`);
    }
    normalized.sidewaysDirection = sidewaysDirection;
  }

  const booleanFields = [
    ["skipStep", "skip_step"],
    ["backwardStep", "backward_step"],
    ["holdingBars", "holding_bars"],
  ];
  for (const [camelField, snakeField] of booleanFields) {
    const value = modifiers[camelField] ?? modifiers[snakeField];
    if (value != null) {
      if (typeof value !== "boolean") {
        throw new Error(`${camelField} modifier must be boolean`);
      }
      normalized[camelField] = value;
    }
  }

  return normalized;
}

function stringField(object, field, index) {
  const value = object?.[field];
  if (typeof value !== "string") {
    throw new Error(`Template ${index} requires string ${field}`);
  }
  return value;
}

function arrayField(object, field, index) {
  const value = object?.[field];
  if (!Array.isArray(value)) {
    throw new Error(`Template ${index} requires array ${field}`);
  }
  return value;
}

function optionalString(value, field, templateId) {
  if (value == null) {
    return undefined;
  }
  if (typeof value !== "string") {
    throw new Error(`Template ${templateId} ${field} must be a string`);
  }
  return value;
}

function optionalInteger(value, field, templateId) {
  if (value == null) {
    return undefined;
  }
  if (!Number.isInteger(value)) {
    throw new Error(`Template ${templateId} ${field} must be an integer`);
  }
  return value;
}

function optionalNumber(value, field, templateId) {
  if (value == null) {
    return undefined;
  }
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new Error(`Template ${templateId} ${field} must be a finite number`);
  }
  return value;
}

function printPlan(projectId, args, templates) {
  console.log(`Project: ${projectId}`);
  console.log(`Command: ${args.command}${args.dryRun ? " (dry run)" : ""}`);
  console.log(`Seed pack: ${args.seedPackId}`);
  console.log(`Collection: ${COLLECTION_ID}`);

  if (args.command === "seed") {
    console.log(`Fixture: ${args.file}`);
    console.log(`Templates: ${templates.map((template) => `${template.templateId} (${template.status})`).join(", ")}`);
  }
}

async function seedTemplates(db, templates, seedPackId) {
  const progress = createProgressReporter({label: "Routine templates", total: templates.length});
  const writer = createBatchWriter(db, {progress});
  const now = FieldValue.serverTimestamp();

  for (const template of templates) {
    writer.set(
      db.collection(COLLECTION_ID).doc(template.templateId),
      {
        ...template,
        seedPackId,
        updatedAt: now,
      },
      {merge: false}
    );
  }

  await writer.drain();
  progress.finish();
}

async function clearSeedPack(db, seedPackId) {
  const snapshot = await db.collection(COLLECTION_ID)
    .where("seedPackId", "==", seedPackId)
    .get();

  if (snapshot.empty) {
    return 0;
  }

  const progress = createProgressReporter({label: "Routine templates (clear)", total: snapshot.size});
  const writer = createBatchWriter(db, {progress});
  for (const doc of snapshot.docs) {
    writer.delete(doc.ref);
  }

  const deleted = await writer.drain();
  progress.finish();
  return deleted;
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
