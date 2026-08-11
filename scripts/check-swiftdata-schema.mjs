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
  assertBaselineRecordsTypes,
  baselineMatches,
  baselineRecordsTypes,
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
// AscendWatchShared/ is compiled into the app target as well as the watch app,
// so an @Model declared there reaches the same persistent store as one under
// AscendApp/. Every root the app target compiles has to be walked, or the gate
// reports on a subset of the schema while reading as though it covered all of it.
const MODEL_SOURCE_ROOTS = [APP_ROOT, join(REPO_ROOT, "AscendWatchShared")];
const MIGRATIONS_DIR = join(APP_ROOT, "Shared/Models/Migrations");
const PLAN_PATH = join(MIGRATIONS_DIR, "AscendMigrationPlan.swift");
const ENTRY_POINT_PATH = join(APP_ROOT, "App/AscendApp.swift");
const LOCAL_STORE_PATH = join(APP_ROOT, "Shared/Models/AscendLocalStore.swift");
const BASELINE_PATH = join(REPO_ROOT, "SharedTestVectors/swiftdata-schema-shape.json");

/**
 * Reads the persisted-shape facts out of the Swift sources.
 * @return {object} Parsed schemas, models, plan, and the baseline-shaped record they imply.
 */
export function readSchemaFacts() {
  const swiftFiles = MODEL_SOURCE_ROOTS.flatMap(collectSwiftFiles);
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
  const containerSchema = readContainerSchema();
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
 *
 * `typeRuleEvaluated` is a precondition, not a violation. A baseline recorded before per-column
 * types existed leaves the type-change rule with nothing to compare against, and the only way to
 * give it types is to re-record - so modelling it as a violation would make `--update` refuse the
 * one write that fixes it. Every other rule is evaluated as normal, and the caller must refuse to
 * report a pass while this is false.
 * @param {object} facts Output of `readSchemaFacts`.
 * @param {object} baseline The recorded baseline.
 * @return {{violations: string[], baselineStale: boolean, typeRuleEvaluated: boolean}} The result.
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

  return {
    violations,
    baselineStale: !baselineMatches(baseline, facts.record),
    typeRuleEvaluated: baselineRecordsTypes(baseline),
  };
}

/**
 * The `VersionedSchema` the app actually opens its store with.
 *
 * The entry point may name it directly, or defer to `AscendLocalStore` - the one declaration of
 * the live model set that account deletion's sweep and the sign-in ownership gate read too, so
 * none of them can drift from the container (#348). Following that hop keeps this check pointed
 * at what opens the store rather than at whatever the entry point happens to spell out.
 * @return {string} The schema the container opens.
 */
function readContainerSchema() {
  const entryPoint = stripComments(readFileSync(ENTRY_POINT_PATH, "utf-8"));
  const named = /Schema\(versionedSchema:\s*([A-Za-z_][A-Za-z0-9_]*)\.self\)/.exec(entryPoint);
  if (named) return named[1];

  if (!/AscendLocalStore\.schema\b/.test(entryPoint)) {
    throw new Error(
      "AscendApp.swift builds its Schema from neither a VersionedSchema nor AscendLocalStore",
    );
  }

  const localStore = stripComments(readFileSync(LOCAL_STORE_PATH, "utf-8"));
  const deferred = /currentSchema:\s*any VersionedSchema\.Type\s*\{\s*([A-Za-z_][A-Za-z0-9_]*)\.self/
    .exec(localStore);
  if (!deferred) {
    throw new Error("AscendLocalStore.swift does not name a VersionedSchema as currentSchema");
  }
  return deferred[1];
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

/**
 * @param {object} baseline The recorded baseline.
 * @param {object} record The freshly parsed record.
 * @return {object} What to write, carrying the hand-written annotations across.
 */
function recordToWrite(baseline, record) {
  // `customStageColumns` is written by hand, not derived from the sources, so re-recording must
  // carry it across rather than silently erase the one thing a stage's exemption rests on.
  return Array.isArray(baseline.customStageColumns) && baseline.customStageColumns.length > 0
    ? {...record, customStageColumns: [...baseline.customStageColumns].sort()}
    : record;
}

function main() {
  const update = process.argv.includes("--update");
  const facts = readSchemaFacts();
  const baseline = readBaseline();
  const {violations, baselineStale, typeRuleEvaluated} = evaluate(facts, baseline);

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
    writeFileSync(BASELINE_PATH, `${JSON.stringify(recordToWrite(baseline, facts.record), null, 2)}\n`);
    console.log(`Recorded ${relative(REPO_ROOT, BASELINE_PATH)} at ${facts.currentSchema.name}.`);

    if (!typeRuleEvaluated) {
      console.log(
        "\nThe previous baseline recorded no per-column types, so the type-change rule could not " +
        "be evaluated for this run. Every other rule was, and passed. The re-recorded baseline " +
        "carries types, so the rule is armed from the next run on."
      );
    }
    return;
  }

  if (!typeRuleEvaluated) {
    try {
      assertBaselineRecordsTypes(baseline);
    } catch (error) {
      console.error(`SwiftData schema check cannot complete:\n\n  - ${error.message}\n`);
    }
    process.exitCode = 1;
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
