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
 * The binary is already accepted by the transporter before any of this runs, so
 * a transient App Store Connect response is not a reason to fail the deploy -
 * only an exhausted budget is. Requests are retried for the remaining budget;
 * credential loading and the app-to-bundle ownership check stay fatal.
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
    appId,
    expectedBundleId,
    buildNumber,
    timeoutSeconds = DEFAULT_TIMEOUT_SECONDS,
    pollIntervalSeconds = DEFAULT_POLL_INTERVAL_SECONDS,
  },
  {
    makeToken = () => makeAppStoreConnectToken(readAppStoreConnectCredentials()),
    request = appStoreConnectRequest,
    sleep = (seconds) => delay(seconds * 1_000),
    report = (message) => console.log(message),
    now = () => Date.now(),
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

  await assertAppOwnsBundleId({token: makeToken(), appId, expectedBundleId}, request);

  const query =
    `/builds?filter%5Bapp%5D=${appId}&filter%5Bversion%5D=${buildNumber}` +
    "&fields%5Bbuilds%5D=version&limit=1";
  const startedAt = now();
  const deadline = startedAt + timeoutSeconds * 1_000;
  const elapsedSeconds = () => Math.round((now() - startedAt) / 1_000);

  let attempt = 0;
  let lastFailure = null;

  for (;;) {
    attempt += 1;

    // A fresh token per attempt: minting is a single ECDSA signature, and it is
    // the only way a poll that outlives TOKEN_LIFETIME_SECONDS cannot 401.
    const token = makeToken();

    try {
      const result = await request(token, query);
      if ((result?.data ?? []).length > 0) {
        report(`Build ${buildNumber} is visible in App Store Connect (attempt ${attempt}).`);
        return attempt;
      }

      lastFailure = null;
      report(`Build ${buildNumber} not listed yet (attempt ${attempt}); retrying.`);
    } catch (error) {
      lastFailure = error.message;
      report(
        `App Store Connect query failed on attempt ${attempt}: ${error.message}. ` +
          "Retrying while the budget remains.",
      );
    }

    const remainingMilliseconds = deadline - now();
    if (remainingMilliseconds <= 0) break;

    await sleep(Math.min(pollIntervalSeconds, remainingMilliseconds / 1_000));
  }

  throw new Error(
    `Build ${buildNumber} for App Store Connect app ${appId} was still not listed in /v1/builds ` +
      `after ${elapsedSeconds()}s across ${attempt} attempts` +
      `${lastFailure ? ` (last error: ${lastFailure})` : ""}. ` +
      "Releasing the deploy concurrency group now would let the next run derive its build number " +
      "from stale remote state and mint a duplicate. Confirm the upload landed in App Store " +
      "Connect before re-running the deploy.",
  );
}

async function main() {
  const [appId, expectedBundleId, buildNumber, ...extra] = process.argv.slice(2);
  if (!appId || !expectedBundleId || !buildNumber || extra.length > 0) {
    throw new Error(
      "Usage: await-build-visible.mjs <app-store-connect-app-id> <bundle-id> <build-number>",
    );
  }

  const credentials = readAppStoreConnectCredentials();
  await awaitBuildVisible(
    {appId, expectedBundleId, buildNumber},
    {makeToken: () => makeAppStoreConnectToken(credentials)},
  );
}

if (isEntrypoint(import.meta.url)) {
  main().catch((error) => {
    console.error(`::error::${error.message}`);
    process.exitCode = 1;
  });
}
