import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {mkdirSync, mkdtempSync, readFileSync, writeFileSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";

import {waitForFirestoreIndexes} from
  "../ci/wait-for-firestore-indexes.mjs";
import {
  evaluateFirestoreIndexReadiness,
  formatFirestoreIndexIssues,
} from "../lib/firestore-index-readiness.mjs";
import {createFirestoreIndexStateReader} from
  "../lib/firestore-index-state-reader.mjs";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));
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
    fieldOverride.indexes,
  ]);

  // A field override replaces the field's whole index configuration, so
  // entries.userId has to restate the COLLECTION-scoped single-field indexes
  // that the per-climb best-completion reads and the Cloud Function
  // reconciliation query run against. finishers and blocked are addressed by
  // document ID, so they need the collection-group index only.
  assert.deepEqual(signatures, [
    [
      "blocked",
      "blockedUid",
      [{order: "ASCENDING", queryScope: "COLLECTION_GROUP"}],
    ],
    [
      "entries",
      "userId",
      [
        {order: "ASCENDING", queryScope: "COLLECTION"},
        {order: "DESCENDING", queryScope: "COLLECTION"},
        {order: "ASCENDING", queryScope: "COLLECTION_GROUP"},
      ],
    ],
    [
      "finishers",
      "userId",
      [{order: "ASCENDING", queryScope: "COLLECTION_GROUP"}],
    ],
  ]);
});

test("index readiness reports each exact non-READY serving state", () => {
  const config = readinessConfig();
  const deployedState = deployedReadinessState({finalStepsState: "CREATING"});
  deployedState.fieldOverrides[0].indexes.push({
    queryScope: "COLLECTION",
    arrayConfig: "CONTAINS",
    state: "READY",
  });
  delete deployedState.indexes[0].state;
  const building = evaluateFirestoreIndexReadiness(config, deployedState);
  const buildingIssues = formatFirestoreIndexIssues(building.issues);
  assert.equal(building.ready, false);
  assert.match(
    buildingIssues,
    /composite \(entries\).*finalSteps,DESCENDING.*: CREATING/
  );
  assert.match(
    buildingIssues,
    /field override \[entries\.userId\].*CONTAINS,COLLECTION\): UNEXPECTED \(READY\)/
  );
  assert.match(
    buildingIssues,
    /isBestForUser,ASCENDING.*: STATE_UNSPECIFIED/
  );

  deployedState.indexes[1].fields.at(-1).order = "DESCENDING";
  deployedState.fieldOverrides = [];
  const wrongDefinitions = evaluateFirestoreIndexReadiness(
    config,
    deployedState
  );
  const wrongDefinitionIssues = formatFirestoreIndexIssues(
    wrongDefinitions.issues
  );
  assert.equal(wrongDefinitions.ready, false);
  assert.match(
    wrongDefinitionIssues,
    /composite \(entries\).*finalSteps,DESCENDING.*: MISSING/
  );
  assert.match(
    wrongDefinitionIssues,
    /field override \[entries\.userId\].*COLLECTION_GROUP\): MISSING/
  );
});

test("index readiness passes only when all current serving states are READY", () => {
  const ready = evaluateFirestoreIndexReadiness(
    readinessConfig(),
    deployedReadinessState()
  );

  assert.equal(ready.ready, true);
  assert.equal(ready.compositeCount, 2);
  assert.equal(ready.fieldOverrideCount, 1);
});

test("index state reader installs explicit or local auth before reading", async () => {
  const directory = mkdtempSync(join(tmpdir(), "ascend-index-reader-"));
  const firestoreDirectory = join(directory, "lib/firestore");
  mkdirSync(firestoreDirectory, {recursive: true});
  writeFileSync(
    join(directory, "lib/auth.js"),
    [
      "exports.setRefreshToken = (token) => {",
      "  global.__ascendFirestoreTestToken = token;",
      "};",
      "exports.getGlobalDefaultAccount = () => ({",
      "  tokens: {refresh_token: \"local-refresh-token\"},",
      "});",
    ].join("\n")
  );
  writeFileSync(
    join(firestoreDirectory, "api.js"),
    [
      "exports.FirestoreApi = class {",
      "  async listIndexes(projectId, databaseId) {",
      "    const accepted = [\"ci-refresh-token\", \"local-refresh-token\"];",
      "    if (!accepted.includes(global.__ascendFirestoreTestToken)) {",
      "      throw new Error(\"refresh token was not installed\");",
      "    }",
      "    return [{",
      "      name: `projects/${projectId}/databases/${databaseId}/` +",
      "        \"collectionGroups/entries/indexes/index-1\",",
      "      queryScope: \"COLLECTION\",",
      "      fields: [{fieldPath: \"finalSteps\", order: \"DESCENDING\"}],",
      "      state: \"READY\",",
      "    }];",
      "  }",
      "  async listFieldOverrides(projectId, databaseId) {",
      "    return [{",
      "      name: `projects/${projectId}/databases/${databaseId}/` +",
      "        \"collectionGroups/entries/fields/userId\",",
      "      indexConfig: {indexes: [{",
      "        queryScope: \"COLLECTION_GROUP\",",
      "        fields: [{fieldPath: \"userId\", order: \"ASCENDING\"}],",
      "        state: \"READY\",",
      "      }]},",
      "    }];",
      "  }",
      "};",
    ].join("\n")
  );

  const readState = createFirestoreIndexStateReader({
    firebaseToolsRoot: directory,
    refreshToken: "ci-refresh-token",
    projectId: "ascend-production",
  });
  const state = await readState();

  assert.deepEqual(state, {
    indexes: [{
      collectionGroup: "entries",
      queryScope: "COLLECTION",
      fields: [{fieldPath: "finalSteps", order: "DESCENDING"}],
      state: "READY",
    }],
    fieldOverrides: [{
      collectionGroup: "entries",
      fieldPath: "userId",
      indexes: [{
        queryScope: "COLLECTION_GROUP",
        order: "ASCENDING",
        state: "READY",
      }],
    }],
  });

  const readWithLocalSession = createFirestoreIndexStateReader({
    firebaseToolsRoot: directory,
    projectId: "ascend-production",
  });
  assert.deepEqual(await readWithLocalSession(), state);
});

test("index wait retries building states and exits when all are READY", async () => {
  let currentTime = 0;
  let readCount = 0;
  const log = memoryLog();
  const result = await waitForFirestoreIndexes({
    config: readinessConfig(),
    readState: async () => {
      readCount += 1;
      return deployedReadinessState({
        finalStepsState: readCount === 1 ? "CREATING" : "READY",
      });
    },
    timeoutMs: 60,
    intervalMs: 20,
    now: () => currentTime,
    sleep: async (milliseconds) => {
      currentTime += milliseconds;
    },
    log,
  });

  assert.equal(result.status, "ready");
  assert.equal(readCount, 2);
  assert.match(log.errors.join("\n"), /finalSteps,DESCENDING.*: CREATING/);
  assert.match(log.messages.join("\n"), /2 composite indexes.*1 field overrides/);
});

test("index wait timeout repeats the exact indexes and states still pending", async () => {
  let currentTime = 0;
  let readCount = 0;
  const log = memoryLog();
  const result = await waitForFirestoreIndexes({
    config: readinessConfig(),
    readState: async () => {
      readCount += 1;
      return deployedReadinessState({finalStepsState: "CREATING"});
    },
    timeoutMs: 40,
    intervalMs: 20,
    now: () => currentTime,
    sleep: async (milliseconds) => {
      currentTime += milliseconds;
    },
    log,
  });

  assert.equal(result.status, "timeout");
  assert.equal(readCount, 3);
  const errors = log.errors.join("\n");
  assert.match(errors, /did not become READY within 40 milliseconds/);
  assert.match(errors, /Still waiting for:/);
  assert.match(
    errors,
    /composite \(entries\).*finalSteps,DESCENDING.*: CREATING/
  );
});

test("index wait fails as verification error after repeated state-read failures", async () => {
  let currentTime = 0;
  let readCount = 0;
  const log = memoryLog();
  const result = await waitForFirestoreIndexes({
    config: readinessConfig(),
    readState: async () => {
      readCount += 1;
      throw new Error("authentication hook missing");
    },
    timeoutMs: 60 * 60 * 1000,
    intervalMs: 20,
    maxConsecutiveReadFailures: 3,
    now: () => currentTime,
    sleep: async (milliseconds) => {
      currentTime += milliseconds;
    },
    log,
  });

  assert.equal(result.status, "read-failed");
  assert.equal(readCount, 3);
  assert.equal(currentTime, 40);
  assert.match(
    log.errors.join("\n"),
    /serving-state API could not be read/
  );
});

test("index wait rejects structural state errors without retrying", async () => {
  let readCount = 0;

  await assert.rejects(
    waitForFirestoreIndexes({
      config: readinessConfig(),
      readState: async () => {
        readCount += 1;
        return {indexes: []};
      },
      sleep: async () => {
        assert.fail("structural errors must not sleep or retry");
      },
      log: memoryLog(),
    }),
    /does not contain a fieldOverrides array/
  );
  assert.equal(readCount, 1);
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
  assert.doesNotMatch(workflow, /firestore:operations:list/);
  assert.match(
    workflow,
    /FIREBASE_TOOLS_ROOT="\$firebase_tools_root"[\s\\]*node scripts\/ci\/wait-for-firestore-indexes\.mjs/
  );
  assert.match(workflow, /firebase-tools@15\.22\.1 -- which firebase/);
});

test("production release documentation orders identity backend ahead of the binary", () => {
  const runbook = readFileSync(
    join(repositoryRoot, "docs/production-backend-rollout-runbook.md"),
    "utf8"
  );

  assert.match(runbook, /There is no public identity backfill to run/);
  assert.match(
    runbook,
    /onPublicProfileIdentityWritten[\s\S]*?onPublicIdentityPropagationJobWritten[\s\S]*?before the binary that publishes identity/
  );
  assert.doesNotMatch(runbook, /restore-public-identities/);
});

function runNode(script, argumentsList, input) {
  return spawnSync(process.execPath, [script, ...argumentsList], {
    encoding: "utf8",
    input,
  });
}

function readinessConfig() {
  return {
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
          {order: "ASCENDING", queryScope: "COLLECTION"},
          {order: "DESCENDING", queryScope: "COLLECTION"},
          {order: "ASCENDING", queryScope: "COLLECTION_GROUP"},
        ],
      },
    ],
  };
}

function deployedReadinessState({finalStepsState = "READY"} = {}) {
  return {
    indexes: [
      {
        collectionGroup: "entries",
        queryScope: "COLLECTION",
        fields: [
          {fieldPath: "isBestForUser", order: "ASCENDING"},
          {fieldPath: "stepsAtBucket", order: "ASCENDING"},
          {fieldPath: "__name__", order: "ASCENDING"},
        ],
        state: "READY",
      },
      {
        collectionGroup: "entries",
        queryScope: "COLLECTION",
        fields: [
          {fieldPath: "finalSteps", order: "DESCENDING"},
          {fieldPath: "__name__", order: "ASCENDING"},
        ],
        state: finalStepsState,
      },
    ],
    fieldOverrides: [
      {
        collectionGroup: "entries",
        fieldPath: "userId",
        indexes: [
          {order: "ASCENDING", queryScope: "COLLECTION", state: "READY"},
          {order: "DESCENDING", queryScope: "COLLECTION", state: "READY"},
          {
            order: "ASCENDING",
            queryScope: "COLLECTION_GROUP",
            state: "READY",
          },
        ],
      },
    ],
  };
}

function memoryLog() {
  const messages = [];
  const errors = [];
  return {
    messages,
    errors,
    log: (message) => messages.push(message),
    error: (message) => errors.push(message),
  };
}
