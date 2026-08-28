#!/usr/bin/env node

/**
 * Prepares the next App Store version record for Ascend and attaches the uploaded build,
 * then STOPS.
 *
 * ============================================================================
 * THIS SCRIPT DOES NOT SUBMIT FOR REVIEW, AND MUST NEVER BE MADE TO.
 *
 * The captain reads the prepared version in App Store Connect and presses Submit himself.
 * That is a deliberate boundary, not an unfinished feature: nothing in this repository may
 * POST to `/v1/reviewSubmissions` or `/v1/appStoreVersionSubmissions`, call fastlane's
 * `deliver` / `upload_to_app_store` / `submit_for_review`, or otherwise put a build in
 * front of App Review without a human pressing the button.
 * `scripts/test/app-store-submission-guard.test.mjs` fails the build if that changes.
 * ============================================================================
 *
 * What it does, in order:
 *   1. Resolves the marketing version from the Xcode project (or `--version`).
 *   2. Reads the existing version record and refuses early if it is past editing.
 *   3. Waits, on a bounded budget, for Apple to finish processing the build.
 *   4. Creates the version record when it does not exist yet - `releaseType: MANUAL`, so
 *      even an approved release waits for a human.
 *   5. Attaches the build.
 *   6. Reports what a human still has to do.
 *
 * Metadata is deliberately NOT written. The repository's App Store copy under
 * `data/ascend-support-page-and-product-page-package/` records the listing that is already
 * live; it is a transcript, not a source of truth, so pushing it would overwrite the
 * captain's listing from a stale document. Release notes are reported as missing instead.
 *
 * Usage:
 *   node scripts/appstore-prepare-version.mjs --confirm
 *   node scripts/appstore-prepare-version.mjs            # dry run: reports, writes nothing
 *   node scripts/appstore-prepare-version.mjs --confirm --version 1.0.1 --build 2026082801
 *
 * Credentials come from the same environment variables the TestFlight upload lane uses:
 *   APP_STORE_CONNECT_API_KEY_ID, APP_STORE_CONNECT_API_ISSUER_ID,
 *   APP_STORE_CONNECT_API_KEY (base64-encoded .p8)
 */

import {readFile} from "node:fs/promises";
import {setTimeout as delay} from "node:timers/promises";

import {isEntrypoint} from "./lib/is-entrypoint.mjs";
import {
  appStoreConnectRequest,
  assertAppOwnsBundleId,
  isTransientAppStoreConnectFailure,
  makeAppStoreConnectToken,
  readAppStoreConnectCredentials,
  requestUnderContract,
} from "./lib/app-store-connect-client.mjs";
import {
  assertVersionString,
  localesMissingReleaseNotes,
  manualNextSteps,
  parseMarketingVersion,
  selectAttachableBuild,
  selectPreparableVersionRecord,
  versionState,
} from "./lib/app-store-version-preparation.mjs";

export const DEFAULT_BUNDLE_ID = "com.TylerPavay.AscendApp";
export const DEFAULT_TIMEOUT_SECONDS = 2_400;
export const DEFAULT_POLL_INTERVAL_SECONDS = 60;

const PROJECT_FILE = "AscendApp.xcodeproj/project.pbxproj";
const PAGE_LIMIT = 200;
const MAX_PAGES = 20;

const APP_LOOKUP_CONTRACT = "GET /v1/apps accepts filter[bundleId] and limit";
const VERSION_LISTING_CONTRACT =
  "GET /v1/apps/{id}/appStoreVersions accepts filter[platform]=IOS and limit";
const BUILD_LISTING_CONTRACT =
  "GET /v1/builds accepts filter[app], filter[preReleaseVersion.version], " +
  "include=preReleaseVersion, fields[builds] and fields[preReleaseVersions]";
const ATTACHED_BUILD_CONTRACT =
  "GET /v1/appStoreVersions/{id}/relationships/build returns the attached build's identifier";
const LOCALIZATION_CONTRACT =
  "GET /v1/appStoreVersions/{id}/appStoreVersionLocalizations accepts " +
  "fields[appStoreVersionLocalizations]=locale,whatsNew";

export function parseArguments(argv) {
  const options = {
    appId: null,
    bundleId: DEFAULT_BUNDLE_ID,
    versionString: null,
    buildNumber: null,
    timeoutSeconds: DEFAULT_TIMEOUT_SECONDS,
    pollIntervalSeconds: DEFAULT_POLL_INTERVAL_SECONDS,
    confirmed: false,
  };

  const valueFlags = new Map([
    ["--app-id", "appId"],
    ["--bundle-id", "bundleId"],
    ["--version", "versionString"],
    ["--build", "buildNumber"],
    ["--timeout-seconds", "timeoutSeconds"],
    ["--poll-seconds", "pollIntervalSeconds"],
  ]);
  const numericFields = new Set(["timeoutSeconds", "pollIntervalSeconds"]);

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];

    if (argument === "--confirm") {
      options.confirmed = true;
      continue;
    }

    const field = valueFlags.get(argument);
    if (!field) {
      throw new Error(
        `Unknown argument '${argument}'. Usage: appstore-prepare-version.mjs [--confirm] ` +
          "[--app-id <id>] [--bundle-id <id>] [--version <versionString>] [--build <number>] " +
          "[--timeout-seconds <n>] [--poll-seconds <n>]",
      );
    }

    const value = argv[index + 1];
    if (value === undefined || value.startsWith("--")) {
      throw new Error(`\`${argument}\` needs a value.`);
    }
    index += 1;

    if (numericFields.has(field)) {
      const parsed = Number(value);
      if (!Number.isFinite(parsed) || parsed <= 0) {
        throw new Error(`\`${argument}\` must be a positive number of seconds, got '${value}'.`);
      }
      options[field] = parsed;
      continue;
    }

    options[field] = value;
  }

  if (options.buildNumber !== null && !/^\d+$/.test(options.buildNumber)) {
    throw new Error(`\`--build\` must be a non-negative integer, got '${options.buildNumber}'.`);
  }
  if (options.versionString !== null) assertVersionString(options.versionString);

  return options;
}

async function resolveMarketingVersion(versionString) {
  if (versionString) return assertVersionString(versionString);

  const projectURL = new URL(`../${PROJECT_FILE}`, import.meta.url);
  return parseMarketingVersion(await readFile(projectURL, "utf8"));
}

async function resolveAppId({token, appId, bundleId}, request) {
  if (appId) {
    await assertAppOwnsBundleId({token, appId, expectedBundleId: bundleId}, request);
    return appId;
  }

  const result = await requestUnderContract(
    token,
    `/apps?filter%5BbundleId%5D=${encodeURIComponent(bundleId)}&limit=2`,
    request,
    APP_LOOKUP_CONTRACT,
  );
  const apps = result?.data ?? [];
  const matching = apps.filter((app) => app?.attributes?.bundleId === bundleId);

  if (matching.length !== 1) {
    throw new Error(
      `Expected exactly one App Store Connect app for bundle id ${bundleId}, found ` +
        `${matching.length}. Pass --app-id to name it explicitly.`,
    );
  }

  return matching[0].id;
}

async function fetchVersionRecords({token, appId}, request) {
  const records = [];
  let next = `/apps/${appId}/appStoreVersions?filter%5Bplatform%5D=IOS&limit=${PAGE_LIMIT}`;

  for (let page = 0; next && page < MAX_PAGES; page += 1) {
    const result = await requestUnderContract(token, next, request, VERSION_LISTING_CONTRACT);
    if (!Array.isArray(result?.data)) {
      throw new Error(
        "APP_STORE_CONTRACT_UNEXPECTED_SHAPE: The App Store Connect version listing for app " +
          `${appId} returned no 'data' array. Refusing to decide against an unread listing.`,
      );
    }
    records.push(...result.data);
    next = result?.links?.next ?? null;
  }

  if (next) throw new Error(`App Store Connect version listing exceeded ${MAX_PAGES} pages.`);

  return records;
}

/**
 * Every build in this marketing version's train, each paired with the train it actually
 * reports, so `selectAttachableBuild` can tell a filtered listing from an unfiltered one.
 */
async function fetchBuildRecords({token, appId, versionString}, request) {
  const records = [];
  let next =
    `/builds?filter%5Bapp%5D=${appId}` +
    `&filter%5BpreReleaseVersion.version%5D=${encodeURIComponent(versionString)}` +
    "&include=preReleaseVersion" +
    "&fields%5Bbuilds%5D=version,processingState,expired,uploadedDate" +
    "&fields%5BpreReleaseVersions%5D=version" +
    `&limit=${PAGE_LIMIT}`;

  for (let page = 0; next && page < MAX_PAGES; page += 1) {
    const result = await requestUnderContract(token, next, request, BUILD_LISTING_CONTRACT);
    if (!Array.isArray(result?.data)) {
      throw new Error(
        "APP_STORE_CONTRACT_UNEXPECTED_SHAPE: The App Store Connect build listing for app " +
          `${appId} returned no 'data' array. Refusing to attach against an unread listing.`,
      );
    }

    for (const build of result.data) {
      const trainId = build?.relationships?.preReleaseVersion?.data?.id;
      const train = (result.included ?? []).find(
        (entry) => entry.type === "preReleaseVersions" && entry.id === trainId,
      );
      records.push({build, trainVersion: train?.attributes?.version ?? null});
    }

    next = result?.links?.next ?? null;
  }

  if (next) throw new Error(`App Store Connect build listing exceeded ${MAX_PAGES} pages.`);

  return records;
}

/**
 * Waits for a build in this train to finish processing.
 *
 * The wait exists because `upload_testflight` runs with
 * `skip_waiting_for_build_processing: true` - the deploy hands off an uploaded binary, not a
 * processed one, and Apple attaches only a processed build. A transient API failure is
 * retried inside the budget; a deterministic refusal is not, because retrying it changes
 * nothing.
 */
export async function awaitAttachableBuild(
  {appId, versionString, requestedBuildNumber, timeoutSeconds, pollIntervalSeconds},
  {
    makeToken,
    request = appStoreConnectRequest,
    sleep = (seconds) => delay(seconds * 1_000),
    report = (message) => console.log(message),
    now = () => Date.now(),
  },
) {
  const startedAt = now();
  const deadline = startedAt + timeoutSeconds * 1_000;
  let attempt = 0;
  let lastFailure = null;

  for (;;) {
    attempt += 1;
    // Every attempt mints its own token: a wait that outlives the 15-minute token lifetime
    // must not start failing on authentication exactly when processing is slowest.
    const token = makeToken();

    try {
      const records = await fetchBuildRecords({token, appId, versionString}, request);
      const selected = selectAttachableBuild(records, {versionString, requestedBuildNumber});
      if (selected) {
        report(
          `Build ${selected.build.attributes.version} in train ${versionString} has finished ` +
            `processing (attempt ${attempt}).`,
        );
        return selected;
      }

      lastFailure = null;
      report(
        `No processed build in train ${versionString} yet on attempt ${attempt} ` +
          `(${records.length} build record(s) in the train). Waiting for Apple to finish ` +
          "processing.",
      );
    } catch (error) {
      // A refusal Apple understood - an unknown build number, an expired binary, a rejected
      // filter - says the same thing every minute for the next forty. Only a rate limit or
      // an outage earns a retry.
      if (!isTransientAppStoreConnectFailure(error)) throw error;

      lastFailure = error.message;
      report(
        `App Store Connect build listing failed on attempt ${attempt}: ${error.message}. ` +
          "Retrying while the budget remains.",
      );
    }

    const remainingMilliseconds = deadline - now();
    if (remainingMilliseconds <= 0) break;

    await sleep(Math.min(pollIntervalSeconds, remainingMilliseconds / 1_000));
  }

  const elapsedSeconds = Math.round((now() - startedAt) / 1_000);
  throw new Error(
    `APP_STORE_BUILD_PROCESSING_TIMEOUT: No build in train ${versionString} for app ${appId} ` +
      `reached VALID after ${elapsedSeconds}s across ${attempt} attempts` +
      `${lastFailure ? ` (last error: ${lastFailure})` : ""}. ` +
      "The upload succeeded; Apple has not finished processing it. Re-run this workflow, or " +
      "attach the build by hand once App Store Connect shows it as ready.",
  );
}

async function createVersionRecord({token, appId, versionString}, request) {
  const result = await request(token, "/appStoreVersions", {
    method: "POST",
    body: {
      data: {
        type: "appStoreVersions",
        attributes: {
          platform: "IOS",
          versionString,
          // MANUAL, never AFTER_APPROVAL: an approved release still waits for a human to
          // release it. Nothing in this pipeline puts a build in front of users on its own.
          releaseType: "MANUAL",
        },
        relationships: {app: {data: {type: "apps", id: appId}}},
      },
    },
  });

  const record = result?.data;
  if (!record?.id) {
    throw new Error(
      `APP_STORE_CONTRACT_UNEXPECTED_SHAPE: Creating version ${versionString} returned no ` +
        "record identifier, so there is nothing to attach a build to.",
    );
  }

  return record;
}

async function attachedBuildId({token, versionId}, request) {
  const result = await requestUnderContract(
    token,
    `/appStoreVersions/${versionId}/relationships/build`,
    request,
    ATTACHED_BUILD_CONTRACT,
  );
  return result?.data?.id ?? null;
}

async function attachBuild({token, versionId, buildId}, request) {
  await request(token, `/appStoreVersions/${versionId}/relationships/build`, {
    method: "PATCH",
    body: {data: {type: "builds", id: buildId}},
  });
}

async function fetchLocalizations({token, versionId}, request) {
  const result = await requestUnderContract(
    token,
    `/appStoreVersions/${versionId}/appStoreVersionLocalizations` +
      `?fields%5BappStoreVersionLocalizations%5D=locale,whatsNew&limit=${PAGE_LIMIT}`,
    request,
    LOCALIZATION_CONTRACT,
  );
  return result?.data ?? [];
}

export async function prepareAppStoreVersion(
  options,
  {
    makeToken,
    request = appStoreConnectRequest,
    sleep = (seconds) => delay(seconds * 1_000),
    report = (message) => console.log(message),
    now = () => Date.now(),
  } = {},
) {
  const versionString = await resolveMarketingVersion(options.versionString);
  const token = makeToken();
  const appId = await resolveAppId(
    {token, appId: options.appId, bundleId: options.bundleId},
    request,
  );

  report(`App Store Connect app ${appId} (${options.bundleId}), marketing version ${versionString}.`);

  // Read the version record before waiting on a build. A version already in review, awaiting
  // release, or released cannot take this build, and finding that out after forty minutes of
  // polling helps nobody.
  const existingRecords = await fetchVersionRecords({token, appId}, request);
  const existing = selectPreparableVersionRecord(existingRecords, versionString);
  report(
    existing
      ? `Version ${versionString} already exists as ${versionState(existing)}; reusing it.`
      : `Version ${versionString} does not exist yet; it will be created.`,
  );

  const selectedBuild = await awaitAttachableBuild(
    {
      appId,
      versionString,
      requestedBuildNumber: options.buildNumber,
      timeoutSeconds: options.timeoutSeconds,
      pollIntervalSeconds: options.pollIntervalSeconds,
    },
    {makeToken, request, sleep, report, now},
  );
  const buildNumber = selectedBuild.build.attributes.version;

  if (!options.confirmed) {
    report(
      `\nDry run. Re-run with --confirm to ${existing ? "attach" : "create version " + versionString + " and attach"} ` +
        `build ${buildNumber}.`,
    );
    return {appId, versionString, buildNumber, written: false};
  }

  // Every token minted at the start of a run that may have waited forty minutes has expired
  // by now; the write path mints its own.
  const writeToken = makeToken();
  const versionRecord =
    existing ?? (await createVersionRecord({token: writeToken, appId, versionString}, request));
  if (!existing) report(`Created App Store version ${versionString} with releaseType MANUAL.`);

  const alreadyAttached = await attachedBuildId(
    {token: writeToken, versionId: versionRecord.id},
    request,
  );
  if (alreadyAttached === selectedBuild.build.id) {
    report(`Build ${buildNumber} is already attached to version ${versionString}.`);
  } else {
    await attachBuild(
      {token: writeToken, versionId: versionRecord.id, buildId: selectedBuild.build.id},
      request,
    );
    report(`Attached build ${buildNumber} to App Store version ${versionString}.`);
  }

  const missingReleaseNotes = localesMissingReleaseNotes(
    await fetchLocalizations({token: writeToken, versionId: versionRecord.id}, request),
  );

  report("\nAutomation stops here, on purpose. Still to be done by a human:");
  for (const step of manualNextSteps({appId, versionString, buildNumber, missingReleaseNotes})) {
    report(`  - ${step}`);
  }

  return {appId, versionString, buildNumber, written: true, missingReleaseNotes};
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  const credentials = readAppStoreConnectCredentials();

  await prepareAppStoreVersion(options, {
    makeToken: () => makeAppStoreConnectToken(credentials),
  });
}

if (isEntrypoint(import.meta.url)) {
  main().catch((error) => {
    console.error(`::error::${error.message}`);
    process.exitCode = 1;
  });
}
