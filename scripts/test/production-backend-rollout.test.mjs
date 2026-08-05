import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import test from "node:test";
import {fileURLToPath, pathToFileURL} from "node:url";

import {
  DEFAULT_STRUCTURAL_GRACE_MS,
  STRUCTURAL_GRACE_ENV_VAR,
  assertLiteralFirebaseProjectId,
  isCommandLineEntryPoint,
  resolveStructuralGraceMs,
  waitForFirestoreIndexes,
} from "../ci/wait-for-firestore-indexes.mjs";
import {
  evaluateFirestoreIndexReadiness,
  formatFirestoreIndexIssues,
  structuralFirestoreIndexIssues,
} from "../lib/firestore-index-readiness.mjs";
import {
  PINNED_FIREBASE_TOOLS_VERSION,
  classifyFirestoreReadError,
  createFirestoreIndexStateReader,
} from "../lib/firestore-index-state-reader.mjs";

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

test("declares every server collection-group field index", () => {
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
  // document ID, so they need the collection-group index only. The entitlement
  // expiry sweep orders active grants by accessUntil across every user.
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
    [
      "entitlements",
      "accessUntil",
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
  const directory = pinnedFirebaseToolsStub();

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
      throw firebaseHttpError(503, "backend unavailable");
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
  assert.equal(result.classification, "transient");
  assert.equal(readCount, 3);
  assert.equal(currentTime, 40);
  assert.match(
    log.errors.join("\n"),
    /serving-state API could not be read/
  );
});

test("index wait retries transient read failures and recovers from a blip", async () => {
  let currentTime = 0;
  let readCount = 0;
  const log = memoryLog();
  const result = await waitForFirestoreIndexes({
    config: readinessConfig(),
    readState: async () => {
      readCount += 1;
      if (readCount <= 5) {
        throw [
          firebaseHttpError(503, "backend unavailable"),
          firebaseHttpError(429, "quota exceeded"),
          firebaseHttpError(500, "internal"),
          Object.assign(new Error("Failed to make request"), {
            code: "ENOTFOUND",
          }),
          Object.assign(new Error("Failed to make request"), {
            original: {code: "EAI_AGAIN"},
          }),
        ][readCount - 1];
      }
      return deployedReadinessState();
    },
    timeoutMs: 60 * 60 * 1000,
    intervalMs: 20,
    maxConsecutiveReadFailures: 15,
    now: () => currentTime,
    sleep: async (milliseconds) => {
      currentTime += milliseconds;
    },
    log,
  });

  assert.equal(result.status, "ready");
  assert.equal(readCount, 6);
  assert.match(log.errors.join("\n"), /Transient .* \(5\/15\)/);
});

test("index wait fails immediately on deterministic auth and permission errors", async () => {
  const deterministicErrors = [
    new Error("Unable to refresh auth: not yet authenticated."),
    firebaseHttpError(401, "Request had invalid authentication credentials"),
    firebaseHttpError(403, "The caller does not have permission"),
    firebaseHttpError(404, "Not Found"),
  ];

  for (const readError of deterministicErrors) {
    let readCount = 0;
    const log = memoryLog();
    const result = await waitForFirestoreIndexes({
      config: readinessConfig(),
      readState: async () => {
        readCount += 1;
        throw readError;
      },
      timeoutMs: 60 * 60 * 1000,
      intervalMs: 20,
      maxConsecutiveReadFailures: 15,
      now: () => 0,
      sleep: async () => {
        assert.fail(`deterministic read errors must not retry: ${readError.message}`);
      },
      log,
    });

    assert.equal(result.status, "read-failed");
    assert.equal(result.classification, "deterministic");
    assert.equal(readCount, 1);
    const errors = log.errors.join("\n");
    assert.match(errors, new RegExp(escapeRegExp(readError.message)));
    assert.match(errors, /Retrying cannot resolve an authentication/);
  }

  assert.equal(
    classifyFirestoreReadError(firebaseHttpError(503, "unavailable")),
    "transient"
  );
  assert.equal(
    classifyFirestoreReadError(new Error("socket hang up")),
    "transient"
  );
});

test("unusable Firebase credentials fail without burning the readiness window", async () => {
  const bold = (value) => `\u001B[1m${value}\u001B[22m`;

  // A revoked or expired refresh token takes refreshTokens()' OAuth 400 early
  // return, so the stale token reaches Firestore and comes back as a 401.
  // These carry a status and must abort on the first poll.
  const immediateErrors = [
    firebaseHttpError(401, "Request had invalid authentication credentials"),
    firebaseHttpError(403, "The caller does not have permission"),
    firebaseHttpError(400, "Request contains an invalid argument"),
    new Error("Unable to refresh auth: not yet authenticated."),
    new Error(
      "This command requires new authorization scopes not granted to your " +
        `current session. Please run ${bold("firebase login --reauth")}`
    ),
  ];

  for (const error of immediateErrors) {
    assert.equal(
      classifyFirestoreReadError(error),
      "deterministic",
      `Expected a deterministic classification for: ${error.message}`
    );

    let readCount = 0;
    const result = await waitForFirestoreIndexes({
      config: readinessConfig(),
      readState: async () => {
        readCount += 1;
        throw error;
      },
      timeoutMs: 60 * 60 * 1000,
      intervalMs: 20,
      now: () => 0,
      sleep: async () => {
        assert.fail(`must not retry a refused credential: ${error.message}`);
      },
      log: memoryLog(),
    });

    assert.equal(result.status, "read-failed");
    assert.equal(result.classification, "deterministic");
    assert.equal(readCount, 1);
  }

  // refreshTokens() raises this identical wording for an OAuth 5xx and for a
  // DNS or socket failure, so it cannot abort the deploy on poll 1.
  const ambiguousErrors = [
    "Authentication Error: Your credentials are no longer valid. Please run " +
      `${bold("firebase login --reauth")}\n\nFor CI servers and headless ` +
      `environments, generate a new token with ${bold("firebase login:ci")}`,
    "Authentication Error.",
    "Unable to getAccessToken",
  ];

  for (const message of ambiguousErrors) {
    const error = new Error(message);
    error.status = 500;
    assert.equal(
      classifyFirestoreReadError(error),
      "ambiguous",
      `Expected an ambiguous classification for: ${message}`
    );
  }

  // The approved retry behaviour for genuine transport failures is unchanged.
  for (const transient of [
    firebaseHttpError(503, "backend unavailable"),
    firebaseHttpError(500, "internal"),
    firebaseHttpError(429, "quota exceeded"),
    Object.assign(new Error("Failed to make request"), {code: "ENOTFOUND"}),
    new Error("socket hang up"),
  ]) {
    assert.equal(
      classifyFirestoreReadError(transient),
      "transient",
      `Expected a transient classification for: ${transient.message}`
    );
  }
});

test("a one-off OAuth blip recovers instead of killing the deploy", async () => {
  const oauthBlip = new Error(
    "Authentication Error: Your credentials are no longer valid."
  );
  oauthBlip.status = 500;

  for (const failingPolls of [1, 2]) {
    let currentTime = 0;
    let readCount = 0;
    const log = memoryLog();
    const result = await waitForFirestoreIndexes({
      config: readinessConfig(),
      readState: async () => {
        readCount += 1;
        if (readCount <= failingPolls) {
          throw oauthBlip;
        }
        return deployedReadinessState();
      },
      timeoutMs: 60 * 60 * 1000,
      intervalMs: 20,
      now: () => currentTime,
      sleep: async (milliseconds) => {
        currentTime += milliseconds;
      },
      log,
    });

    assert.equal(
      result.status,
      "ready",
      `${failingPolls} ambiguous poll(s) must not abort the deploy`
    );
    assert.equal(readCount, failingPolls + 1);
    assert.match(
      log.errors.join("\n"),
      new RegExp(
        `Firebase credential read failure \\(${failingPolls}/3\\): ` +
          "Authentication Error"
      )
    );
  }
});

test("a persistently unusable credential fails after the bounded credential retry", async () => {
  const revoked = new Error(
    "Authentication Error: Your credentials are no longer valid."
  );
  revoked.status = 500;

  let currentTime = 0;
  let readCount = 0;
  const log = memoryLog();
  const result = await waitForFirestoreIndexes({
    config: readinessConfig(),
    readState: async () => {
      readCount += 1;
      throw revoked;
    },
    timeoutMs: 60 * 60 * 1000,
    intervalMs: 20,
    maxConsecutiveReadFailures: 15,
    now: () => currentTime,
    sleep: async (milliseconds) => {
      currentTime += milliseconds;
    },
    log,
  });

  assert.equal(result.status, "read-failed");
  assert.equal(result.classification, "ambiguous");
  assert.equal(readCount, 3);
  assert.equal(currentTime, 40);

  const errors = log.errors.join("\n");
  assert.match(errors, /credential stayed unusable across 3 consecutive polls/);
  assert.match(errors, /expired or revoked\s+FIREBASE_TOKEN or a sustained OAuth outage/);
  assert.match(errors, /Authentication Error: Your credentials are no longer valid/);
});

test("an intermittent credential blip cannot outlive the overall read-failure bound", async () => {
  const oauthBlip = new Error("Unable to getAccessToken");
  oauthBlip.status = 500;

  let currentTime = 0;
  let readCount = 0;
  const result = await waitForFirestoreIndexes({
    config: readinessConfig(),
    readState: async () => {
      readCount += 1;
      throw readCount % 2 === 0 ?
        firebaseHttpError(503, "backend unavailable") : oauthBlip;
    },
    timeoutMs: 60 * 60 * 1000,
    intervalMs: 20,
    maxConsecutiveReadFailures: 6,
    now: () => currentTime,
    sleep: async (milliseconds) => {
      currentTime += milliseconds;
    },
    log: memoryLog(),
  });

  assert.equal(result.status, "read-failed");
  assert.equal(readCount, 6);
});

test("structural grace is operator-configurable and fails closed when invalid", async () => {
  assert.equal(DEFAULT_STRUCTURAL_GRACE_MS, 2 * 60 * 1000);
  assert.equal(STRUCTURAL_GRACE_ENV_VAR, "FIRESTORE_INDEX_STRUCTURAL_GRACE_MS");

  for (const unset of [undefined, null, "", "   "]) {
    assert.equal(resolveStructuralGraceMs(unset), DEFAULT_STRUCTURAL_GRACE_MS);
  }

  assert.equal(resolveStructuralGraceMs("300000"), 300000);
  assert.equal(resolveStructuralGraceMs(" 300000 "), 300000);

  for (const invalid of ["0", "-1", "abc", "NaN", "Infinity", "5m", "1e999"]) {
    assert.throws(
      () => resolveStructuralGraceMs(invalid),
      new RegExp(
        `${STRUCTURAL_GRACE_ENV_VAR} must be a finite, strictly positive`
      ),
      `Expected ${invalid} to fail closed`
    );
  }

  for (const disabling of [60 * 60 * 1000, 60 * 60 * 1000 + 1]) {
    assert.throws(
      () => resolveStructuralGraceMs(String(disabling)),
      /must stay below the 3600000 ms readiness window/
    );
  }

  await assert.rejects(
    waitForFirestoreIndexes({
      config: readinessConfig(),
      readState: async () => deployedReadinessState(),
      structuralGraceMs: 0,
      log: memoryLog(),
    }),
    /structuralGraceMs must be a finite, strictly positive/
  );

  const workflow = readFileSync(
    join(repositoryRoot, ".github/workflows/deploy-production.yml"),
    "utf8"
  );
  assert.match(
    workflow,
    new RegExp(
      `${STRUCTURAL_GRACE_ENV_VAR}: \\$\\{\\{ vars\\.` +
        `${STRUCTURAL_GRACE_ENV_VAR} \\}\\}`
    )
  );

  const runbook = readFileSync(
    join(repositoryRoot, "docs/production-backend-rollout-runbook.md"),
    "utf8"
  );
  assert.match(runbook, new RegExp(`${STRUCTURAL_GRACE_ENV_VAR}=300000`));
  assert.match(runbook, /estimate, not a measurement/);
});

test("a raised structural grace keeps waiting where the default would fail", async () => {
  const missingCompositeState = () => {
    const state = deployedReadinessState({finalStepsState: "CREATING"});
    state.indexes.splice(0, 1);
    return state;
  };

  let currentTime = 0;
  let readCount = 0;
  const recovered = await waitForFirestoreIndexes({
    config: readinessConfig(),
    readState: async () => {
      readCount += 1;
      return readCount < 5 ? missingCompositeState() : deployedReadinessState();
    },
    timeoutMs: 60 * 60 * 1000,
    intervalMs: 20,
    structuralGraceMs: 200,
    now: () => currentTime,
    sleep: async (milliseconds) => {
      currentTime += milliseconds;
    },
    log: memoryLog(),
  });

  assert.equal(recovered.status, "ready");
  assert.equal(readCount, 5);

  currentTime = 0;
  readCount = 0;
  const aborted = await waitForFirestoreIndexes({
    config: readinessConfig(),
    readState: async () => {
      readCount += 1;
      return readCount < 5 ? missingCompositeState() : deployedReadinessState();
    },
    timeoutMs: 60 * 60 * 1000,
    intervalMs: 20,
    structuralGraceMs: 40,
    now: () => currentTime,
    sleep: async (milliseconds) => {
      currentTime += milliseconds;
    },
    log: memoryLog(),
  });

  assert.equal(aborted.status, "structural");
});

test("index wait fails a still-MISSING composite as a verification error after the grace period", async () => {
  let currentTime = 0;
  let readCount = 0;
  const log = memoryLog();
  const config = readinessConfig();
  const result = await waitForFirestoreIndexes({
    config,
    readState: async () => {
      readCount += 1;
      const state = deployedReadinessState({finalStepsState: "CREATING"});
      state.indexes.splice(0, 1);
      return state;
    },
    timeoutMs: 60 * 60 * 1000,
    intervalMs: 20,
    structuralGraceMs: 60,
    now: () => currentTime,
    sleep: async (milliseconds) => {
      currentTime += milliseconds;
    },
    log,
  });

  assert.equal(result.status, "structural");
  assert.equal(readCount, 4);
  assert.equal(currentTime, 60);
  const errors = log.errors.join("\n");
  assert.match(errors, /Waiting only resolves\s+CREATING indexes/);
  assert.match(
    errors,
    /composite \(entries\).*isBestForUser,ASCENDING.*stepsAtBucket,ASCENDING\): MISSING/
  );
  // The building index keeps the full readiness window, so it must not be
  // reported as a structural failure alongside the missing one.
  const structural = formatFirestoreIndexIssues(
    structuralFirestoreIndexIssues(result.readiness.issues)
  );
  assert.doesNotMatch(structural, /CREATING/);
});

test("index wait preserves the whole window for a CREATING index", async () => {
  let currentTime = 0;
  let readCount = 0;
  const result = await waitForFirestoreIndexes({
    config: readinessConfig(),
    readState: async () => {
      readCount += 1;
      return deployedReadinessState({
        finalStepsState: readCount < 10 ? "CREATING" : "READY",
      });
    },
    timeoutMs: 60 * 60 * 1000,
    intervalMs: 20,
    structuralGraceMs: 60,
    now: () => currentTime,
    sleep: async (milliseconds) => {
      currentTime += milliseconds;
    },
    log: memoryLog(),
  });

  assert.equal(result.status, "ready");
  assert.equal(readCount, 10);
});

test("a declared field override that is absent can never pass vacuously", async () => {
  const config = readinessConfig();
  config.fieldOverrides.push({
    collectionGroup: "finishers",
    fieldPath: "userId",
    indexes: [],
  });

  const absent = evaluateFirestoreIndexReadiness(config, deployedReadinessState());
  assert.equal(absent.ready, false);
  assert.match(
    formatFirestoreIndexIssues(absent.issues),
    /field override \[finishers\.userId\] -- resource: MISSING/
  );

  const deployedState = deployedReadinessState();
  deployedState.fieldOverrides.push({
    collectionGroup: "finishers",
    fieldPath: "userId",
    indexes: [],
  });
  const applied = evaluateFirestoreIndexReadiness(config, deployedState);
  assert.equal(applied.ready, true);

  let currentTime = 0;
  const log = memoryLog();
  const result = await waitForFirestoreIndexes({
    config,
    readState: async () => deployedReadinessState(),
    timeoutMs: 60 * 60 * 1000,
    intervalMs: 20,
    structuralGraceMs: 40,
    now: () => currentTime,
    sleep: async (milliseconds) => {
      currentTime += milliseconds;
    },
    log,
  });

  assert.equal(result.status, "structural");
  assert.match(
    log.errors.join("\n"),
    /field override \[finishers\.userId\] -- resource: MISSING/
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
    "expireRevenueCatEntitlements",
    "onPublicIdentityPropagationJobWritten",
    "onPublicProfileIdentityWritten",
    "onWorkoutWritten",
    "onWorkoutReplaySplitsWritten",
    "revenueCatWebhook",
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
    /expireRevenueCatEntitlements, onPublicIdentityPropagationJobWritten, onPublicProfileIdentityWritten, onWorkoutReplaySplitsWritten, revenueCatWebhook, unsubscribeFromEmails/
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
  assert.match(workflow, /expireRevenueCatEntitlements/);
  assert.match(workflow, /revenueCatWebhook/);
  assert.doesNotMatch(workflow, /firestore:operations:list/);
  // The gate is only substantive if it polls the production project and the
  // default database, so both positional arguments are pinned here.
  assert.match(
    workflow,
    /FIREBASE_TOOLS_ROOT="\$firebase_tools_root" \\\n\s*node scripts\/ci\/wait-for-firestore-indexes\.mjs \\\n\s*firestore\.indexes\.json \\\n\s*"\$\{\{ vars\.FIREBASE_PROJECT_ID_PRODUCTION \}\}" \\\n\s*"\(default\)"/
  );
  assert.match(
    workflow,
    new RegExp(
      `firebase-tools@${PINNED_FIREBASE_TOOLS_VERSION.replaceAll(".", "\\.")}` +
        " -- which firebase"
    )
  );
});

test("staging deploys entitlement dependencies before paid rules", () => {
  const workflow = readFileSync(
    join(repositoryRoot, ".github/workflows/deploy-staging.yml"),
    "utf8"
  );
  const orderedSteps = [
    "      - name: Deploy Firestore indexes\n",
    "      - name: Wait for every declared Firestore index\n",
    "      - name: Deploy Functions\n",
    "      - name: Verify deployed functions match this ref\n",
    "      - name: Deploy Firestore rules\n",
    "      - name: Deploy Storage rules\n",
    "      - name: Deploy Hosting\n",
  ];
  const positions = orderedSteps.map((step) => workflow.indexOf(step));

  for (const [index, position] of positions.entries()) {
    assert.notEqual(
      position,
      -1,
      `Missing staging rollout step: ${orderedSteps[index]}`
    );
  }
  assert.deepEqual(positions, [...positions].sort((left, right) => left - right));
  assert.doesNotMatch(
    workflow,
    /--only functions,firestore:rules,firestore:indexes,storage,hosting/
  );
});

test("index reader refuses any firebase-tools tree other than the pinned one", () => {
  const mismatchedVersion = pinnedFirebaseToolsStub();
  writeFileSync(
    join(mismatchedVersion, "package.json"),
    JSON.stringify({name: "firebase-tools", version: "15.23.0"})
  );

  assert.throws(
    () => createFirestoreIndexStateReader({
      firebaseToolsRoot: mismatchedVersion,
      refreshToken: "ci-refresh-token",
      projectId: "ascend-production",
    }),
    new RegExp(
      `private firebase-tools ` +
        `${escapeRegExp(PINNED_FIREBASE_TOOLS_VERSION)} internals` +
        `[\\s\\S]*resolved 15\\.23\\.0`
    )
  );

  const mismatchedPackage = pinnedFirebaseToolsStub();
  writeFileSync(
    join(mismatchedPackage, "package.json"),
    JSON.stringify({
      name: "some-other-cli",
      version: PINNED_FIREBASE_TOOLS_VERSION,
    })
  );
  assert.throws(
    () => createFirestoreIndexStateReader({
      firebaseToolsRoot: mismatchedPackage,
      refreshToken: "ci-refresh-token",
      projectId: "ascend-production",
    }),
    /resolved some-other-cli, not firebase-tools/
  );

  assert.throws(
    () => createFirestoreIndexStateReader({
      firebaseToolsRoot: join(mismatchedPackage, "absent"),
      refreshToken: "ci-refresh-token",
      projectId: "ascend-production",
    }),
    /does not hold a package/
  );
});

test("the pinned reader version matches every workflow firebase-tools pin", () => {
  const workflows = [
    ".github/workflows/deploy-production.yml",
    ".github/workflows/deploy-staging.yml",
  ];

  for (const path of workflows) {
    const contents = readFileSync(join(repositoryRoot, path), "utf8");
    const pins = [...contents.matchAll(/firebase-tools@(\d+\.\d+\.\d+)/g)];
    assert.notEqual(pins.length, 0, `No firebase-tools pin in ${path}`);
    for (const [, version] of pins) {
      assert.equal(
        version,
        PINNED_FIREBASE_TOOLS_VERSION,
        `${path} pins firebase-tools ${version} but the index reader loads ` +
          `${PINNED_FIREBASE_TOOLS_VERSION} internals`
      );
    }
  }
});

test("index wait runs through a symlinked, space-bearing invocation path", () => {
  assert.equal(
    isCommandLineEntryPoint(
      pathToFileURL(join(repositoryRoot, "scripts/ci/x.mjs")).href,
      undefined
    ),
    false
  );

  const directory = mkdtempSync(join(tmpdir(), "ascend wait entry "));
  const linkPath = join(directory, "wait-for-firestore-indexes.mjs");
  symlinkSync(
    join(repositoryRoot, "scripts/ci/wait-for-firestore-indexes.mjs"),
    linkPath
  );

  const invoked = spawnSync(process.execPath, [linkPath], {encoding: "utf8"});

  assert.equal(
    invoked.status,
    2,
    `Expected the gate to run and reject its arguments, got ` +
      `${invoked.status}: ${invoked.stdout}${invoked.stderr}`
  );
  assert.match(invoked.stderr, /Firebase project ID as the second argument/);
});

test("the index gate refuses a .firebaserc alias before reading any state", () => {
  const aliases = JSON.parse(
    readFileSync(join(repositoryRoot, ".firebaserc"), "utf8")
  ).projects;
  assert.equal(aliases.production, "ascend-prod-9c8f2");

  const {directory, contactLogPath} = contactRecordingFirebaseToolsStub();
  const invoked = spawnSync(
    process.execPath,
    [
      join(repositoryRoot, "scripts/ci/wait-for-firestore-indexes.mjs"),
      "firestore.indexes.json",
      "production",
      "(default)",
    ],
    {
      cwd: repositoryRoot,
      encoding: "utf8",
      env: {
        ...process.env,
        FIREBASE_TOOLS_ROOT: directory,
        FIREBASE_TOKEN: "ci-refresh-token",
      },
    }
  );

  assert.equal(
    invoked.status,
    2,
    `Expected a structural configuration failure, got ${invoked.status}: ` +
      `${invoked.stdout}${invoked.stderr}`
  );
  assert.match(invoked.stderr, /"production" is a \.firebaserc project alias/);
  assert.match(invoked.stderr, /never\s+resolves aliases/);
  assert.match(invoked.stderr, /ascend-prod-9c8f2/);
  assert.equal(
    existsSync(contactLogPath),
    false,
    "The gate contacted Firestore with an unresolved project alias"
  );
});

test("the index gate accepts a literal project ID and fails closed otherwise", () => {
  const firebaserc = readFileSync(join(repositoryRoot, ".firebaserc"), "utf8");

  assert.doesNotThrow(
    () => assertLiteralFirebaseProjectId("ascend-prod-9c8f2", firebaserc)
  );
  assert.doesNotThrow(
    () => assertLiteralFirebaseProjectId("ascend-staging-fa7d5", firebaserc)
  );
  assert.doesNotThrow(() => assertLiteralFirebaseProjectId(
    "ascend-prod-9c8f2",
    JSON.stringify({projects: {"ascend-prod-9c8f2": "ascend-prod-9c8f2"}})
  ));

  assert.throws(
    () => assertLiteralFirebaseProjectId("staging", firebaserc),
    /"staging" is a \.firebaserc project alias[\s\S]*ascend-staging-fa7d5/
  );
  assert.throws(
    () => assertLiteralFirebaseProjectId("default", firebaserc),
    /ascend-f2e4f/
  );
  assert.throws(
    () => assertLiteralFirebaseProjectId(
      "production",
      JSON.stringify({projects: {production: null}})
    ),
    /does not map it to a project ID/
  );
  assert.throws(
    () => assertLiteralFirebaseProjectId("production", "{ not json"),
    /\.firebaserc is not valid JSON/
  );
  assert.throws(
    () => assertLiteralFirebaseProjectId("production", JSON.stringify({})),
    /declares no "projects" alias map/
  );
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

function pinnedFirebaseToolsStub() {
  const directory = mkdtempSync(join(tmpdir(), "ascend-index-reader-"));
  const firestoreDirectory = join(directory, "lib/firestore");
  mkdirSync(firestoreDirectory, {recursive: true});
  writeFileSync(
    join(directory, "package.json"),
    JSON.stringify({
      name: "firebase-tools",
      version: PINNED_FIREBASE_TOOLS_VERSION,
    })
  );
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

  return directory;
}

// Records every touch of the pinned CLI's private modules, so a test can prove
// the gate refused its argument before any Firestore contact rather than after.
function contactRecordingFirebaseToolsStub() {
  const directory = mkdtempSync(join(tmpdir(), "ascend-index-alias-"));
  const firestoreDirectory = join(directory, "lib/firestore");
  mkdirSync(firestoreDirectory, {recursive: true});

  const contactLogPath = join(directory, "firestore-contact.log");
  const record = (event) =>
    `require("node:fs").appendFileSync(` +
      `${JSON.stringify(contactLogPath)}, ${JSON.stringify(`${event}\n`)});`;

  writeFileSync(
    join(directory, "package.json"),
    JSON.stringify({
      name: "firebase-tools",
      version: PINNED_FIREBASE_TOOLS_VERSION,
    })
  );
  writeFileSync(
    join(directory, "lib/auth.js"),
    [
      record("auth-loaded"),
      "exports.setRefreshToken = () => {};",
      "exports.getGlobalDefaultAccount = () => ({",
      "  tokens: {refresh_token: \"local-refresh-token\"},",
      "});",
    ].join("\n")
  );
  writeFileSync(
    join(firestoreDirectory, "api.js"),
    [
      record("api-loaded"),
      "exports.FirestoreApi = class {",
      `  async listIndexes() { ${record("listIndexes")} return []; }`,
      "  async listFieldOverrides() {",
      `    ${record("listFieldOverrides")}`,
      "    return [];",
      "  }",
      "};",
    ].join("\n")
  );

  return {directory, contactLogPath};
}

function escapeRegExp(value) {
  return value.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function firebaseHttpError(statusCode, message) {
  const error = new Error(`HTTP Error: ${statusCode}, ${message}`);
  error.status = statusCode;
  return error;
}

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
