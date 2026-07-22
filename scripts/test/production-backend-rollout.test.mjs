import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {mkdtempSync, readFileSync, writeFileSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));
const indexReadinessScript = join(
  repositoryRoot,
  "scripts/ci/assert-firestore-indexes-ready.mjs"
);
const functionReadinessScript = join(
  repositoryRoot,
  "scripts/ci/assert-firebase-functions-active.mjs"
);

function hasIndex(indexes, collectionGroup, fields) {
  return indexes.some((index) =>
    index.collectionGroup === collectionGroup &&
    index.queryScope === "COLLECTION" &&
    JSON.stringify(index.fields) === JSON.stringify(fields)
  );
}

test("declares both filtered Live Replay window indexes", () => {
  const config = JSON.parse(
    readFileSync(join(repositoryRoot, "firestore.indexes.json"), "utf8")
  );
  const ascendingFields = [
    {fieldPath: "isBestForUser", order: "ASCENDING"},
    {fieldPath: "stepsAtBucket", order: "ASCENDING"},
  ];
  const descendingFields = [
    {fieldPath: "isBestForUser", order: "ASCENDING"},
    {fieldPath: "stepsAtBucket", order: "DESCENDING"},
  ];

  assert.ok(hasIndex(config.indexes, "entries", ascendingFields));
  assert.ok(hasIndex(config.indexes, "entries", descendingFields));

  const repository = readFileSync(
    join(
      repositoryRoot,
      "AscendApp/Shared/Repositories/Firebase/" +
        "FirestoreLiveReplayLeaderboardRepository.swift"
    ),
    "utf8"
  );
  assert.match(repository, /whereField\("isBestForUser", isEqualTo: true\)/);
  assert.match(
    repository,
    /whereField\("stepsAtBucket", isGreaterThanOrEqualTo: currentSteps\)[\s\S]*?order\(by: "stepsAtBucket", descending: false\)/
  );
  assert.match(
    repository,
    /whereField\("stepsAtBucket", isLessThan: currentSteps\)[\s\S]*?order\(by: "stepsAtBucket", descending: true\)/
  );
});

test("index readiness requires every declared index to report READY", () => {
  const directory = mkdtempSync(join(tmpdir(), "ascend-index-readiness-"));
  const configPath = join(directory, "firestore.indexes.json");
  writeFileSync(
    configPath,
    JSON.stringify({
      indexes: [
        {
          collectionGroup: "entries",
          queryScope: "COLLECTION",
          fields: [
            {fieldPath: "isBestForUser", order: "ASCENDING"},
            {fieldPath: "stepsAtBucket", order: "ASCENDING"},
          ],
        },
        {
          collectionGroup: "entries",
          queryScope: "COLLECTION",
          fields: [
            {fieldPath: "finalSteps", order: "DESCENDING"},
            {fieldPath: "__name__", order: "ASCENDING"},
          ],
        },
      ],
      fieldOverrides: [],
    })
  );

  const building = runNode(
    indexReadinessScript,
    [configPath],
    "[READY] (entries) -- (isBestForUser,ASCENDING) " +
      "(stepsAtBucket,ASCENDING) (ignored,ASCENDING)\n" +
      "[CREATING] (entries) -- (finalSteps,DESCENDING)\n"
  );
  assert.notEqual(building.status, 0);
  assert.match(building.stderr, /finalSteps/);

  const ready = runNode(
    indexReadinessScript,
    [configPath],
    "[READY] (entries) -- (isBestForUser,ASCENDING) " +
      "(stepsAtBucket,ASCENDING)\n" +
      "[READY] (entries) -- (finalSteps,DESCENDING)\n"
  );
  assert.equal(ready.status, 0, ready.stderr);
  assert.match(ready.stdout, /All 2 declared Firestore indexes are READY/);
});

test("function readiness rejects missing and inactive critical functions", () => {
  const expected = [
    "cleanupDeletedUserData",
    "onWorkoutWritten",
    "onWorkoutReplaySplitsWritten",
    "unsubscribeFromEmails",
  ];
  const payload = JSON.stringify({
    status: "success",
    result: [
      {id: "cleanupDeletedUserData", state: "ACTIVE"},
      {id: "onWorkoutWritten", state: "ACTIVE"},
      {id: "onWorkoutReplaySplitsWritten", state: "FAILED"},
    ],
  });
  const incomplete = runNode(functionReadinessScript, expected, payload);

  assert.notEqual(incomplete.status, 0);
  assert.match(
    incomplete.stderr,
    /onWorkoutReplaySplitsWritten, unsubscribeFromEmails/
  );

  const completePayload = JSON.stringify({
    status: "success",
    result: expected.map((id) => ({id, state: "ACTIVE"})),
  });
  const complete = runNode(functionReadinessScript, expected, completePayload);

  assert.equal(complete.status, 0, complete.stderr);
  assert.match(complete.stdout, /Verified ACTIVE Firebase Functions/);
});

test("production deploy waits for indexes and rolls the backend out in dependency order", () => {
  const workflow = readFileSync(
    join(repositoryRoot, ".github/workflows/deploy-production.yml"),
    "utf8"
  );
  const orderedSteps = [
    "      - name: Deploy Firestore indexes\n",
    "      - name: Wait for every declared Firestore index\n",
    "      - name: Deploy Functions\n",
    "      - name: Verify critical Functions are active\n",
    "      - name: Deploy Firestore rules\n",
    "      - name: Deploy Storage rules\n",
    "      - name: Deploy Hosting\n",
    "      - name: Verify Hosting serves the climb manifest\n",
  ];
  const positions = orderedSteps.map((step) => workflow.indexOf(step));

  for (const [index, position] of positions.entries()) {
    assert.notEqual(position, -1, `Missing production rollout step: ${orderedSteps[index]}`);
  }

  assert.deepEqual(positions, [...positions].sort((left, right) => left - right));
  assert.match(
    workflow,
    /upload-testflight:[\s\S]*?needs:[\s\S]*?- deploy-firebase/
  );
  assert.doesNotMatch(
    workflow,
    /--only functions,firestore:rules,firestore:indexes,storage,hosting/
  );
});

function runNode(script, argumentsList, input) {
  return spawnSync(process.execPath, [script, ...argumentsList], {
    encoding: "utf8",
    input,
  });
}
