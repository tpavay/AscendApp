#!/usr/bin/env node
/**
 * Fails a schema change that would silently default existing rows, or that would let the model
 * list and the versioned schema drift apart.
 *
 * Both are silent failures on a user's phone: nothing crashes, nothing logs, the data is simply
 * replaced with defaults or never migrated at all. The only place they are visible is here, in the
 * diff, before the binary ships - an iOS binary cannot be rolled back.
 *
 *   node scripts/check-swiftdata-schema.mjs             # verify, exit non-zero on a violation
 *   node scripts/check-swiftdata-schema.mjs --update     # re-record the baseline, if it is legal
 *
 * See `.claude/skills/ascend-data-migration/`.
 */

import {readFileSync, readdirSync, writeFileSync} from "node:fs";
import {join, relative} from "node:path";
import {fileURLToPath} from "node:url";

import {
  baselineMatches,
  checkModelSetAgreement,
  checkShapeDelta,
  parseMigrationPlan,
  parseModels,
  parseVersionedSchema,
  shapeOf,
  stripComments,
} from "./lib/swiftdata-schema-shape.mjs";

const REPO_ROOT = fileURLToPath(new URL("..", import.meta.url));
const APP_ROOT = join(REPO_ROOT, "AscendApp");
const MIGRATIONS_DIR = join(APP_ROOT, "Shared/Models/Migrations");
const PLAN_PATH = join(MIGRATIONS_DIR, "AscendMigrationPlan.swift");
const ENTRY_POINT_PATH = join(APP_ROOT, "App/AscendApp.swift");
const BASELINE_PATH = join(REPO_ROOT, "SharedTestVectors/swiftdata-schema-shape.json");

/**
 * Reads the persisted-shape facts out of the Swift sources.
 * @return {object} Parsed schemas, models, plan, and the baseline-shaped record they imply.
 */
export function readSchemaFacts() {
  const swiftFiles = collectSwiftFiles(APP_ROOT);
  const liveModels = [];
  const frozenModels = [];

  for (const path of swiftFiles) {
    const source = readFileSync(path, "utf-8");
    if (!source.includes("@Model")) continue;

    for (const model of parseModels(source, relative(REPO_ROOT, path))) {
      // A nested @Model is a frozen copy inside a historical VersionedSchema, not a live model.
      (model.nested ? frozenModels : liveModels).push(model);
    }
  }

  const versionedSchemas = readdirSync(MIGRATIONS_DIR)
    .filter((name) => name.endsWith(".swift"))
    .map((name) => parseVersionedSchema(readFileSync(join(MIGRATIONS_DIR, name), "utf-8"), name))
    .filter(Boolean)
    .sort((a, b) => compareVersions(a.versionIdentifier, b.versionIdentifier));

  if (versionedSchemas.length === 0) {
    throw new Error(`no VersionedSchema found under ${relative(REPO_ROOT, MIGRATIONS_DIR)}`);
  }

  const plan = parseMigrationPlan(readFileSync(PLAN_PATH, "utf-8"), relative(REPO_ROOT, PLAN_PATH));
  const containerSchema = readContainerSchema(readFileSync(ENTRY_POINT_PATH, "utf-8"));
  const currentSchema = versionedSchemas.at(-1);

  return {
    liveModels,
    frozenModels,
    currentSchema,
    plan,
    containerSchema,
    record: {
      currentSchema: currentSchema.name,
      versionIdentifier: currentSchema.versionIdentifier,
      customStageCount: plan.customStageCount,
      lightweightStageCount: plan.lightweightStageCount,
      models: shapeOf(liveModels),
      frozenModels: shapeOf(frozenModels),
    },
  };
}

/**
 * Runs both checks against the sources.
 * @param {object} facts Output of `readSchemaFacts`.
 * @param {object} baseline The recorded baseline.
 * @return {{violations: string[], baselineStale: boolean}} The result.
 */
export function evaluate(facts, baseline) {
  const violations = [
    ...checkModelSetAgreement({
      liveModels: facts.liveModels.map((model) => model.name),
      currentSchema: facts.currentSchema,
      planSchemas: facts.plan.schemas,
      containerSchema: facts.containerSchema,
    }),
    ...checkShapeDelta({
      baseline,
      currentShape: facts.record.models,
      frozenShape: facts.record.frozenModels,
      plan: facts.plan,
      currentSchema: facts.currentSchema,
    }),
  ];

  return {violations, baselineStale: !baselineMatches(baseline, facts.record)};
}

/** @param {string} source `AscendApp.swift` text. @return {string} The schema the container opens. */
function readContainerSchema(source) {
  const match = /Schema\(versionedSchema:\s*([A-Za-z_][A-Za-z0-9_]*)\.self\)/
    .exec(stripComments(source));
  if (!match) {
    throw new Error("AscendApp.swift does not build its Schema from a VersionedSchema");
  }
  return match[1];
}

/** @param {string} directory Directory to walk. @return {string[]} Every `.swift` file beneath it. */
function collectSwiftFiles(directory) {
  const found = [];
  for (const entry of readdirSync(directory, {withFileTypes: true})) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      found.push(...collectSwiftFiles(path));
    } else if (entry.name.endsWith(".swift")) {
      found.push(path);
    }
  }
  return found.sort();
}

/** @param {number[]} left Version. @param {number[]} right Version. @return {number} Ordering. */
function compareVersions(left, right) {
  for (let index = 0; index < 3; index += 1) {
    if (left[index] !== right[index]) return left[index] - right[index];
  }
  return 0;
}

/**
 * @return {object} The recorded baseline, or an empty one when it has not been written yet.
 *
 * An absent baseline reads as "nothing has shipped", which makes every model new and therefore
 * exempt - correct only for the bootstrap `--update` that writes the file for the first time. It
 * still leaves the stale-baseline failure below, so an absent baseline can never pass a check.
 */
export function readBaseline() {
  try {
    return JSON.parse(readFileSync(BASELINE_PATH, "utf-8"));
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
    return {currentSchema: null, models: {}, frozenModels: {}, customStageCount: 0};
  }
}

function main() {
  const update = process.argv.includes("--update");
  const facts = readSchemaFacts();
  const {violations, baselineStale} = evaluate(facts, readBaseline());

  if (violations.length > 0) {
    console.error("SwiftData schema check failed:\n");
    for (const violation of violations) {
      console.error(`  - ${violation}\n`);
    }
    console.error("Load .claude/skills/ascend-data-migration before changing this.");
    process.exitCode = 1;
    return;
  }

  if (update) {
    writeFileSync(BASELINE_PATH, `${JSON.stringify(facts.record, null, 2)}\n`);
    console.log(`Recorded ${relative(REPO_ROOT, BASELINE_PATH)} at ${facts.currentSchema.name}.`);
    return;
  }

  if (baselineStale) {
    console.error(
      "The persisted shape no longer matches SharedTestVectors/swiftdata-schema-shape.json.\n" +
      "The change is legal, so re-record it in the same PR:\n\n" +
      "  node scripts/check-swiftdata-schema.mjs --update\n"
    );
    process.exitCode = 1;
    return;
  }

  console.log(`SwiftData schema check passed at ${facts.currentSchema.name}.`);
}

if (process.argv[1] && import.meta.url === `file://${process.argv[1]}`) {
  main();
}
