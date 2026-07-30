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

test("declares every cleanup and propagation collection-group field index", () => {
  const config = JSON.parse(
    readFileSync(join(repositoryRoot, "firestore.indexes.json"), "utf8")
  );
  const signatures = config.fieldOverrides.map((fieldOverride) => [
    fieldOverride.collectionGroup,
    fieldOverride.fieldPath,
    fieldOverride.indexes[0]?.order,
    fieldOverride.indexes[0]?.queryScope,
  ]);

  assert.deepEqual(signatures, [
    ["blocked", "blockedUid", "ASCENDING", "COLLECTION_GROUP"],
    ["entries", "userId", "ASCENDING", "COLLECTION_GROUP"],
    ["finishers", "userId", "ASCENDING", "COLLECTION_GROUP"],
  ]);
});

test("index readiness requires every declared index to report READY", () => {
  const directory = mkdtempSync(join(tmpdir(), "ascend-index-readiness-"));
  const configPath = join(directory, "firestore.indexes.json");
  const deployedSpecPath = join(directory, "deployed-index-spec.json");
  const operationsPath = join(directory, "firestore-operations.json");
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
      fieldOverrides: [
        {
          collectionGroup: "entries",
          fieldPath: "userId",
          indexes: [
            {order: "ASCENDING", queryScope: "COLLECTION_GROUP"},
          ],
        },
      ],
    })
  );
  writeFileSync(
    operationsPath,
    JSON.stringify({status: "success", result: []})
  );
  writeFileSync(
    deployedSpecPath,
    JSON.stringify({
      status: "success",
      result: {
        fieldOverrides: [{
          collectionGroup: "entries",
          fieldPath: "userId",
          indexes: [
            {order: "ASCENDING", queryScope: "COLLECTION_GROUP"},
          ],
        }],
        indexes: [],
      },
    })
  );

  const building = runNode(
    indexReadinessScript,
    [configPath, operationsPath, deployedSpecPath],
    "[READY] (entries) -- (isBestForUser,ASCENDING) " +
      "(stepsAtBucket,ASCENDING) (ignored,ASCENDING)\n" +
      "[CREATING] (entries) -- (finalSteps,DESCENDING)\n" +
      "[entries.userId] -- (ASCENDING)\n"
  );
  assert.equal(building.status, 1);
  assert.match(building.stderr, /finalSteps/);

  const leadingSuperset = runNode(
    indexReadinessScript,
    [configPath, operationsPath, deployedSpecPath],
    "[READY] (entries) -- (other,ASCENDING) (isBestForUser,ASCENDING) " +
      "(stepsAtBucket,ASCENDING)\n" +
      "[CREATING] (entries) -- (isBestForUser,ASCENDING) " +
      "(stepsAtBucket,ASCENDING)\n" +
      "[READY] (entries) -- (finalSteps,DESCENDING)\n" +
      "[entries.userId] -- (ASCENDING)\n"
  );
  assert.equal(leadingSuperset.status, 1);
  assert.match(leadingSuperset.stderr, /isBestForUser/);

  const ready = runNode(
    indexReadinessScript,
    [configPath, operationsPath, deployedSpecPath],
    "[READY] (entries) -- (isBestForUser,ASCENDING) " +
      "(stepsAtBucket,ASCENDING)\n" +
      "[READY] (entries) -- (finalSteps,DESCENDING)\n" +
      "[entries.userId] -- (ASCENDING)\n"
  );
  assert.equal(ready.status, 0, ready.stderr);
  assert.match(ready.stdout, /All 3 declared Firestore indexes are READY/);

  writeFileSync(
    deployedSpecPath,
    JSON.stringify({
      status: "success",
      result: {
        fieldOverrides: [{
          collectionGroup: "entries",
          fieldPath: "userId",
          indexes: [
            {order: "ASCENDING", queryScope: "COLLECTION"},
          ],
        }],
      },
    })
  );
  const wrongScopeFieldOverride = runNode(
    indexReadinessScript,
    [configPath, operationsPath, deployedSpecPath],
    "[READY] (entries) -- (isBestForUser,ASCENDING) " +
      "(stepsAtBucket,ASCENDING)\n" +
      "[READY] (entries) -- (finalSteps,DESCENDING)\n" +
      "[entries.userId] -- (ASCENDING)\n"
  );
  assert.equal(wrongScopeFieldOverride.status, 1);
  assert.match(wrongScopeFieldOverride.stderr, /entries\.userId/);

  writeFileSync(
    deployedSpecPath,
    JSON.stringify({
      status: "success",
      result: {
        fieldOverrides: [{
          collectionGroup: "entries",
          fieldPath: "userId",
          indexes: [
            {order: "ASCENDING", queryScope: "COLLECTION_GROUP"},
          ],
        }],
      },
    })
  );

  writeFileSync(
    operationsPath,
    JSON.stringify({
      status: "success",
      result: [{
        done: false,
        metadata: {
          "@type": "type.googleapis.com/" +
            "google.firestore.admin.v1.FieldOperationMetadata",
          field: "projects/ascend/databases/(default)/" +
            "collectionGroups/entries/fields/userId",
          state: "PROCESSING",
        },
        name: "projects/ascend/databases/(default)/operations/field-userId",
      }],
    })
  );
  const backfillingFieldOverride = runNode(
    indexReadinessScript,
    [configPath, operationsPath, deployedSpecPath],
    "[READY] (entries) -- (isBestForUser,ASCENDING) " +
      "(stepsAtBucket,ASCENDING)\n" +
      "[READY] (entries) -- (finalSteps,DESCENDING)\n" +
      "[entries.userId] -- (ASCENDING)\n"
  );
  assert.equal(backfillingFieldOverride.status, 1);
  assert.match(backfillingFieldOverride.stderr, /pending field-index operation/);

  writeFileSync(
    operationsPath,
    JSON.stringify({
      status: "success",
      result: [{
        done: true,
        error: {code: 9, message: "index entry limit exceeded"},
        metadata: {
          "@type": "type.googleapis.com/" +
            "google.firestore.admin.v1.FieldOperationMetadata",
          field: "projects/ascend/databases/(default)/" +
            "collectionGroups/entries/fields/userId",
          state: "FAILED",
        },
      }],
    })
  );
  const failedFieldOverride = runNode(
    indexReadinessScript,
    [configPath, operationsPath, deployedSpecPath],
    "[READY] (entries) -- (isBestForUser,ASCENDING) " +
      "(stepsAtBucket,ASCENDING)\n" +
      "[READY] (entries) -- (finalSteps,DESCENDING)\n" +
      "[entries.userId] -- (ASCENDING)\n"
  );
  assert.equal(failedFieldOverride.status, 1);
  assert.match(
    failedFieldOverride.stderr,
    /failed \(index entry limit exceeded\) field-index operation/
  );

  writeFileSync(
    operationsPath,
    JSON.stringify({
      status: "success",
      result: [{
        done: true,
        metadata: {
          "@type": "type.googleapis.com/" +
            "google.firestore.admin.v1.FieldOperationMetadata",
          field: "projects/ascend/databases/(default)/" +
            "collectionGroups/entries/fields/userId",
          state: "CANCELLED",
        },
      }],
    })
  );
  const cancelledFieldOverride = runNode(
    indexReadinessScript,
    [configPath, operationsPath, deployedSpecPath],
    "[READY] (entries) -- (isBestForUser,ASCENDING) " +
      "(stepsAtBucket,ASCENDING)\n" +
      "[READY] (entries) -- (finalSteps,DESCENDING)\n" +
      "[entries.userId] -- (ASCENDING)\n"
  );
  assert.equal(cancelledFieldOverride.status, 1);
  assert.match(
    cancelledFieldOverride.stderr,
    /terminal-CANCELLED field-index operation/
  );

  writeFileSync(
    operationsPath,
    JSON.stringify({
      status: "success",
      result: [
        {
          done: true,
          error: {code: 9, message: "older failed attempt"},
          metadata: {
            "@type": "type.googleapis.com/" +
              "google.firestore.admin.v1.FieldOperationMetadata",
            field: "projects/ascend/databases/(default)/" +
              "collectionGroups/entries/fields/userId",
            startTime: "2026-07-29T10:00:00Z",
            state: "FAILED",
          },
        },
        {
          done: true,
          metadata: {
            "@type": "type.googleapis.com/" +
              "google.firestore.admin.v1.FieldOperationMetadata",
            field: "projects/ascend/databases/(default)/" +
              "collectionGroups/entries/fields/userId",
            startTime: "2026-07-29T11:00:00Z",
            state: "SUCCESSFUL",
          },
        },
      ],
    })
  );
  const completedFieldOverride = runNode(
    indexReadinessScript,
    [configPath, operationsPath, deployedSpecPath],
    "[READY] (entries) -- (isBestForUser,ASCENDING) " +
      "(stepsAtBucket,ASCENDING)\n" +
      "[READY] (entries) -- (finalSteps,DESCENDING)\n" +
      "[entries.userId] -- (ASCENDING)\n"
  );
  assert.equal(completedFieldOverride.status, 0, completedFieldOverride.stderr);

  const unsupportedScopePath = join(directory, "collection-group.indexes.json");
  writeFileSync(
    unsupportedScopePath,
    JSON.stringify({
      indexes: [
        {
          collectionGroup: "entries",
          queryScope: "COLLECTION_GROUP",
          fields: [{fieldPath: "finalSteps", order: "DESCENDING"}],
        },
      ],
      fieldOverrides: [],
    })
  );
  const structural = runNode(
    indexReadinessScript,
    [unsupportedScopePath],
    "[READY] (entries) -- (finalSteps,DESCENDING)\n"
  );
  assert.equal(structural.status, 2);
  assert.match(structural.stderr, /COLLECTION indexes/);
});

test("function readiness rejects missing and inactive critical functions", () => {
  const expected = [
    "cleanupDeletedUserData",
    "onPublicIdentityPropagationJobWritten",
    "onPublicProfileIdentityWritten",
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
    /onPublicIdentityPropagationJobWritten, onPublicProfileIdentityWritten, onWorkoutReplaySplitsWritten, unsubscribeFromEmails/
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
  assert.match(workflow, /onPublicIdentityPropagationJobWritten/);
  assert.match(workflow, /firestore:operations:list/);
  assert.match(
    workflow,
    /assert-firestore-indexes-ready\.mjs firestore\.indexes\.json "\$operations_file" "\$deployed_spec_file"/
  );
});

test("production release documentation gates TestFlight on identity restoration v6", () => {
  const runbook = readFileSync(
    join(repositoryRoot, "docs/production-backend-rollout-runbook.md"),
    "utf8"
  );
  const identityRunbook = readFileSync(
    join(repositoryRoot, "docs/public-identity-restoration-runbook.md"),
    "utf8"
  );

  assert.match(
    runbook,
    /Complete public identity restoration operation version 6/
  );
  assert.match(
    runbook,
    /restore-public-identities\.mjs[\s\S]*?--apply[\s\S]*?--audit/
  );
  assert.match(
    runbook,
    /Do not approve the protected `production` environment while the audit reports/
  );
  assert.match(identityRunbook, /identityChangedAt/);
  assert.match(identityRunbook, /freshly enumerates user roots and every projection/);
});

function runNode(script, argumentsList, input) {
  return spawnSync(process.execPath, [script, ...argumentsList], {
    encoding: "utf8",
    input,
  });
}
