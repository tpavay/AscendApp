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
 *   2. Reads the existing version record and stops early if it is past editing - a refusal
 *      by default, a reported no-op under `--skip-when-not-editable`.
 *   3. Reads the build already attached, so a conflict it can decide on costs seconds
 *      rather than the whole polling budget.
 *   4. Waits, on a bounded budget, for Apple to finish processing the build.
 *   5. Creates the version record when it does not exist yet - `releaseType: MANUAL`, so
 *      even an approved release waits for a human.
 *   6. Attaches the build, replacing an older one loudly and refusing to step backwards
 *      onto one that is not older.
 *   7. Reports what a human still has to do.
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
 * `--skip-when-not-editable` turns a version that is already with Apple into a reported
 * no-op instead of a failure. The chained workflow run passes it, because a backend-only
 * merge to `main` uploads a build while the previous version is in review and that outcome
 * is expected; a human dispatching the workflow by name does not, and still gets a red run.
 *
 * Credentials come from the same environment variables the TestFlight upload lane uses:
 *   APP_STORE_CONNECT_API_KEY_ID, APP_STORE_CONNECT_API_ISSUER_ID,
 *   APP_STORE_CONNECT_API_KEY (base64-encoded .p8)
 */

import {appendFile, readFile} from "node:fs/promises";
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
  AppStorePreparationRefusal,
  assertVersionString,
  earlyAttachmentRefusal,
  localesMissingReleaseNotes,
  manualNextSteps,
  nonEditableVersionNotice,
  nonEditableVersionRefusal,
  parseMarketingVersion,
  resolveAttachmentPlan,
  resolveVersionRecordOutcome,
  selectAttachableBuild,
} from "./lib/app-store-version-preparation.mjs";

export const DEFAULT_BUNDLE_ID = "com.TylerPavay.AscendApp";
// Waiting for the NEWEST build in the train is load-bearing, so every run now pays Apple's
// full processing latency rather than settling for a build that happened to be ready. This
// budget stays inside the workflow's `timeout-minutes: 60` with room for checkout, Node setup
// and the summary step, so a timeout means something is wrong rather than that Apple was slow.
export const DEFAULT_TIMEOUT_SECONDS = 3_000;
export const DEFAULT_POLL_INTERVAL_SECONDS = 60;

const PROJECT_FILE = "AscendApp.xcodeproj/project.pbxproj";
const PAGE_LIMIT = 200;
const MAX_PAGES = 20;

const APP_LOOKUP_CONTRACT = "GET /v1/apps accepts filter[bundleId] and limit";
const VERSION_LISTING_CONTRACT =
  "GET /v1/apps/{id}/appStoreVersions accepts filter[platform]=IOS and limit";
const BUILD_LISTING_CONTRACT =
  "GET /v1/builds accepts filter[app], filter[preReleaseVersion.version], " +
  "include=preReleaseVersion, fields[builds] (which must list preReleaseVersion, because a " +
  "sparse fieldset selects relationships too) and fields[preReleaseVersions]";
const ATTACHED_BUILD_CONTRACT =
  "GET /v1/appStoreVersions/{id}/relationships/build returns the attached build's identifier";
const ATTACHED_BUILD_DETAIL_CONTRACT = "GET /v1/builds/{id} accepts fields[builds]=version";
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
    skipWhenNotEditable: false,
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

    if (argument === "--skip-when-not-editable") {
      options.skipWhenNotEditable = true;
      continue;
    }

    const field = valueFlags.get(argument);
    if (!field) {
      throw new Error(
        `Unknown argument '${argument}'. Usage: appstore-prepare-version.mjs [--confirm] ` +
          "[--skip-when-not-editable] [--app-id <id>] [--bundle-id <id>] " +
          "[--version <versionString>] [--build <number>] [--timeout-seconds <n>] " +
          "[--poll-seconds <n>]",
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
    // `fields[builds]` is a sparse fieldset that selects RELATIONSHIPS as well as
    // attributes, so `preReleaseVersion` has to be named here even though `include=` already
    // asks for it. Omitting it strips `relationships.preReleaseVersion` from every build,
    // every train reads as unknown, and the run burns its whole budget on a train mismatch
    // that never existed.
    "&fields%5Bbuilds%5D=version,processingState,expired,uploadedDate,preReleaseVersion" +
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
      if (!trainId) {
        throw new AppStorePreparationRefusal(
          `APP_STORE_CONTRACT_UNEXPECTED_SHAPE: build ${build?.id ?? "(unknown)"} came back with ` +
            "no preReleaseVersion relationship, so the train it belongs to cannot be read. " +
            `The assumption that stopped holding: ${BUILD_LISTING_CONTRACT}.`,
        );
      }

      const train = (result.included ?? []).find(
        (entry) => entry.type === "preReleaseVersions" && entry.id === trainId,
      );
      if (!train?.attributes?.version) {
        throw new AppStorePreparationRefusal(
          `APP_STORE_CONTRACT_UNEXPECTED_SHAPE: build ${build?.id ?? "(unknown)"} names train ` +
            `${trainId}, which the listing did not include. ` +
            `The assumption that stopped holding: ${BUILD_LISTING_CONTRACT}.`,
        );
      }

      records.push({build, trainVersion: train.attributes.version});
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
        `The newest build in train ${versionString} has not finished processing on attempt ` +
          `${attempt} (${records.length} build record(s) in the train). Waiting for Apple ` +
          "rather than attaching an older build that happens to be ready.",
      );
    } catch (error) {
      // A refusal Apple understood - an unknown build number, an expired binary, a rejected
      // filter - says the same thing every minute for the next forty. Only a rate limit or
      // an outage earns a retry. A refusal this script raised itself carries no HTTP status,
      // so it has to be recognised by type: without that it looked transient, burned the
      // whole budget, and surfaced as a processing timeout that blamed Apple's queue.
      if (error instanceof AppStorePreparationRefusal) throw error;
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

/**
 * The build currently attached to a version record, by identifier AND number.
 *
 * The relationship carries only an opaque identifier, and deciding whether this run's build
 * is newer than the attached one needs the number, so it costs one extra GET.
 */
async function fetchAttachment({token, versionId}, request) {
  const buildId = await attachedBuildId({token, versionId}, request);
  if (!buildId) return null;

  const result = await requestUnderContract(
    token,
    `/builds/${buildId}?fields%5Bbuilds%5D=version`,
    request,
    ATTACHED_BUILD_DETAIL_CONTRACT,
  );

  return {buildId, buildNumber: result?.data?.attributes?.version ?? null};
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

/**
 * A version past editing is either a failure or the expected answer, and which one is the
 * caller's call, passed in explicitly rather than read from the GitHub context here: the
 * chained run finds this every time a backend-only merge ships while the previous version is
 * with Apple, and a red run for an expected outcome teaches everyone to ignore red runs.
 */
function refuseOrSkipNonEditableVersion({
  appId,
  versionString,
  state,
  buildNumber,
  skipWhenNotEditable,
  report,
}) {
  if (!skipWhenNotEditable) {
    throw new AppStorePreparationRefusal(nonEditableVersionRefusal(versionString, state));
  }

  const notice = nonEditableVersionNotice(versionString, state);
  report(notice);
  return {
    appId,
    versionString,
    buildNumber,
    written: false,
    outcome: "version-not-editable",
    notice,
  };
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
  // release, or released cannot take this build, and finding that out after the whole polling
  // budget helps nobody.
  const existingRecords = await fetchVersionRecords({token, appId}, request);
  const versionOutcome = resolveVersionRecordOutcome(existingRecords, versionString);

  if (versionOutcome.outcome === "not-editable") {
    return refuseOrSkipNonEditableVersion({
      appId,
      versionString,
      state: versionOutcome.state,
      buildNumber: null,
      skipWhenNotEditable: options.skipWhenNotEditable,
      report,
    });
  }

  const existing = versionOutcome.record;
  report(
    existing
      ? `Version ${versionString} already exists as ${versionOutcome.state}; reusing it.`
      : `Version ${versionString} does not exist yet; it will be created.`,
  );

  // Read what is attached now, for the same reason the version state is read now: a conflict
  // this run can already decide on must not cost the full polling budget first.
  const attachment = existing
    ? await fetchAttachment({token, versionId: existing.id}, request)
    : null;
  if (attachment) {
    report(
      `Version ${versionString} currently has build ${attachment.buildNumber ?? "(unknown)"} ` +
        "attached.",
    );
  }

  const earlyRefusal = earlyAttachmentRefusal({
    versionString,
    attachment,
    buildExplicitlyRequested: options.buildNumber !== null,
  });
  if (earlyRefusal) throw new AppStorePreparationRefusal(earlyRefusal);

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
    // The release-notes gap is the deliberate substitute for pushing metadata, so a dry run
    // that cannot report it is only reporting half of what it would do. Reading it stays a
    // plain GET, and only an existing version record has localizations to read.
    const missingReleaseNotes = existing
      ? localesMissingReleaseNotes(
          await fetchLocalizations({token: makeToken(), versionId: existing.id}, request),
        )
      : [];

    // The plan is resolved here too, so the preview cannot promise an attach the confirmed
    // run would refuse.
    const plan = resolveAttachmentPlan({
      versionString,
      attachment,
      selectedBuildId: selectedBuild.build.id,
      selectedBuildNumber: buildNumber,
      buildExplicitlyRequested: options.buildNumber !== null,
    });

    report(
      plan.action === "refuse"
        ? `\nDry run. A confirmed run would refuse: ${plan.message}`
        : `\nDry run. Re-run with --confirm to ${existing ? "attach" : "create version " + versionString + " and attach"} ` +
            `build ${buildNumber}.`,
    );
    if (plan.action !== "refuse" && plan.message) report(plan.message);
    reportReleaseNotesGap(report, {existing, missingReleaseNotes});

    return {
      appId,
      versionString,
      buildNumber,
      written: false,
      outcome: "dry-run",
      attachmentAction: plan.action,
      missingReleaseNotes,
    };
  }

  // Every token minted at the start of a run that may have waited out the whole budget has
  // expired by now; the write path mints its own.
  const writeToken = makeToken();

  // Re-read the version state as well as the attachment, rather than trusting reads taken
  // before a wait that can run the better part of an hour. The human who might attach a build
  // mid-wait is the same human who might press Submit mid-wait, and he is the captain: a
  // submission during that window used to make this run PATCH a WAITING_FOR_REVIEW version,
  // which Apple refuses as a raw API error that --skip-when-not-editable can no longer turn
  // into the clean no-op it exists for. Two GETs are the price of not confusing him during
  // his own release.
  const currentVersionOutcome = existing
    ? resolveVersionRecordOutcome(
        await fetchVersionRecords({token: writeToken, appId}, request),
        versionString,
      )
    : {outcome: "create", record: null, state: null};

  if (currentVersionOutcome.outcome === "not-editable") {
    return refuseOrSkipNonEditableVersion({
      appId,
      versionString,
      state: currentVersionOutcome.state,
      buildNumber,
      skipWhenNotEditable: options.skipWhenNotEditable,
      report,
    });
  }

  const versionRecord =
    currentVersionOutcome.record ??
    (await createVersionRecord({token: writeToken, appId, versionString}, request));
  if (!currentVersionOutcome.record) {
    report(`Created App Store version ${versionString} with releaseType MANUAL.`);
  }

  const currentAttachment = currentVersionOutcome.record
    ? await fetchAttachment({token: writeToken, versionId: versionRecord.id}, request)
    : null;
  const plan = resolveAttachmentPlan({
    versionString,
    attachment: currentAttachment,
    selectedBuildId: selectedBuild.build.id,
    selectedBuildNumber: buildNumber,
    buildExplicitlyRequested: options.buildNumber !== null,
  });

  if (plan.action === "refuse") throw new AppStorePreparationRefusal(plan.message);

  if (plan.action === "already-attached") {
    report(plan.message);
  } else {
    if (plan.message) report(plan.message);
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

  return {
    appId,
    versionString,
    buildNumber,
    written: true,
    outcome: "prepared",
    attachmentAction: plan.action,
    missingReleaseNotes,
  };
}

function reportReleaseNotesGap(report, {existing, missingReleaseNotes}) {
  if (!existing) {
    report(
      "Release notes cannot be read yet: the version record does not exist, so it has no " +
        "localizations. The confirmed run reports them.",
    );
    return;
  }

  report(
    missingReleaseNotes.length > 0
      ? `"What's New" is still empty for: ${missingReleaseNotes.join(", ")}. Nothing in this ` +
          "repository owns that copy, so a human writes it in App Store Connect."
      : 'Every locale already has "What\'s New" text.',
  );
}

/**
 * Lets the workflow's summary step tell a prepared version from a run that correctly found
 * nothing to do. Only the GitHub Actions handoff lives here; the decision itself is made in
 * pure code above.
 */
async function recordWorkflowOutcome(outcome) {
  const outputPath = process.env.GITHUB_OUTPUT;
  if (!outputPath) return;
  await appendFile(outputPath, `outcome=${outcome}\n`);
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  const credentials = readAppStoreConnectCredentials();

  const result = await prepareAppStoreVersion(options, {
    makeToken: () => makeAppStoreConnectToken(credentials),
  });

  await recordWorkflowOutcome(result.outcome);
}

if (isEntrypoint(import.meta.url)) {
  main().catch((error) => {
    console.error(`::error::${error.message}`);
    process.exitCode = 1;
  });
}
