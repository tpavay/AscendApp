import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {readFileSync, readdirSync} from "node:fs";
import {dirname, extname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {test} from "node:test";

import {
  PROTECTED_WIPE_COLLECTION_IDS,
  classifyWipeCollections,
  reviewedWipeCollectionIds,
  sourceDeclaredTopLevelCollectionIds,
  topLevelRuleCollectionIds,
} from "../lib/firestore-wipe-policy.mjs";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");

test("wipe deletes reviewed data while preserving the migration ledger", () => {
  const plan = classifyWipeCollections(
    ["users", "_migrations", "notification_devices", "leaderboard_periods"],
    reviewedWipeCollectionIds(REPO_ROOT)
  );

  assert.deepEqual(plan.collectionsToDelete, [
    "users",
    "leaderboard_periods",
    "notification_devices",
  ]);
  assert.deepEqual(plan.protectedCollections, ["_migrations"]);
  assert.deepEqual(plan.unknownCollections, []);
});

test("records are deleted before the projections their triggers rederive", () => {
  const plan = classifyWipeCollections(
    [
      "live_replay_leaderboards",
      "leaderboard_stats",
      "users",
      "leaderboard_periods",
    ],
    reviewedWipeCollectionIds(REPO_ROOT)
  );

  assert.equal(plan.collectionsToDelete[0], "users");
  assert.deepEqual(plan.collectionsToDelete.slice(1), [
    "leaderboard_periods",
    "leaderboard_stats",
    "live_replay_leaderboards",
  ]);
});

test("a new unreviewed top-level collection still blocks the wipe", () => {
  const plan = classifyWipeCollections(
    ["users", "new_unreviewed_collection"],
    reviewedWipeCollectionIds(REPO_ROOT)
  );

  assert.deepEqual(plan.collectionsToDelete, ["users"]);
  assert.deepEqual(plan.protectedCollections, []);
  assert.deepEqual(plan.unknownCollections, ["new_unreviewed_collection"]);
});

test("every source-declared root collection is reviewed or protected", () => {
  const reviewed = new Set(reviewedWipeCollectionIds(REPO_ROOT));
  const protectedIds = new Set(PROTECTED_WIPE_COLLECTION_IDS);
  const declared = new Set();

  for (const path of sourceFiles(resolve(REPO_ROOT, "functions", "src"))) {
    addDeclaredCollections(declared, path);
  }
  for (const path of sourceFiles(resolve(REPO_ROOT, "scripts"), new Set(["test"]))) {
    addDeclaredCollections(declared, path);
  }

  const unreviewed = [...declared]
    .filter((collectionId) => !reviewed.has(collectionId) && !protectedIds.has(collectionId))
    .sort();

  assert.deepEqual(
    unreviewed,
    [],
    "root collections used by source must have a top-level Firestore rule or explicit protection"
  );
});

test("the rules parser returns direct database children only", () => {
  const rules = readFileSync(resolve(REPO_ROOT, "firestore.rules"), "utf8");
  const ids = topLevelRuleCollectionIds(rules);

  assert.ok(ids.includes("users"));
  assert.ok(ids.includes("notification_devices"));
  assert.ok(ids.includes("notification_campaigns"));
  assert.ok(!ids.includes("workouts"));
  assert.ok(!ids.includes("entries"));
});

test("the rules parser reads nesting from braces, not indentation", () => {
  const reformatted = [
    "rules_version = '2';",
    "service cloud.firestore {",
    "match /databases/{database}/documents {",
    "    match /users/{userId} {",
    "    match /workouts/{workoutId} {",
    "      allow read: if false;",
    "    }",
    "    }",
    "    match /leaderboard_stats/{docId} {",
    "      allow read: if false;",
    "    }",
    "  }",
    "}",
    "",
  ].join("\n");

  assert.deepEqual(topLevelRuleCollectionIds(reformatted), [
    "leaderboard_stats",
    "users",
  ]);
});

test("a root collection reached through admin.firestore() is still declared", () => {
  const source = [
    "const query = admin.firestore()",
    "  .collection(\"notification_devices\")",
    "  .where(\"active\", \"==\", true);",
    "const other = getFirestore().collection(\"leaderboard_periods\");",
  ].join("\n");

  assert.deepEqual(sourceDeclaredTopLevelCollectionIds(source), [
    "leaderboard_periods",
    "notification_devices",
  ]);
});

test("staging requires its own confirmation and rejects the dev confirmation", () => {
  const missing = runDevDb("wipe", "--project", "staging");
  assert.notEqual(missing.status, 0);
  assert.match(missing.stderr, /staging wipe requires --confirm-staging-wipe/);

  const mismatched = runDevDb(
    "wipe",
    "--project",
    "staging",
    "--confirm-dev-wipe"
  );
  assert.notEqual(mismatched.status, 0);
  assert.match(mismatched.stderr, /--confirm-dev-wipe cannot authorize/);
});

test("production is refused before even a wipe dry-run can list collections", () => {
  const result = runDevDb("wipe", "--project", "production", "--dry-run");

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Refusing to write ascend-prod-9c8f2/);
});

function addDeclaredCollections(output, path) {
  const source = readFileSync(path, "utf8");
  for (const collectionId of sourceDeclaredTopLevelCollectionIds(source)) {
    output.add(collectionId);
  }
}

function sourceFiles(directory, excludedDirectories = new Set()) {
  const paths = [];
  for (const entry of readdirSync(directory, {withFileTypes: true})) {
    if (entry.name === "node_modules" || excludedDirectories.has(entry.name)) {
      continue;
    }

    const path = resolve(directory, entry.name);
    if (entry.isDirectory()) {
      paths.push(...sourceFiles(path, excludedDirectories));
    } else if ([".js", ".mjs", ".ts"].includes(extname(entry.name))) {
      paths.push(path);
    }
  }
  return paths;
}

function runDevDb(...args) {
  return spawnSync(
    process.execPath,
    [resolve(REPO_ROOT, "scripts", "dev-db.mjs"), ...args],
    {encoding: "utf8"}
  );
}
