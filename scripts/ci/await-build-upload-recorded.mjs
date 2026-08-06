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
  isTransientAppStoreConnectFailure,
  makeAppStoreConnectToken,
  readAppStoreConnectCredentials,
  requestUnderContract,
} from "../lib/app-store-connect-client.mjs";

export const DEFAULT_TIMEOUT_SECONDS = 900;
export const DEFAULT_POLL_INTERVAL_SECONDS = 15;

const LEDGER_PAGE_LIMIT = 200;
const LEDGER_CONTRACT =
  "GET /v1/apps/{id}/buildUploads accepts filter[cfBundleVersion], " +
  `fields[buildUploads]=cfBundleVersion,state,uploadedDate and limit=${LEDGER_PAGE_LIMIT}`;

/**
 * Apple reuses a build number after a FAILED upload, so a build number can name
 * several ledger records and the query declares no ordering. Trusting whichever
 * record Apple happens to return first - or trusting that it applied the filter
 * at all - is how this gate would release the concurrency group over a
 * different upload than the one the deploy just made.
 */
function matchingUploads({result, appId, buildNumber}) {
  if (!Array.isArray(result.data)) {
    throw new Error(
      `APP_STORE_CONTRACT_UNEXPECTED_SHAPE: GET /v1/apps/${appId}/buildUploads returned no ` +
        "'data' array. This gate cannot identify the upload without it.",
    );
  }

  const matching = result.data.filter(
    (upload) => String(upload?.attributes?.cfBundleVersion) === String(buildNumber),
  );
  if (matching.length === 0 && result.data.length > 0) {
    throw new Error(
      `APP_STORE_CONTRACT_FILTER_IGNORED: GET /v1/apps/${appId}/buildUploads returned ` +
        `${result.data.length} record(s), none of them build ${buildNumber}. App Store Connect ` +
        "did not honor filter[cfBundleVersion], so no returned record can be trusted to be " +
        "this upload.",
    );
  }

  return matching;
}

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
    `&fields%5BbuildUploads%5D=cfBundleVersion,state,uploadedDate&limit=${LEDGER_PAGE_LIMIT}`;
  const startedAt = now();
  const deadline = startedAt + timeoutSeconds * 1_000;
  const elapsedSeconds = () => Math.round((now() - startedAt) / 1_000);

  let attempt = 0;
  let lastFailure = null;

  for (;;) {
    attempt += 1;
    // A poll that outlives TOKEN_LIFETIME_SECONDS cannot 401 only because every
    // attempt mints its own token; hoisting this single ECDSA signature out of
    // the loop reintroduces that failure exactly when a slow upload appears.
    const token = makeToken();
    let result = null;

    try {
      result = await requestUnderContract(token, query, request, LEDGER_CONTRACT);
      lastFailure = null;
    } catch (error) {
      if (!isTransientAppStoreConnectFailure(error)) throw error;

      lastFailure = error.message;
      report(
        `App Store Connect upload-ledger query failed on attempt ${attempt}: ${error.message}. ` +
          "Retrying while the budget remains.",
      );
    }

    if (result) {
      const matching = matchingUploads({result, appId, buildNumber});

      let sawFailure = false;
      let sawPending = false;
      for (const upload of matching) {
        // Fatal on an unrecognized state: this is the exact upload the deploy
        // just made, so guessing what Apple means by it risks releasing the
        // concurrency group over a binary that never landed.
        const state = buildUploadState(upload);
        if (state === "PROCESSING" || state === "COMPLETE") {
          report(
            `Build upload ${buildNumber} is recorded in App Store Connect as ${state} ` +
              `(attempt ${attempt}).`,
          );
          return {attempt, state};
        }
        if (state === "FAILED") sawFailure = true;
        else sawPending = true;
      }

      if (sawFailure && !sawPending) {
        const summary = matching.map(buildUploadFailureSummary).join(" | ");
        throw new Error(
          `APP_STORE_UPLOAD_FAILED: Build upload ${buildNumber} for App Store Connect app ` +
            `${appId} failed: ${summary}. Apple permits reusing a failed upload's build number.`,
        );
      }

      if (matching.length > 0) {
        report(
          `Build upload ${buildNumber} is not uploaded yet on attempt ${attempt} ` +
            `(${matching.length} matching record(s)); waiting for the file upload.`,
        );
      } else {
        report(`Build upload ${buildNumber} is not in the upload ledger yet (attempt ${attempt}).`);
      }
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
