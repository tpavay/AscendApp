/**
 * The forced-server read contract.
 *
 * A Firestore read with `source: .server` fails at once with `unavailable`
 * whenever the SDK has marked itself offline, which takes one failed stream
 * attempt and happens while the phone still has a working network path. Thirty
 * call sites forced the server that way and failed together during a network
 * handoff on 2026-10-03, each reporting it in its own words.
 *
 * `ServerPreferredRead` is the one place that decides what a forced read does
 * next - wait briefly and ask once more, heal a refusal, fall back to the
 * device's copy or throw. A call site that passes `source: .server` to the SDK
 * itself has stepped around it, and nothing at runtime would notice: it would
 * simply fail the old way the next time a stream drops.
 */

import test from "node:test";
import assert from "node:assert/strict";
import {readdirSync, readFileSync} from "node:fs";
import {dirname, join, relative, resolve} from "node:path";
import {fileURLToPath} from "node:url";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const APP_ROOT = join(REPO_ROOT, "AscendApp");

/** Where the SDK is handed `source: .server` on the app's behalf. */
const SERVER_READ_EXTENSIONS =
  "AscendApp/Shared/Services/ServerRead/Firestore+ServerRead.swift";

/**
 * The one read that chooses its Firestore source at runtime. It runs inside
 * `ServerPreferredRead.run`, which is what makes choosing `.server` safe.
 */
const RUNTIME_SOURCE_SELECTION =
  "AscendApp/Features/Leaderboards/ViewModels/LeaderboardViewModel.swift";

/** A direct SDK read whose source argument is the literal `.server`. */
const DIRECT_SERVER_READ =
  /\.(getDocuments|getDocument|getAggregation)\(\s*source:\s*\.server\b/;

/** `.server` chosen as a `FirestoreSource` value rather than passed inline. */
const SERVER_SOURCE_VALUE = /FirestoreSource\b[^\n]*\.server\b|\?\s*\.server\s*:/;

function swiftFiles(directory) {
  return readdirSync(directory, {withFileTypes: true}).flatMap((entry) => {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) return swiftFiles(path);
    return entry.name.endsWith(".swift") ? [path] : [];
  });
}

function matches(pattern, {except = []} = {}) {
  return swiftFiles(APP_ROOT).flatMap((path) => {
    const file = relative(REPO_ROOT, path);
    if (except.includes(file)) return [];
    return readFileSync(path, "utf8")
      .split("\n")
      .map((line, index) => ({line, number: index + 1}))
      .filter(({line}) => pattern.test(line))
      .map(({line, number}) => `${file}:${number}: ${line.trim()}`);
  });
}

test("the scan reads the app's Swift sources", () => {
  // A scan over the wrong directory finds no offenders and passes for nothing.
  assert.ok(swiftFiles(APP_ROOT).length > 500);
  assert.equal(
    matches(DIRECT_SERVER_READ).filter((hit) => hit.startsWith(SERVER_READ_EXTENSIONS)).length,
    3,
    "the three server-read extensions are the control: the scan must find them",
  );
});

test("no call site forces the server around ServerPreferredRead", () => {
  assert.deepEqual(
    matches(DIRECT_SERVER_READ, {except: [SERVER_READ_EXTENSIONS]}),
    [],
    "use getServerDocuments(), getServerDocument() or getServerAggregation() instead",
  );
});

test("only the leaderboard's shared read chooses the server at runtime", () => {
  assert.deepEqual(
    matches(SERVER_SOURCE_VALUE, {except: [SERVER_READ_EXTENSIONS, RUNTIME_SOURCE_SELECTION]}),
    [],
    "a read that may force the server belongs inside ServerPreferredRead.run",
  );

  const viewModel = readFileSync(join(REPO_ROOT, RUNTIME_SOURCE_SELECTION), "utf8");
  assert.match(viewModel, /ServerPreferredRead\.run\(/);
});
