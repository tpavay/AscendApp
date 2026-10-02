import test from "node:test";
import assert from "node:assert/strict";

import {
  PRODUCTION_PROJECT_ID,
  catalogueUrl,
  compareVersions,
  defaultAssetBaseUrl,
  parseArgs,
  resolveTarget,
} from "../send-drop-email.mjs";
import {parseArgs as parseSkipArgs} from "../skip-stale-email-jobs.mjs";

const argv = (...args) => ["node", "send-drop-email.mjs", ...args];

test("a run with no mode is a dry run", () => {
  const args = parseArgs(argv("--env", "staging", "--drop", "halloween-2026"));
  assert.equal(args.send, false);
  assert.equal(args.testTo, null);
  assert.equal(args.preview, null);
  assert.equal(args.status, false);
});

test("modes are exclusive", () => {
  assert.throws(
    () => parseArgs(argv("--send", "--test-to", "a@example.com")),
    /Pick one of/
  );
  assert.throws(() => parseArgs(argv("--send", "--status")), /Pick one of/);
});

test("the real send cannot borrow another site's images", () => {
  assert.throws(
    () => parseArgs(argv("--send", "--asset-base-url", "https://x.web.app")),
    /--preview and --test-to only/
  );
  assert.equal(
    parseArgs(argv("--test-to", "a@example.com", "--asset-base-url",
      "https://x.web.app/")).assetBaseUrl,
    "https://x.web.app"
  );
  assert.throws(
    () => parseArgs(argv("--asset-base-url", "http://x.web.app")),
    /https/
  );
});

test("a test send needs an address", () => {
  assert.throws(() => parseArgs(argv("--test-to", "nobody")), /email address/);
});

test("production needs its project id spelled out, dry run included", () => {
  assert.throws(() => resolveTarget({env: null}), /No target/);
  assert.throws(() => resolveTarget({env: "prod"}), /--confirm-production/);
  assert.throws(
    () => resolveTarget({env: "prod", confirmProduction: "ascend-staging-fa7d5"}),
    /--confirm-production/
  );
  assert.equal(
    resolveTarget({env: "prod", confirmProduction: PRODUCTION_PROJECT_ID})
      .projectId,
    PRODUCTION_PROJECT_ID
  );
  assert.equal(resolveTarget({env: "staging"}).projectId, "ascend-staging-fa7d5");
});

test("images and the catalogue come from the target's own site", () => {
  assert.equal(defaultAssetBaseUrl(PRODUCTION_PROJECT_ID), "https://ascendstepper.com");
  assert.equal(
    defaultAssetBaseUrl("ascend-staging-fa7d5"),
    "https://ascend-staging-fa7d5.web.app"
  );
  assert.equal(
    catalogueUrl(PRODUCTION_PROJECT_ID),
    "https://ascend-prod-9c8f2.web.app/unlocks/catalog.json"
  );
});

test("app versions compare numerically", () => {
  assert.ok(compareVersions("1.2.2", "1.2.2") === 0);
  assert.ok(compareVersions("1.3", "1.2.2") > 0);
  assert.ok(compareVersions("1.2.1", "1.2.2") < 0);
  assert.ok(compareVersions("1.10", "1.9") > 0);
  assert.ok(compareVersions("1.2", "1.2.0") === 0);
});

test("the stale skip needs a zoned cutoff and commits only when told", () => {
  const skipArgv = (...args) => ["node", "skip-stale-email-jobs.mjs", ...args];
  assert.throws(() => parseSkipArgs(skipArgv("--env", "dev")), /--before is required/);
  assert.throws(
    () => parseSkipArgs(skipArgv("--before", "2026-10-02T12:00:00")),
    /with a zone/
  );
  const args = parseSkipArgs(skipArgv("--env", "dev", "--before", "2026-10-02T12:00:00Z"));
  assert.equal(args.commit, false);
  assert.equal(args.before.toISOString(), "2026-10-02T12:00:00.000Z");
  assert.equal(
    parseSkipArgs(skipArgv("--before", "2026-10-02T07:00:00-05:00", "--commit"))
      .commit,
    true
  );
});
