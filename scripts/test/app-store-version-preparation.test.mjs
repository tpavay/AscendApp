import assert from "node:assert/strict";
import test from "node:test";

import {
  localesMissingReleaseNotes,
  manualNextSteps,
  parseMarketingVersion,
  selectAttachableBuild,
  selectPreparableVersionRecord,
  versionState,
} from "../lib/app-store-version-preparation.mjs";
import {parseArguments, prepareAppStoreVersion} from "../appstore-prepare-version.mjs";

function projectFile(...versions) {
  return versions
    .map((version) => `\t\t\t\tMARKETING_VERSION = ${version};\n\t\t\t\tPRODUCT_NAME = Ascend;\n`)
    .join("");
}

function buildRecord({id = "b1", version, processingState = "VALID", expired = false, train}) {
  return {
    build: {id, attributes: {version, processingState, expired}},
    trainVersion: train,
  };
}

test("the marketing version is read only when every target agrees", () => {
  assert.equal(parseMarketingVersion(projectFile("1.0.1", "1.0.1", "1.0.1")), "1.0.1");

  assert.throws(
    () => parseMarketingVersion(projectFile("1.0.1", "1.1")),
    /2 different MARKETING_VERSION values \(1\.0\.1, 1\.1\)/,
  );
  assert.throws(() => parseMarketingVersion("PRODUCT_NAME = Ascend;"), /No MARKETING_VERSION/);
  assert.throws(() => parseMarketingVersion(projectFile("1.0.1-beta")), /one to three numeric/);
});

test("a version state is read under both the current and the deprecated attribute name", () => {
  assert.equal(versionState({attributes: {appVersionState: "PREPARE_FOR_SUBMISSION"}}), "PREPARE_FOR_SUBMISSION");
  assert.equal(versionState({attributes: {appStoreState: "READY_FOR_SALE"}}), "READY_FOR_SALE");
  assert.equal(versionState({attributes: {}}), null);
});

test("a version that is past editing is refused rather than written to", () => {
  const live = {id: "v1", attributes: {versionString: "1.0", appStoreState: "READY_FOR_SALE"}};
  const editable = {
    id: "v2",
    attributes: {versionString: "1.0.1", appStoreState: "PREPARE_FOR_SUBMISSION"},
  };

  assert.equal(selectPreparableVersionRecord([live, editable], "1.0.1"), editable);
  assert.equal(selectPreparableVersionRecord([live], "1.0.1"), null);

  assert.throws(
    () => selectPreparableVersionRecord([live], "1.0"),
    /is READY_FOR_SALE, which this script may not write to/,
  );
  assert.throws(
    () => selectPreparableVersionRecord(
      [{id: "v3", attributes: {versionString: "1.0.1", appVersionState: "IN_REVIEW"}}],
      "1.0.1",
    ),
    /is IN_REVIEW, which this script may not write to/,
  );
  assert.throws(
    () => selectPreparableVersionRecord([editable, {...editable, id: "v4"}], "1.0.1"),
    /2 App Store version records share version string 1\.0\.1/,
  );
});

test("a rejected version is still preparable, because that is what a resubmission needs", () => {
  for (const state of ["DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"]) {
    const record = {id: "v1", attributes: {versionString: "1.0.1", appVersionState: state}};
    assert.equal(selectPreparableVersionRecord([record], "1.0.1"), record, state);
  }
});

test("the newest processed build in the train is attached, and nothing else is", () => {
  const records = [
    buildRecord({id: "old", version: "2026082801", train: "1.0.1"}),
    buildRecord({id: "new", version: "2026082803", train: "1.0.1"}),
    buildRecord({id: "processing", version: "2026082804", processingState: "PROCESSING", train: "1.0.1"}),
    buildRecord({id: "expired", version: "2026082805", expired: true, train: "1.0.1"}),
  ];

  assert.equal(selectAttachableBuild(records, {versionString: "1.0.1"}).build.id, "new");
});

test("build numbers order numerically, not lexicographically", () => {
  const records = [
    buildRecord({id: "nine", version: "9", train: "1.0.1"}),
    buildRecord({id: "ten", version: "10", train: "1.0.1"}),
  ];

  assert.equal(selectAttachableBuild(records, {versionString: "1.0.1"}).build.id, "ten");
});

test("no processed build yet is a wait, not a failure", () => {
  const records = [
    buildRecord({id: "processing", version: "2026082801", processingState: "PROCESSING", train: "1.0.1"}),
  ];

  assert.equal(selectAttachableBuild(records, {versionString: "1.0.1"}), null);
  assert.equal(selectAttachableBuild([], {versionString: "1.0.1"}), null);
});

test("a train filter App Store Connect ignored is refused, never fallen back on", () => {
  const records = [buildRecord({id: "other", version: "2026082801", train: "1.0"})];

  assert.throws(
    () => selectAttachableBuild(records, {versionString: "1.0.1"}),
    /APP_STORE_CONTRACT_FILTER_IGNORED/,
  );
});

test("an explicitly requested build must exist in the train and be processed", () => {
  const records = [
    buildRecord({id: "valid", version: "2026082801", train: "1.0.1"}),
    buildRecord({id: "processing", version: "2026082802", processingState: "PROCESSING", train: "1.0.1"}),
    buildRecord({id: "expired", version: "2026082803", expired: true, train: "1.0.1"}),
  ];

  assert.equal(
    selectAttachableBuild(records, {versionString: "1.0.1", requestedBuildNumber: "2026082801"}).build.id,
    "valid",
  );
  assert.throws(
    () => selectAttachableBuild(records, {versionString: "1.0.1", requestedBuildNumber: "2026082802"}),
    /is PROCESSING, not VALID/,
  );
  assert.throws(
    () => selectAttachableBuild(records, {versionString: "1.0.1", requestedBuildNumber: "2026082803"}),
    /has expired/,
  );
  assert.throws(
    () => selectAttachableBuild(records, {versionString: "1.0.1", requestedBuildNumber: "2026082899"}),
    /No build 2026082899 in train 1\.0\.1/,
  );
});

test("empty release notes are reported per locale", () => {
  const localizations = [
    {attributes: {locale: "en-US", whatsNew: "   "}},
    {attributes: {locale: "de-DE", whatsNew: "Neu"}},
    {attributes: {locale: "fr-FR"}},
  ];

  assert.deepEqual(localesMissingReleaseNotes(localizations), ["en-US", "fr-FR"]);
  assert.deepEqual(localesMissingReleaseNotes([]), []);
});

test("the manual step list always ends at Submit, and never claims to have pressed it", () => {
  const steps = manualNextSteps({
    appId: "6757202987",
    versionString: "1.0.1",
    buildNumber: "2026082801",
    missingReleaseNotes: ["en-US"],
  });

  assert.match(steps.join("\n"), /What's New/);
  assert.ok(
    steps.some((step) => /Press Submit for Review yourself/.test(step)),
    "the human has to be told they press Submit",
  );
  assert.ok(
    steps.every((step) => !/submitted for review/i.test(step)),
    "nothing may claim the version was submitted",
  );
});

test("arguments parse into the shape the run uses, and refuse nonsense", () => {
  const options = parseArguments([
    "--confirm",
    "--app-id",
    "6757202987",
    "--version",
    "1.0.1",
    "--build",
    "2026082801",
    "--poll-seconds",
    "5",
  ]);

  assert.equal(options.confirmed, true);
  assert.equal(options.appId, "6757202987");
  assert.equal(options.versionString, "1.0.1");
  assert.equal(options.buildNumber, "2026082801");
  assert.equal(options.pollIntervalSeconds, 5);
  assert.equal(options.bundleId, "com.TylerPavay.AscendApp");

  assert.equal(parseArguments([]).confirmed, false, "a run without --confirm writes nothing");
  assert.throws(() => parseArguments(["--submit-for-review"]), /Unknown argument/);
  assert.throws(() => parseArguments(["--version"]), /needs a value/);
  assert.throws(() => parseArguments(["--build", "abc"]), /non-negative integer/);
  assert.throws(() => parseArguments(["--timeout-seconds", "0"]), /positive number of seconds/);
});

/**
 * A fake App Store Connect that answers the five reads and two writes this script makes, and
 * records every request so a test can prove which ones were sent - above all, that no
 * submission endpoint was ever touched.
 */
function fakeAppStoreConnect({versions = [], builds = [], localizations = []} = {}) {
  const calls = [];
  const state = {versions: [...versions], attachedBuildByVersion: new Map()};

  async function request(token, pathOrURL, {method = "GET", body} = {}) {
    calls.push({method, path: pathOrURL, body});

    if (pathOrURL.startsWith("/apps?filter")) {
      return {data: [{id: "6757202987", attributes: {bundleId: "com.TylerPavay.AscendApp"}}]};
    }
    if (/^\/apps\/[^/]+\/appStoreVersions/.test(pathOrURL)) {
      return {data: state.versions};
    }
    if (/^\/apps\/\d+\?/.test(pathOrURL)) {
      return {data: {id: "6757202987", attributes: {bundleId: "com.TylerPavay.AscendApp"}}};
    }
    if (pathOrURL.startsWith("/builds?")) {
      return {
        data: builds.map((record) => ({
          ...record.build,
          relationships: {preReleaseVersion: {data: {id: `train-${record.trainVersion}`}}},
        })),
        included: [...new Set(builds.map((record) => record.trainVersion))].map((train) => ({
          type: "preReleaseVersions",
          id: `train-${train}`,
          attributes: {version: train},
        })),
      };
    }
    if (pathOrURL === "/appStoreVersions" && method === "POST") {
      const created = {
        id: "created-version",
        attributes: {
          versionString: body.data.attributes.versionString,
          appVersionState: "PREPARE_FOR_SUBMISSION",
        },
      };
      state.versions.push(created);
      return {data: created};
    }
    if (/relationships\/build$/.test(pathOrURL)) {
      const versionId = pathOrURL.split("/")[2];
      if (method === "PATCH") {
        state.attachedBuildByVersion.set(versionId, body.data.id);
        return null;
      }
      return {data: state.attachedBuildByVersion.has(versionId)
        ? {type: "builds", id: state.attachedBuildByVersion.get(versionId)}
        : null};
    }
    if (/appStoreVersionLocalizations/.test(pathOrURL)) {
      return {data: localizations};
    }

    throw new Error(`Unexpected App Store Connect request: ${method} ${pathOrURL}`);
  }

  return {request, calls, state};
}

const RUN_HARNESS_DEFAULTS = {
  makeToken: () => "token",
  sleep: async () => {},
  report: () => {},
  now: () => 0,
};

test("a confirmed run creates the version, attaches the build, and submits nothing", async () => {
  const connect = fakeAppStoreConnect({
    builds: [buildRecord({id: "build-1", version: "2026082801", train: "1.0.1"})],
    localizations: [{attributes: {locale: "en-US", whatsNew: ""}}],
  });

  const result = await prepareAppStoreVersion(
    {...parseArguments(["--confirm", "--version", "1.0.1"]), appId: "6757202987"},
    {...RUN_HARNESS_DEFAULTS, request: connect.request},
  );

  assert.deepEqual(result, {
    appId: "6757202987",
    versionString: "1.0.1",
    buildNumber: "2026082801",
    written: true,
    missingReleaseNotes: ["en-US"],
  });

  const created = connect.calls.find((call) => call.path === "/appStoreVersions");
  assert.equal(created.method, "POST");
  assert.equal(created.body.data.attributes.versionString, "1.0.1");
  assert.equal(
    created.body.data.attributes.releaseType,
    "MANUAL",
    "an approved release must still wait for a human",
  );

  assert.equal(connect.state.attachedBuildByVersion.get("created-version"), "build-1");

  for (const call of connect.calls) {
    assert.doesNotMatch(
      call.path,
      /reviewSubmission|appStoreVersionSubmission|VersionExperiment|phasedRelease/i,
      `the run must never call ${call.path}`,
    );
  }
});

test("a run without --confirm reports the plan and writes nothing", async () => {
  const connect = fakeAppStoreConnect({
    builds: [buildRecord({id: "build-1", version: "2026082801", train: "1.0.1"})],
  });

  const result = await prepareAppStoreVersion(
    {...parseArguments(["--version", "1.0.1"]), appId: "6757202987"},
    {...RUN_HARNESS_DEFAULTS, request: connect.request},
  );

  assert.equal(result.written, false);
  assert.ok(
    connect.calls.every((call) => call.method === "GET"),
    `a dry run may only read, sent: ${connect.calls.map((call) => `${call.method} ${call.path}`)}`,
  );
});

test("an existing version record is reused rather than duplicated", async () => {
  const existing = {
    id: "existing-version",
    attributes: {versionString: "1.0.1", appVersionState: "PREPARE_FOR_SUBMISSION"},
  };
  const connect = fakeAppStoreConnect({
    versions: [existing],
    builds: [buildRecord({id: "build-1", version: "2026082801", train: "1.0.1"})],
  });

  await prepareAppStoreVersion(
    {...parseArguments(["--confirm", "--version", "1.0.1"]), appId: "6757202987"},
    {...RUN_HARNESS_DEFAULTS, request: connect.request},
  );

  assert.equal(
    connect.calls.filter((call) => call.method === "POST").length,
    0,
    "an existing version must not be created a second time",
  );
  assert.equal(connect.state.attachedBuildByVersion.get("existing-version"), "build-1");
});

test("a version already in review stops the run before it waits on a build", async () => {
  const connect = fakeAppStoreConnect({
    versions: [{id: "v", attributes: {versionString: "1.0.1", appVersionState: "WAITING_FOR_REVIEW"}}],
    builds: [buildRecord({id: "build-1", version: "2026082801", train: "1.0.1"})],
  });

  await assert.rejects(
    prepareAppStoreVersion(
      {...parseArguments(["--confirm", "--version", "1.0.1"]), appId: "6757202987"},
      {...RUN_HARNESS_DEFAULTS, request: connect.request},
    ),
    /is WAITING_FOR_REVIEW, which this script may not write to/,
  );

  assert.ok(
    connect.calls.every((call) => !call.path.startsWith("/builds?")),
    "the build listing must not be polled for a version that cannot take a build",
  );
});

test("a build that never finishes processing times out instead of waiting forever", async () => {
  const connect = fakeAppStoreConnect({
    builds: [
      buildRecord({id: "build-1", version: "2026082801", processingState: "PROCESSING", train: "1.0.1"}),
    ],
  });

  let clock = 0;
  await assert.rejects(
    prepareAppStoreVersion(
      {...parseArguments(["--confirm", "--version", "1.0.1", "--timeout-seconds", "120"]), appId: "6757202987"},
      {
        ...RUN_HARNESS_DEFAULTS,
        request: connect.request,
        now: () => clock,
        sleep: async (seconds) => {
          clock += seconds * 1_000;
        },
      },
    ),
    /APP_STORE_BUILD_PROCESSING_TIMEOUT/,
  );
});

test("a transient failure is retried while a refusal Apple understood is not", async () => {
  const transient = Object.assign(new Error("rate limited"), {status: 429});
  const deterministic = Object.assign(new Error("bad filter"), {status: 400});

  for (const [error, expected] of [[transient, /TIMEOUT/], [deterministic, /bad filter/]]) {
    let clock = 0;
    let buildListings = 0;

    await assert.rejects(
      prepareAppStoreVersion(
        {...parseArguments(["--confirm", "--version", "1.0.1", "--timeout-seconds", "120"]), appId: "6757202987"},
        {
          ...RUN_HARNESS_DEFAULTS,
          now: () => clock,
          sleep: async (seconds) => {
            clock += seconds * 1_000;
          },
          request: async (token, path) => {
            if (/^\/apps\/\d+\?/.test(path)) {
              return {data: {id: "6757202987", attributes: {bundleId: "com.TylerPavay.AscendApp"}}};
            }
            if (/appStoreVersions/.test(path)) return {data: []};
            if (path.startsWith("/builds?")) {
              buildListings += 1;
              throw error;
            }
            throw new Error(`Unexpected request: ${path}`);
          },
        },
      ),
      expected,
    );

    if (error === deterministic) {
      assert.equal(buildListings, 1, "a deterministic refusal must not be retried");
    } else {
      assert.ok(buildListings > 1, "a transient failure must be retried inside the budget");
    }
  }
});
