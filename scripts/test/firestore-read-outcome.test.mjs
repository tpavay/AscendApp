import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {test} from "node:test";

import {
  EXIT_CODE,
  OUTCOME,
  classifyRead,
  firestoreConsoleUrl,
  objectMatchesPrefix,
  parseFirestorePath,
  renderReport,
  requirePathKind,
  resolveTarget,
} from "../lib/firestore-read-outcome.mjs";
import {parseArgs} from "../firestore-query.mjs";

const SCRIPTS_DIR = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const DEV_TARGET = {kind: "backend", projectId: "ascend-f2e4f", label: "ascend-f2e4f (dev)"};

test("a failed read is never reportable as an empty result", () => {
  const classified = classifyRead({failure: new Error("Could not refresh access token")});

  assert.equal(classified.outcome, OUTCOME.failed);
  assert.equal(classified.matchCount, null);
  assert.equal(classified.exitCode, EXIT_CODE.failed);

  const rendered = renderReport({
    target: DEV_TARGET,
    command: "count",
    path: "live_replay_leaderboards",
    classified,
  });

  // The whole point: nothing a caller could read as "there are zero of these".
  assert.equal(rendered.stdout, "");
  assert.match(rendered.stderr, /^FAILED/);
  assert.match(rendered.stderr, /NOT an empty result/);
  assert.doesNotMatch(rendered.stderr, /matches: 0/);
  assert.doesNotMatch(rendered.stderr, /EMPTY/);
  assert.notEqual(rendered.exitCode, 0);
});

test("a read with no usable count is a failure, not an emptiness", () => {
  for (const matchCount of [null, undefined, NaN, -1, "0"]) {
    const classified = classifyRead({matchCount});
    assert.equal(classified.outcome, OUTCOME.failed, `matchCount ${String(matchCount)}`);
    assert.equal(classified.exitCode, EXIT_CODE.failed);
  }
});

test("zero results without a control probe stay unverified and exit non-zero", () => {
  const classified = classifyRead({matchCount: 0});

  assert.equal(classified.outcome, OUTCOME.emptyUnverified);
  assert.equal(classified.exitCode, EXIT_CODE.emptyUnverified);
  assert.notEqual(classified.exitCode, 0);

  const rendered = renderReport({
    target: DEV_TARGET,
    command: "count",
    path: "users/abc/workouts",
    classified,
  });
  assert.match(rendered.stdout, /UNVERIFIED/);
  assert.match(rendered.stdout, /Do NOT report this path as empty/);
});

test("zero results are verified empty only once the same method found data elsewhere", () => {
  const classified = classifyRead({
    matchCount: 0,
    control: {path: "users", matchCount: 14, failure: null},
  });

  assert.equal(classified.outcome, OUTCOME.emptyVerified);
  assert.equal(classified.exitCode, 0);
  assert.match(classified.reason, /returned 14 at the known-populated control path users/);
});

test("a control probe that failed or was itself empty proves nothing", () => {
  const failedControl = classifyRead({
    matchCount: 0,
    control: {path: "users", matchCount: null, failure: "PERMISSION_DENIED"},
  });
  assert.equal(failedControl.outcome, OUTCOME.emptyUnverified);
  assert.match(failedControl.reason, /failed/);

  const emptyControl = classifyRead({
    matchCount: 0,
    control: {path: "users", matchCount: 0, failure: null},
  });
  assert.equal(emptyControl.outcome, OUTCOME.emptyUnverified);
  assert.match(emptyControl.reason, /also returned nothing/);
});

test("a positive result needs no control probe", () => {
  const classified = classifyRead({matchCount: 59});
  assert.equal(classified.outcome, OUTCOME.found);
  assert.equal(classified.exitCode, 0);
});

test("environment aliases resolve, raw project IDs do not", () => {
  assert.equal(resolveTarget({env: "dev"}).projectId, "ascend-f2e4f");
  assert.equal(resolveTarget({env: "staging"}).projectId, "ascend-staging-fa7d5");
  assert.throws(() => resolveTarget({env: "ascend-prod-9c8f2"}), /Unknown environment/);
  assert.throws(() => resolveTarget({env: "qa"}), /Unknown environment/);
});

test("production reads require the confirmation flag", () => {
  assert.throws(() => resolveTarget({env: "prod"}), /requires --confirm-production/);
  assert.throws(() => resolveTarget({env: "production"}), /requires --confirm-production/);
  assert.equal(
    resolveTarget({env: "prod", confirmProduction: true}).projectId,
    "ascend-prod-9c8f2"
  );
});

test("a running emulator is the default target, but never overrides an explicit --env", () => {
  const implicit = resolveTarget({env: null, emulatorRunning: true});
  assert.equal(implicit.kind, "emulator");

  const explicit = resolveTarget({env: "staging", emulatorRunning: true});
  assert.equal(explicit.kind, "backend");
  assert.equal(explicit.projectId, "ascend-staging-fa7d5");

  assert.throws(() => resolveTarget({env: null, emulatorRunning: false}), /No target/);
});

test("every rendered line names the database that was actually read", () => {
  for (const classified of [
    classifyRead({matchCount: 3}),
    classifyRead({matchCount: 0}),
    classifyRead({failure: new Error("boom")}),
  ]) {
    const rendered = renderReport({
      target: {kind: "backend", projectId: "ascend-prod-9c8f2", label: "ascend-prod-9c8f2 (prod)"},
      command: "count",
      path: "users",
      classified,
    });
    assert.match(`${rendered.stdout}${rendered.stderr}`, /ascend-prod-9c8f2 \(prod\)/);
  }
});

test("document and collection paths are told apart by segment count", () => {
  assert.equal(parseFirestorePath("users").kind, "collection");
  assert.equal(parseFirestorePath("users/abc").kind, "document");
  assert.equal(
    parseFirestorePath("live_replay_leaderboards/k/splitBuckets/0/entries").kind,
    "collection"
  );
  assert.throws(() => parseFirestorePath("users//abc"), /empty segment/);
  assert.throws(() => parseFirestorePath(""), /Path is required/);
  assert.throws(() => requirePathKind("users/abc", "collection"), /needs a collection path/);
  assert.throws(() => requirePathKind("users", "document"), /needs a document path/);
});

test("a Storage prefix anchors at the start instead of matching anywhere", () => {
  // Six flat-path objects were once reported as nineteen because the owner-scoped
  // prefix contains the flat one as a substring.
  assert.ok(objectMatchesPrefix("profile_pictures/a.jpg", "profile_pictures/"));
  assert.equal(objectMatchesPrefix("users/uid-1/profile_pictures/a.jpg", "profile_pictures/"), false);
  assert.ok(objectMatchesPrefix("users/uid-1/profile_pictures/a.jpg", "users/"));
});

test("console deep links point at the document, encoded the way the console reads it", () => {
  assert.equal(
    firestoreConsoleUrl("ascend-f2e4f", "live_replay_leaderboards/live_climb__burj-khalifa"),
    "https://console.firebase.google.com/project/ascend-f2e4f/firestore/databases/-default-/data/" +
      "~2Flive_replay_leaderboards~2Flive_climb__burj-khalifa"
  );
});

test("argument parsing rejects a command that would read the wrong shape of path", () => {
  const parsed = parseArgs(["node", "firestore-query.mjs", "count", "users", "--env", "dev"]);
  assert.equal(parsed.command, "count");
  assert.equal(parsed.path, "users");
  assert.equal(parsed.env, "dev");

  assert.throws(() => parseArgs(["node", "x", "query", "users"]), /Command must be one of/);
  assert.throws(() => parseArgs(["node", "x", "count"]), /needs a path/);
  assert.throws(() => parseArgs(["node", "x", "count", "users", "--env"]), /--env needs a value/);
  assert.throws(() => parseArgs(["node", "x", "count", "users", "--limit", "0"]), /positive integer/);
  assert.throws(() => parseArgs(["node", "x", "count", "users", "--delete"]), /Unknown argument/);
});

test("the investigation tooling cannot write, and no credential is committed with it", () => {
  const sources = [
    readFileSync(resolve(SCRIPTS_DIR, "firestore-query.mjs"), "utf8"),
    readFileSync(resolve(SCRIPTS_DIR, "lib", "firestore-read-outcome.mjs"), "utf8"),
  ].join("\n");

  const mutatingCalls = [
    /\.set\(/, /\.update\(/, /\.delete\(/, /\.create\(/, /\.add\(/,
    /\.batch\(/, /bulkWriter/, /recursiveDelete/, /runTransaction/,
    /\.save\(/, /deleteFiles/, /\.upload\(/,
  ];
  for (const pattern of mutatingCalls) {
    assert.doesNotMatch(sources, pattern, `read-only tooling must not call ${pattern}`);
  }

  const credentials = [
    /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
    /"private_key"/,
    /ya29\./,
    /AIza[0-9A-Za-z_-]{20}/,
  ];
  for (const pattern of credentials) {
    assert.doesNotMatch(sources, pattern, `no credential may be committed (${pattern})`);
  }
});
