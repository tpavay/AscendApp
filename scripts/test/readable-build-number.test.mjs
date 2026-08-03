import assert from "node:assert/strict";
import test from "node:test";

import {
  BUILDS_PER_DAY,
  MAX_BUILD_NUMBER,
  PREVIOUS_BUILD_NUMBER_FLOOR,
  deriveReadableBuildNumber,
  fetchHighestUploadedBuildNumber,
  utcDateStamp,
} from "../ci/derive-build-number.mjs";
import {
  appStoreConnectRequest,
  readAppStoreConnectCredentials,
} from "../lib/app-store-connect-client.mjs";

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

  assert.equal(highest, "2026080302");
  assert.equal(requests.length, 3);
  assert.match(requests[1].path, /filter%5Bapp%5D=6759919365/);
  assert.equal(requests[2].path, "https://api.appstoreconnect.apple.com/v1/builds?cursor=next");
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
