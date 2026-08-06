#!/usr/bin/env node

/**
 * Holds the per-app workflow concurrency group until App Store Connect records
 * the exact Transporter upload as PROCESSING or COMPLETE.
 *
 * `/v1/builds` contains processed binaries only. Apple can accept a binary and
 * create its build upload record long before that later index exposes a Build.
 * The allocator reads both resources, so the upload record is sufficient to
 * reserve the number for the next queued run without blocking on processing.
 *
 * The 900-second budget covers upload-ledger visibility and transient API
 * failures, not build processing. The 20 staging uploads preceding this change
 * took at most 86 seconds from build-upload creation to uploadedDate, and the
 * failure that motivated it had already been recorded before this gate began.
 *
 * Usage:
 *   node scripts/ci/await-build-upload-recorded.mjs <app-id> <bundle-id> <build-number>
 */

import {setTimeout as delay} from "node:timers/promises";

import {
  buildUploadFailureSummary,
  buildUploadState,
} from "../lib/app-store-connect-build-uploads.mjs";
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

export async function awaitBuildUploadRecorded(
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
    `/apps/${appId}/buildUploads?filter%5BcfBundleVersion%5D=${buildNumber}` +
    "&fields%5BbuildUploads%5D=cfBundleVersion,state,uploadedDate&limit=1";
  const startedAt = now();
  const deadline = startedAt + timeoutSeconds * 1_000;
  const elapsedSeconds = () => Math.round((now() - startedAt) / 1_000);

  let attempt = 0;
  let lastFailure = null;

  for (;;) {
    attempt += 1;
    const token = makeToken();
    let result = null;

    try {
      result = await request(token, query);
      lastFailure = null;
    } catch (error) {
      const isTransient =
        error.status === undefined || error.status === 429 || error.status >= 500;
      if (!isTransient) throw error;

      lastFailure = error.message;
      report(
        `App Store Connect upload-ledger query failed on attempt ${attempt}: ${error.message}. ` +
          "Retrying while the budget remains.",
      );
    }

    const upload = result?.data?.[0];
    if (upload) {
      const state = buildUploadState(upload);
      if (state === "PROCESSING" || state === "COMPLETE") {
        report(
          `Build upload ${buildNumber} is recorded in App Store Connect as ${state} ` +
            `(attempt ${attempt}).`,
        );
        return {attempt, state};
      }
      if (state === "FAILED") {
        throw new Error(
          `APP_STORE_UPLOAD_FAILED: Build upload ${buildNumber} for App Store Connect app ` +
            `${appId} failed: ${buildUploadFailureSummary(upload)}. Apple permits reusing a ` +
            "failed upload's build number.",
        );
      }

      report(
        `Build upload ${buildNumber} is ${state} on attempt ${attempt}; waiting for the file upload.`,
      );
    } else if (result) {
      report(`Build upload ${buildNumber} is not in the upload ledger yet (attempt ${attempt}).`);
    }

    const remainingMilliseconds = deadline - now();
    if (remainingMilliseconds <= 0) break;

    await sleep(Math.min(pollIntervalSeconds, remainingMilliseconds / 1_000));
  }

  throw new Error(
    `APP_STORE_UPLOAD_RECORD_TIMEOUT: Build upload ${buildNumber} for App Store Connect app ` +
      `${appId} was not recorded as PROCESSING or COMPLETE after ${elapsedSeconds()}s across ` +
      `${attempt} attempts${lastFailure ? ` (last error: ${lastFailure})` : ""}. ` +
      "The build-number handoff and IPA matched before upload, but the upload ledger never " +
      "confirmed Apple's receipt. This is not a missing or guessed build number.",
  );
}

async function main() {
  const [appId, expectedBundleId, buildNumber, ...extra] = process.argv.slice(2);
  if (!appId || !expectedBundleId || !buildNumber || extra.length > 0) {
    throw new Error(
      "Usage: await-build-upload-recorded.mjs <app-store-connect-app-id> <bundle-id> <build-number>",
    );
  }

  const credentials = readAppStoreConnectCredentials();
  await awaitBuildUploadRecorded(
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
