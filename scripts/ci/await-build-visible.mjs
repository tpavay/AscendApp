#!/usr/bin/env node

/**
 * Blocks the upload job until the build it just uploaded is queryable through
 * `/v1/builds`.
 *
 * The build-number allocator's only sequence state is App Store Connect's build
 * list. `upload_to_testflight` keeps `skip_waiting_for_build_processing: true`,
 * so the lane returns as soon as the transporter accepts the binary - minutes
 * before the Build record exists. Workflow concurrency serializes runs, not
 * Apple's ingestion, so the next queued run would derive against the pre-upload
 * maximum and mint the same YYYYMMDDNN value. Holding the concurrency group
 * until the record appears is what makes the serialization claim true.
 *
 * This deliberately waits for *visibility*, not for processing to finish: the
 * allocator only needs the version to be listed.
 *
 * Usage:
 *   node scripts/ci/await-build-visible.mjs <app-id> <bundle-id> <build-number>
 */

import {setTimeout as delay} from "node:timers/promises";

import {isEntrypoint} from "../lib/is-entrypoint.mjs";
import {
  BUILD_NUMBER_PATTERN,
  appStoreConnectRequest,
  assertAppOwnsBundleId,
  makeAppStoreConnectToken,
  readAppStoreConnectCredentials,
} from "../lib/app-store-connect-client.mjs";

export const DEFAULT_TIMEOUT_SECONDS = 900;
export const DEFAULT_POLL_INTERVAL_SECONDS = 15;

export async function awaitBuildVisible(
  {
    token,
    appId,
    expectedBundleId,
    buildNumber,
    timeoutSeconds = DEFAULT_TIMEOUT_SECONDS,
    pollIntervalSeconds = DEFAULT_POLL_INTERVAL_SECONDS,
  },
  {
    request = appStoreConnectRequest,
    sleep = (seconds) => delay(seconds * 1_000),
    report = (message) => console.log(message),
  } = {},
) {
  if (!BUILD_NUMBER_PATTERN.test(String(buildNumber))) {
    throw new Error(`Build number must be a non-negative integer, got '${buildNumber}'.`);
  }
  if (!(timeoutSeconds > 0) || !(pollIntervalSeconds > 0)) {
    throw new Error(
      `Timeout and poll interval must both be positive, got ${timeoutSeconds}s / ${pollIntervalSeconds}s.`,
    );
  }

  await assertAppOwnsBundleId({token, appId, expectedBundleId}, request);

  const attempts = Math.max(1, Math.ceil(timeoutSeconds / pollIntervalSeconds));
  const query =
    `/builds?filter%5Bapp%5D=${appId}&filter%5Bversion%5D=${buildNumber}` +
    "&fields%5Bbuilds%5D=version&limit=1";

  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    const result = await request(token, query);
    if ((result?.data ?? []).length > 0) {
      report(`Build ${buildNumber} is visible in App Store Connect (attempt ${attempt}).`);
      return attempt;
    }

    if (attempt < attempts) {
      report(`Build ${buildNumber} not listed yet (attempt ${attempt} of ${attempts}); retrying.`);
      await sleep(pollIntervalSeconds);
    }
  }

  throw new Error(
    `Build ${buildNumber} for App Store Connect app ${appId} was still not listed in /v1/builds ` +
      `after ${timeoutSeconds}s. Releasing the deploy concurrency group now would let the next run ` +
      "derive its build number from stale remote state and mint a duplicate. Confirm the upload " +
      "landed in App Store Connect before re-running the deploy.",
  );
}

async function main() {
  const [appId, expectedBundleId, buildNumber, ...extra] = process.argv.slice(2);
  if (!appId || !expectedBundleId || !buildNumber || extra.length > 0) {
    throw new Error(
      "Usage: await-build-visible.mjs <app-store-connect-app-id> <bundle-id> <build-number>",
    );
  }

  const token = makeAppStoreConnectToken(readAppStoreConnectCredentials());
  await awaitBuildVisible({token, appId, expectedBundleId, buildNumber});
}

if (isEntrypoint(import.meta.url)) {
  main().catch((error) => {
    console.error(`::error::${error.message}`);
    process.exitCode = 1;
  });
}
