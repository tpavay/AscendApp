import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {copyFileSync, mkdirSync, mkdtempSync, writeFileSync} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  BUILDS_PER_DAY,
  MAX_BUILD_NUMBER,
  PREVIOUS_BUILD_NUMBER_FLOOR,
  deriveReadableBuildNumber,
  fetchHighestUploadedBuildNumber,
  utcDateStamp,
} from "../ci/derive-build-number.mjs";
import {awaitBuildUploadRecorded} from "../ci/await-build-upload-recorded.mjs";
import {
  appStoreConnectRequest,
  readAppStoreConnectCredentials,
} from "../lib/app-store-connect-client.mjs";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));

test("the first build of a UTC day is readable and later builds increment", () => {
  assert.equal(deriveReadableBuildNumber("20260803", null), 2_026_080_301);
  assert.equal(deriveReadableBuildNumber("20260803", "2026080301"), 2_026_080_302);
  assert.equal(deriveReadableBuildNumber("20260803", "37102594"), 2_026_080_301);
});

test("a new UTC day outranks all 99 builds from the previous day", () => {
  assert.equal(BUILDS_PER_DAY, 99);
  assert.ok(
    deriveReadableBuildNumber("20260804", "2026080399") >
      deriveReadableBuildNumber("20260803", "2026080398"),
  );
  assert.equal(deriveReadableBuildNumber("20260804", "2026080399"), 2_026_080_401);
});

test("the cutover moves upward from the legacy clock sequence", () => {
  assert.equal(PREVIOUS_BUILD_NUMBER_FLOOR, 37_105_794);
  const firstReadableBuild = deriveReadableBuildNumber("20260803", PREVIOUS_BUILD_NUMBER_FLOOR);

  assert.equal(firstReadableBuild, 2_026_080_301);
  assert.ok(firstReadableBuild > PREVIOUS_BUILD_NUMBER_FLOOR);
});

test("a 100th build in one day fails instead of wrapping", () => {
  assert.throws(
    () => deriveReadableBuildNumber("20260803", "2026080399"),
    /Daily build-number sequence exhausted.*100th build/s,
  );
});

test("a remote build ahead of today's range fails instead of regressing", () => {
  assert.throws(
    () => deriveReadableBuildNumber("20260803", "2026080401"),
    /Refusing to emit a duplicate or regressing build number/,
  );
});

test("the legacy floor and 32-bit ceiling remain hard guards", () => {
  assert.equal(MAX_BUILD_NUMBER, 4_294_967_295);
  assert.throws(
    () => deriveReadableBuildNumber("00010101", null),
    /not above the legacy cutover floor/,
  );
  assert.equal(deriveReadableBuildNumber("42941231", null), 4_294_123_101);
  assert.throws(
    () => deriveReadableBuildNumber("42950101", null),
    /exceeds the App Store limit/,
  );
});

test("UTC timestamps resolve to the promised calendar date", () => {
  assert.equal(utcDateStamp(Date.parse("2026-08-03T23:59:59Z") / 1_000), "20260803");
  assert.equal(utcDateStamp(Date.parse("2026-08-04T00:00:00Z") / 1_000), "20260804");
});

test("App Store Connect is paginated and the numeric maximum is used", async () => {
  const requests = [];
  const responses = [
    {data: {attributes: {bundleId: "com.TylerPavay.AscendApp.staging"}}},
    {
      data: [
        {attributes: {version: "2026080301"}},
        {attributes: {version: "37102594"}},
      ],
      links: {next: "https://api.appstoreconnect.apple.com/v1/builds?cursor=next"},
    },
    {
      data: [{attributes: {version: "2026080302"}}],
      links: {next: null},
    },
    {
      data: [
        {
          attributes: {
            cfBundleVersion: "2026080303",
            state: {state: "PROCESSING"},
          },
        },
        {
          attributes: {
            cfBundleVersion: "2026080399",
            state: {state: "FAILED"},
          },
        },
      ],
      links: {next: null},
    },
  ];
  const request = async (token, path) => {
    requests.push({token, path});
    return responses.shift();
  };

  const highest = await fetchHighestUploadedBuildNumber(
    {
      token: "redacted-test-token",
      appId: "6759919365",
      expectedBundleId: "com.TylerPavay.AscendApp.staging",
    },
    request,
  );

  assert.equal(highest, "2026080303");
  assert.equal(requests.length, 4);
  assert.match(requests[1].path, /filter%5Bapp%5D=6759919365/);
  assert.equal(requests[2].path, "https://api.appstoreconnect.apple.com/v1/builds?cursor=next");
  assert.match(requests[3].path, /apps\/6759919365\/buildUploads/);
});

test("the allocator refuses an App Store app and bundle mismatch", async () => {
  const request = async () => ({
    data: {attributes: {bundleId: "com.TylerPavay.AscendApp"}},
  });

  await assert.rejects(
    fetchHighestUploadedBuildNumber(
      {
        token: "redacted-test-token",
        appId: "6757202987",
        expectedBundleId: "com.TylerPavay.AscendApp.staging",
      },
      request,
    ),
    /not expected bundle/,
  );
});

// Ownership is the check that proves both scripts are looking at the right
// app, so its deterministic refusal must name its own assumption rather than
// arrive as a bare status alongside the listings that already do.
test("a deterministic ownership refusal names the assumption that broke", async () => {
  const refuseOwnership = async () => {
    const error = new Error("App Store Connect GET /v1/apps/6759919365 failed (400): Parameter error");
    error.status = 400;
    throw error;
  };

  await assert.rejects(
    fetchHighestUploadedBuildNumber(
      {
        token: "redacted-test-token",
        appId: "6759919365",
        expectedBundleId: "com.TylerPavay.AscendApp.staging",
      },
      refuseOwnership,
    ),
    /APP_STORE_CONTRACT_REJECTED:.*fields\[apps\]=bundleId,name/s,
  );

  await assert.rejects(
    awaitBuildUploadRecorded(
      {
        appId: "6759919365",
        expectedBundleId: "com.TylerPavay.AscendApp.staging",
        buildNumber: "2026080301",
      },
      {
        makeToken: () => "redacted-test-token",
        request: refuseOwnership,
        report: () => {},
      },
    ),
    /APP_STORE_CONTRACT_REJECTED:.*fields\[apps\]=bundleId,name/s,
  );
});

// The allocator sweeps the whole upload history, so one record Apple starts
// reporting differently must cost a build number, never every future deploy.
test("an unknown or missing upload state still reserves its build number", async () => {
  const responses = [
    {data: {attributes: {bundleId: "com.TylerPavay.AscendApp.staging"}}},
    {data: [{attributes: {version: "2026080301"}}], links: {next: null}},
    {
      data: [
        {attributes: {cfBundleVersion: "2026080304", state: {state: "QUARANTINED"}}},
        {attributes: {cfBundleVersion: "2026080303"}},
        {attributes: {cfBundleVersion: "2026080399", state: {state: "FAILED"}}},
      ],
      links: {next: null},
    },
  ];

  const highest = await fetchHighestUploadedBuildNumber(
    {
      token: "redacted-test-token",
      appId: "6759919365",
      expectedBundleId: "com.TylerPavay.AscendApp.staging",
    },
    async () => responses.shift(),
  );

  assert.equal(highest, "2026080304");
});

test("a deterministic allocator rejection names the assumption that broke", async () => {
  const responses = [{data: {attributes: {bundleId: "com.TylerPavay.AscendApp.staging"}}}];

  await assert.rejects(
    fetchHighestUploadedBuildNumber(
      {
        token: "redacted-test-token",
        appId: "6759919365",
        expectedBundleId: "com.TylerPavay.AscendApp.staging",
      },
      async () => {
        const queued = responses.shift();
        if (queued) return queued;

        const error = new Error("App Store Connect GET /v1/builds failed (400): Parameter error");
        error.status = 400;
        throw error;
      },
    ),
    /APP_STORE_CONTRACT_REJECTED:.*fields\[builds\]=version/s,
  );
});

test("an allocator listing without a data array refuses to allocate", async () => {
  const responses = [
    {data: {attributes: {bundleId: "com.TylerPavay.AscendApp.staging"}}},
    {links: {next: null}},
  ];

  await assert.rejects(
    fetchHighestUploadedBuildNumber(
      {
        token: "redacted-test-token",
        appId: "6759919365",
        expectedBundleId: "com.TylerPavay.AscendApp.staging",
      },
      async () => responses.shift(),
    ),
    /APP_STORE_CONTRACT_UNEXPECTED_SHAPE.*build listing/s,
  );
});

test("the allocator refuses non-numeric remote build numbers", async () => {
  const responses = [
    {data: {attributes: {bundleId: "com.TylerPavay.AscendApp.staging"}}},
    {data: [{attributes: {version: "1.2.3"}}], links: {next: null}},
  ];

  await assert.rejects(
    fetchHighestUploadedBuildNumber(
      {
        token: "redacted-test-token",
        appId: "6759919365",
        expectedBundleId: "com.TylerPavay.AscendApp.staging",
      },
      async () => responses.shift(),
    ),
    /non-numeric build number/,
  );
});

test("missing credentials fail before any App Store Connect request", () => {
  assert.throws(
    () => readAppStoreConnectCredentials({}),
    /APP_STORE_CONNECT_API_KEY_ID.*APP_STORE_CONNECT_API_ISSUER_ID.*APP_STORE_CONNECT_API_KEY/,
  );
});

test("an unavailable App Store Connect API fails closed", async () => {
  await assert.rejects(
    appStoreConnectRequest("redacted-test-token", "/builds", {
      fetchImplementation: async () => ({
        status: 503,
        ok: false,
        text: async () => JSON.stringify({errors: [{title: "Unavailable", detail: "Retry later"}]}),
      }),
    }),
    /failed \(503\): Unavailable: Retry later/,
  );
});

// `import.meta.url` is both percent-encoded and realpath-resolved; `process.argv[1]`
// is neither. A main-module guard that compares them as strings silently exits 0
// having written nothing whenever the invocation path holds a space or crosses a
// symlink - and the deploy archives that empty value as its CFBundleVersion.
// The temp root below is both: it contains spaces and sits behind /private on macOS.
test("the CI entrypoints still run from a path with spaces or a symlink", () => {
  const root = mkdtempSync(join(tmpdir(), "ascend build number "));
  mkdirSync(join(root, "scripts/ci"), {recursive: true});
  mkdirSync(join(root, "scripts/lib"), {recursive: true});
  for (const file of [
    "scripts/ci/derive-build-number.mjs",
    "scripts/ci/await-build-upload-recorded.mjs",
    "scripts/lib/app-store-connect-client.mjs",
    "scripts/lib/app-store-connect-build-uploads.mjs",
    "scripts/lib/is-entrypoint.mjs",
  ]) {
    copyFileSync(join(repositoryRoot, file), join(root, file));
  }

  assert.ok(root.includes(" "));

  for (const [script, usage] of [
    ["derive-build-number.mjs", /::error::Usage: derive-build-number/],
    ["await-build-upload-recorded.mjs", /::error::Usage: await-build-upload-recorded/],
  ]) {
    const result = spawnSync(process.execPath, [join(root, "scripts/ci", script)], {
      encoding: "utf8",
    });

    assert.notEqual(result.status, 0, `${script} never ran main and exited 0`);
    assert.match(result.stderr, usage);
    assert.equal(result.stdout, "");
  }
});

// A clock that only advances when the poller sleeps, so the elapsed budget the
// loop enforces is exactly what the assertions below can pin.
function testClock() {
  const slept = [];
  let current = 0;

  return {
    slept,
    now: () => current,
    sleep: async (seconds) => {
      slept.push(seconds);
      current += seconds * 1_000;
    },
  };
}

function isAppOwnershipRequest(path) {
  return /^\/apps\/[^/]+\?/.test(path);
}

test("the upload holds the concurrency group until the exact upload is recorded", async () => {
  const paths = [];
  const responses = [
    {data: {attributes: {bundleId: "com.TylerPavay.AscendApp.staging"}}},
    {data: []},
    {
      data: [
        {
          attributes: {
            cfBundleVersion: "2026080301",
            state: {state: "AWAITING_UPLOAD"},
          },
        },
      ],
    },
    {
      data: [
        {
          attributes: {
            cfBundleVersion: "2026080301",
            state: {state: "PROCESSING"},
          },
        },
      ],
    },
  ];
  const clock = testClock();

  const outcome = await awaitBuildUploadRecorded(
    {
      appId: "6759919365",
      expectedBundleId: "com.TylerPavay.AscendApp.staging",
      buildNumber: "2026080301",
      timeoutSeconds: 60,
      pollIntervalSeconds: 15,
    },
    {
      makeToken: () => "redacted-test-token",
      request: async (token, path) => {
        paths.push(path);
        return responses.shift();
      },
      sleep: clock.sleep,
      now: clock.now,
      report: () => {},
    },
  );

  assert.deepEqual(outcome, {attempt: 3, state: "PROCESSING"});
  assert.deepEqual(clock.slept, [15, 15]);
  assert.match(paths[1], /apps\/6759919365\/buildUploads/);
  assert.match(paths[1], /filter%5BcfBundleVersion%5D=2026080301/);
});

const ipaVerifier = join(repositoryRoot, "scripts/ci/verify-ipa-build-number.sh");

// The verifier decides whether a deploy uploads at all, so its argument
// handling is asserted on every runner. Only the CFBundleVersion extraction
// needs macOS, and that half lives in the test below.
test("the IPA verifier refuses a missing, non-numeric, or unreadable handoff", () => {
  const root = mkdtempSync(join(tmpdir(), "ascend ipa handoff "));
  const absentIpa = join(root, "AscendApp.ipa");

  const missing = spawnSync(ipaVerifier, [absentIpa, ""], {encoding: "utf8"});
  assert.notEqual(missing.status, 0);
  assert.match(missing.stderr, /BUILD_NUMBER_HANDOFF_MISSING/);
  assert.equal(missing.stdout, "");

  const noArguments = spawnSync(ipaVerifier, [], {encoding: "utf8"});
  assert.notEqual(noArguments.status, 0);
  assert.match(noArguments.stderr, /BUILD_NUMBER_HANDOFF_MISSING/);

  for (const invalid of ["1.2.3", "2026080601a", " 2026080601"]) {
    const rejected = spawnSync(ipaVerifier, [absentIpa, invalid], {encoding: "utf8"});
    assert.notEqual(rejected.status, 0, invalid);
    assert.match(rejected.stderr, /BUILD_NUMBER_HANDOFF_INVALID/, invalid);
    assert.equal(rejected.stdout, "", invalid);
  }

  // A valid number against an IPA that never arrived must name the artifact
  // problem, not the handoff.
  const unavailable = spawnSync(ipaVerifier, [absentIpa, "2026080601"], {encoding: "utf8"});
  assert.notEqual(unavailable.status, 0);
  assert.match(unavailable.stderr, /IPA_BUILD_NUMBER_UNAVAILABLE/);
});

test(
  "the IPA verifier rejects a mismatched handoff and returns the embedded value",
  {skip: process.platform !== "darwin"},
  () => {
    const root = mkdtempSync(join(tmpdir(), "ascend ipa build number "));
    const appDirectory = join(root, "Payload", "AscendApp.app");
    const ipaPath = join(root, "AscendApp.ipa");
    mkdirSync(appDirectory, {recursive: true});
    writeFileSync(
      join(appDirectory, "Info.plist"),
      `<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>CFBundleVersion</key>
  <string>2026080602</string>
</dict>
</plist>\n`,
    );

    const zipped = spawnSync("zip", ["-q", "-r", ipaPath, "Payload"], {
      cwd: root,
      encoding: "utf8",
    });
    assert.equal(zipped.status, 0, zipped.stderr);

    const missing = spawnSync(ipaVerifier, [ipaPath, ""], {encoding: "utf8"});
    assert.notEqual(missing.status, 0);
    assert.match(missing.stderr, /BUILD_NUMBER_HANDOFF_MISSING/);

    const mismatch = spawnSync(ipaVerifier, [ipaPath, "2026080601"], {encoding: "utf8"});
    assert.notEqual(mismatch.status, 0);
    assert.match(mismatch.stderr, /BUILD_NUMBER_HANDOFF_MISMATCH/);

    const verified = spawnSync(ipaVerifier, [ipaPath, "2026080602"], {encoding: "utf8"});
    assert.equal(verified.status, 0, verified.stderr);
    assert.equal(verified.stdout, "2026080602\n");
  },
);

// TOKEN_LIFETIME_SECONDS equals the default poll budget, so a token minted once
// up front expires mid-poll and turns a build that appears late into a 401.
test("every upload-ledger poll attempt carries a freshly minted token", async () => {
  const tokens = [];
  const clock = testClock();

  await assert.rejects(
    awaitBuildUploadRecorded(
      {
        appId: "6759919365",
        expectedBundleId: "com.TylerPavay.AscendApp.staging",
        buildNumber: "2026080301",
        timeoutSeconds: 45,
        pollIntervalSeconds: 15,
      },
      {
        makeToken: () => {
          const token = `token-${tokens.length}`;
          tokens.push(token);
          return token;
        },
        request: async (token, path) => {
          if (isAppOwnershipRequest(path)) {
            return {data: {attributes: {bundleId: "com.TylerPavay.AscendApp.staging"}}};
          }
          assert.equal(token, tokens.at(-1), "a poll reused a stale token");
          return {data: []};
        },
        sleep: clock.sleep,
        now: clock.now,
        report: () => {},
      },
    ),
    /APP_STORE_UPLOAD_RECORD_TIMEOUT/,
  );

  // One for the ownership check plus one per poll attempt.
  assert.equal(tokens.length, 5);
  assert.equal(new Set(tokens).size, tokens.length);
});

test("transient App Store Connect failures do not fail a recorded upload", async () => {
  const clock = testClock();
  const outcomes = [
    () => {
      throw new Error("App Store Connect GET /v1/buildUploads failed (503): Unavailable: Retry later");
    },
    () => {
      throw new Error("App Store Connect GET /v1/buildUploads failed (429): Too many requests");
    },
    () => ({data: []}),
    () => ({
      data: [
        {
          attributes: {
            cfBundleVersion: "2026080301",
            state: {state: "COMPLETE"},
          },
        },
      ],
    }),
  ];
  const reported = [];

  const outcome = await awaitBuildUploadRecorded(
    {
      appId: "6759919365",
      expectedBundleId: "com.TylerPavay.AscendApp.staging",
      buildNumber: "2026080301",
      timeoutSeconds: 900,
      pollIntervalSeconds: 15,
    },
    {
      makeToken: () => "redacted-test-token",
      request: async (token, path) => {
        if (isAppOwnershipRequest(path)) {
          return {data: {attributes: {bundleId: "com.TylerPavay.AscendApp.staging"}}};
        }
        return outcomes.shift()();
      },
      sleep: clock.sleep,
      now: clock.now,
      report: (message) => reported.push(message),
    },
  );

  assert.deepEqual(outcome, {attempt: 4, state: "COMPLETE"});
  assert.equal(outcomes.length, 0);
  assert.ok(reported.some((message) => /failed on attempt 1.*503/.test(message)));
  assert.ok(reported.some((message) => /failed on attempt 2.*429/.test(message)));
  assert.ok(reported.every((message) => !message.includes("redacted-test-token")));
});

test("a failed upload stops immediately with Apple's details", async () => {
  const clock = testClock();

  await assert.rejects(
    awaitBuildUploadRecorded(
      {
        appId: "6759919365",
        expectedBundleId: "com.TylerPavay.AscendApp.staging",
        buildNumber: "2026080301",
        timeoutSeconds: 900,
        pollIntervalSeconds: 15,
      },
      {
        makeToken: () => "redacted-test-token",
        request: async (token, path) => {
          if (isAppOwnershipRequest(path)) {
            return {data: {attributes: {bundleId: "com.TylerPavay.AscendApp.staging"}}};
          }
          return {
            data: [
              {
                attributes: {
                  cfBundleVersion: "2026080301",
                  state: {
                    state: "FAILED",
                    errors: [{code: "INVALID_BINARY", message: "Invalid binary"}],
                  },
                },
              },
            ],
          };
        },
        sleep: clock.sleep,
        now: clock.now,
        report: () => {},
      },
    ),
    /APP_STORE_UPLOAD_FAILED:.*Invalid binary.*permits reusing/s,
  );

  assert.deepEqual(clock.slept, []);
});

test("an upload absent from the ledger fails loudly within a bounded timeout", async () => {
  let polls = 0;
  const clock = testClock();

  await assert.rejects(
    awaitBuildUploadRecorded(
      {
        appId: "6759919365",
        expectedBundleId: "com.TylerPavay.AscendApp.staging",
        buildNumber: "2026080301",
        timeoutSeconds: 45,
        pollIntervalSeconds: 15,
      },
      {
        makeToken: () => "redacted-test-token",
        request: async (token, path) => {
          if (isAppOwnershipRequest(path)) {
            return {data: {attributes: {bundleId: "com.TylerPavay.AscendApp.staging"}}};
          }
          polls += 1;
          return {data: []};
        },
        sleep: clock.sleep,
        now: clock.now,
        report: () => {},
      },
    ),
    /APP_STORE_UPLOAD_RECORD_TIMEOUT:.*not recorded as PROCESSING or COMPLETE after 45s across 4 attempts/s,
  );

  // The reported budget must be what actually elapsed, not one interval more.
  assert.equal(polls, 4);
  assert.deepEqual(clock.slept, [15, 15, 15]);
});

test("a timeout spent entirely on transient errors names the last one", async () => {
  const clock = testClock();

  await assert.rejects(
    awaitBuildUploadRecorded(
      {
        appId: "6759919365",
        expectedBundleId: "com.TylerPavay.AscendApp.staging",
        buildNumber: "2026080301",
        timeoutSeconds: 30,
        pollIntervalSeconds: 15,
      },
      {
        makeToken: () => "redacted-test-token",
        request: async (token, path) => {
          if (isAppOwnershipRequest(path)) {
            return {data: {attributes: {bundleId: "com.TylerPavay.AscendApp.staging"}}};
          }
          throw new Error("App Store Connect GET /v1/builds failed (500): Internal");
        },
        sleep: clock.sleep,
        now: clock.now,
        report: () => {},
      },
    ),
    /after 30s across 3 attempts \(last error: .*500.*\)/s,
  );
});

test("a deterministic upload-ledger rejection is fatal rather than retried", async () => {
  const clock = testClock();
  let ledgerRequests = 0;

  await assert.rejects(
    awaitBuildUploadRecorded(
      {
        appId: "6759919365",
        expectedBundleId: "com.TylerPavay.AscendApp.staging",
        buildNumber: "2026080301",
      },
      {
        makeToken: () => "redacted-test-token",
        request: async (token, path) => {
          if (isAppOwnershipRequest(path)) {
            return {data: {attributes: {bundleId: "com.TylerPavay.AscendApp.staging"}}};
          }
          ledgerRequests += 1;
          const error = new Error("App Store Connect rejected the upload-ledger query (403)");
          error.status = 403;
          throw error;
        },
        sleep: clock.sleep,
        now: clock.now,
        report: () => {},
      },
    ),
    /upload-ledger query \(403\)/,
  );

  assert.equal(ledgerRequests, 1);
  assert.deepEqual(clock.slept, []);
});

// Apple reuses a number after a FAILED upload and the query declares no
// ordering, so the record that answers must be the one that names this build.
test("a reused build number resolves on the live record, not the failed one", async () => {
  const clock = testClock();

  const outcome = await awaitBuildUploadRecorded(
    {
      appId: "6759919365",
      expectedBundleId: "com.TylerPavay.AscendApp.staging",
      buildNumber: "2026080301",
      timeoutSeconds: 900,
      pollIntervalSeconds: 15,
    },
    {
      makeToken: () => "redacted-test-token",
      request: async (token, path) => {
        if (isAppOwnershipRequest(path)) {
          return {data: {attributes: {bundleId: "com.TylerPavay.AscendApp.staging"}}};
        }
        return {
          data: [
            {
              attributes: {
                cfBundleVersion: "2026080301",
                state: {state: "FAILED", errors: [{message: "Invalid binary"}]},
              },
            },
            {
              attributes: {
                cfBundleVersion: "2026080301",
                state: {state: "PROCESSING"},
              },
            },
          ],
        };
      },
      sleep: clock.sleep,
      now: clock.now,
      report: () => {},
    },
  );

  assert.deepEqual(outcome, {attempt: 1, state: "PROCESSING"});
  assert.deepEqual(clock.slept, []);
});

test("the wait does not poll without a limit clamped to one record", async () => {
  const paths = [];
  const clock = testClock();

  await assert.rejects(
    awaitBuildUploadRecorded(
      {
        appId: "6759919365",
        expectedBundleId: "com.TylerPavay.AscendApp.staging",
        buildNumber: "2026080301",
        timeoutSeconds: 15,
        pollIntervalSeconds: 15,
      },
      {
        makeToken: () => "redacted-test-token",
        request: async (token, path) => {
          paths.push(path);
          if (isAppOwnershipRequest(path)) {
            return {data: {attributes: {bundleId: "com.TylerPavay.AscendApp.staging"}}};
          }
          return {data: []};
        },
        sleep: clock.sleep,
        now: clock.now,
        report: () => {},
      },
    ),
    /APP_STORE_UPLOAD_RECORD_TIMEOUT/,
  );

  assert.match(paths[1], /limit=200/);
  assert.doesNotMatch(paths[1], /limit=1(?!\d)/);
});

test("an ignored cfBundleVersion filter is a fatal contract break, not a wait", async () => {
  const clock = testClock();
  let ledgerRequests = 0;

  await assert.rejects(
    awaitBuildUploadRecorded(
      {
        appId: "6759919365",
        expectedBundleId: "com.TylerPavay.AscendApp.staging",
        buildNumber: "2026080301",
        timeoutSeconds: 900,
        pollIntervalSeconds: 15,
      },
      {
        makeToken: () => "redacted-test-token",
        request: async (token, path) => {
          if (isAppOwnershipRequest(path)) {
            return {data: {attributes: {bundleId: "com.TylerPavay.AscendApp.staging"}}};
          }
          ledgerRequests += 1;
          return {
            data: [
              {attributes: {cfBundleVersion: "2026080299", state: {state: "COMPLETE"}}},
            ],
          };
        },
        sleep: clock.sleep,
        now: clock.now,
        report: () => {},
      },
    ),
    /APP_STORE_CONTRACT_FILTER_IGNORED:.*filter\[cfBundleVersion\]/s,
  );

  assert.equal(ledgerRequests, 1);
  assert.deepEqual(clock.slept, []);
});

test("an upload-ledger response without a data array is a fatal contract break", async () => {
  const clock = testClock();

  await assert.rejects(
    awaitBuildUploadRecorded(
      {
        appId: "6759919365",
        expectedBundleId: "com.TylerPavay.AscendApp.staging",
        buildNumber: "2026080301",
        timeoutSeconds: 900,
        pollIntervalSeconds: 15,
      },
      {
        makeToken: () => "redacted-test-token",
        request: async (token, path) => {
          if (isAppOwnershipRequest(path)) {
            return {data: {attributes: {bundleId: "com.TylerPavay.AscendApp.staging"}}};
          }
          return {data: {attributes: {cfBundleVersion: "2026080301"}}};
        },
        sleep: clock.sleep,
        now: clock.now,
        report: () => {},
      },
    ),
    /APP_STORE_CONTRACT_UNEXPECTED_SHAPE/,
  );

  assert.deepEqual(clock.slept, []);
});

test("an unknown state on the exact upload stops the wait", async () => {
  const clock = testClock();

  await assert.rejects(
    awaitBuildUploadRecorded(
      {
        appId: "6759919365",
        expectedBundleId: "com.TylerPavay.AscendApp.staging",
        buildNumber: "2026080301",
        timeoutSeconds: 900,
        pollIntervalSeconds: 15,
      },
      {
        makeToken: () => "redacted-test-token",
        request: async (token, path) => {
          if (isAppOwnershipRequest(path)) {
            return {data: {attributes: {bundleId: "com.TylerPavay.AscendApp.staging"}}};
          }
          return {
            data: [
              {attributes: {cfBundleVersion: "2026080301", state: {state: "QUARANTINED"}}},
            ],
          };
        },
        sleep: clock.sleep,
        now: clock.now,
        report: () => {},
      },
    ),
    /unknown build upload state 'QUARANTINED'/,
  );

  assert.deepEqual(clock.slept, []);
});

test("a deterministic ledger rejection names the assumption that broke", async () => {
  const clock = testClock();

  await assert.rejects(
    awaitBuildUploadRecorded(
      {
        appId: "6759919365",
        expectedBundleId: "com.TylerPavay.AscendApp.staging",
        buildNumber: "2026080301",
      },
      {
        makeToken: () => "redacted-test-token",
        request: async (token, path) => {
          if (isAppOwnershipRequest(path)) {
            return {data: {attributes: {bundleId: "com.TylerPavay.AscendApp.staging"}}};
          }
          const error = new Error("App Store Connect GET /v1/apps/6759919365/buildUploads failed (400): Parameter error");
          error.status = 400;
          throw error;
        },
        sleep: clock.sleep,
        now: clock.now,
        report: () => {},
      },
    ),
    /APP_STORE_CONTRACT_REJECTED:.*filter\[cfBundleVersion\]/s,
  );

  assert.deepEqual(clock.slept, []);
});

test("the wait refuses an app that does not own the expected bundle", async () => {
  await assert.rejects(
    awaitBuildUploadRecorded(
      {
        appId: "6757202987",
        expectedBundleId: "com.TylerPavay.AscendApp.staging",
        buildNumber: "2026080301",
      },
      {
        makeToken: () => "redacted-test-token",
        request: async () => ({data: {attributes: {bundleId: "com.TylerPavay.AscendApp"}}}),
        report: () => {},
      },
    ),
    /not expected bundle/,
  );
});

// The ownership check is what proves the poll is watching the right app, so an
// error there must stop the deploy rather than be retried as transient.
test("an ownership check failure is fatal rather than retried", async () => {
  const clock = testClock();
  let requests = 0;

  await assert.rejects(
    awaitBuildUploadRecorded(
      {
        appId: "6759919365",
        expectedBundleId: "com.TylerPavay.AscendApp.staging",
        buildNumber: "2026080301",
        timeoutSeconds: 900,
        pollIntervalSeconds: 15,
      },
      {
        makeToken: () => "redacted-test-token",
        request: async () => {
          requests += 1;
          throw new Error("App Store Connect GET /v1/apps/6759919365 failed (401): Unauthorized");
        },
        sleep: clock.sleep,
        now: clock.now,
        report: () => {},
      },
    ),
    /failed \(401\)/,
  );

  assert.equal(requests, 1);
  assert.deepEqual(clock.slept, []);
});

test("the wait refuses a missing or non-numeric build number", async () => {
  for (const buildNumber of ["", "1.2.3", undefined]) {
    await assert.rejects(
      awaitBuildUploadRecorded(
        {
          appId: "6759919365",
          expectedBundleId: "com.TylerPavay.AscendApp.staging",
          buildNumber,
        },
        {
          makeToken: () => assert.fail("must not mint a token for invalid input"),
          request: async () => assert.fail("must not reach App Store Connect"),
          report: () => {},
        },
      ),
      /Build number must be a non-negative integer/,
    );
  }
});

test("pagination cannot send the API token to another origin", async () => {
  let requested = false;

  await assert.rejects(
    appStoreConnectRequest("redacted-test-token", "https://example.com/builds", {
      fetchImplementation: async () => {
        requested = true;
      },
    }),
    /Refusing to send App Store Connect credentials/,
  );
  assert.equal(requested, false);
});
