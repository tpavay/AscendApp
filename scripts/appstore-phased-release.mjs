#!/usr/bin/env node

/**
 * Drives App Store phased release for Ascend from the command line.
 *
 * Phased release rolls an *update* out over seven days (1/2/5/10/20/50/100% of users with
 * automatic updates on), which is the only rollback-adjacent lever the App Store itself
 * gives an iOS binary. It does not apply to an app's first release - see
 * `docs/remote-config-kill-switches.md` for what covers launch day instead.
 *
 * Pausing is the halt: it freezes the rollout at its current percentage so no further
 * users are moved onto the bad build. Users who already updated stay updated, which is why
 * the Remote Config kill switches - not this - are what stops a data-corrupting path.
 *
 * Usage:
 *   node scripts/appstore-phased-release.mjs status
 *   node scripts/appstore-phased-release.mjs enable --confirm
 *   node scripts/appstore-phased-release.mjs pause --confirm
 *   node scripts/appstore-phased-release.mjs resume --confirm
 *   node scripts/appstore-phased-release.mjs release-to-all --confirm
 *
 * Add `--version <versionString>` to any command to name the version explicitly instead of
 * letting the script resolve it.
 *
 * Credentials come from the same environment variables the TestFlight upload lane uses:
 *   APP_STORE_CONNECT_API_KEY_ID, APP_STORE_CONNECT_API_ISSUER_ID,
 *   APP_STORE_CONNECT_API_KEY (base64-encoded .p8)
 */

import {
  appStoreConnectRequest,
  makeAppStoreConnectToken,
  readAppStoreConnectCredentials,
} from "./lib/app-store-connect-client.mjs";
import {newestCandidate, selectVersion} from "./lib/phased-release-selection.mjs";

const BUNDLE_ID = "com.TylerPavay.AscendApp";
const VERSION_PAGE_LIMIT = 50;
const MAX_VERSION_PAGES = 10;

const COMMANDS = new Set(["status", "enable", "pause", "resume", "release-to-all"]);
const MUTATING_COMMANDS = new Set(["enable", "pause", "resume", "release-to-all"]);

const STATE_FOR_COMMAND = {
  pause: "PAUSED",
  resume: "ACTIVE",
  "release-to-all": "COMPLETE",
};

async function findApp(token) {
  const result = await appStoreConnectRequest(
    token,
    `/apps?filter[bundleId]=${encodeURIComponent(BUNDLE_ID)}&limit=1`,
  );
  const app = result?.data?.[0];
  if (!app) {
    throw new Error(`No App Store Connect app found for bundle id ${BUNDLE_ID}`);
  }
  return app;
}

/**
 * Every iOS version record, each paired with its phased release.
 *
 * Deliberately a full listing rather than `limit=1`: the endpoint documents no default
 * ordering, so asking for one record asks the API to choose the target of a `pause`.
 * `selectVersion` makes that choice explicitly instead.
 */
async function fetchVersionCandidates(token, appId) {
  const candidates = [];
  let url =
    `/apps/${appId}/appStoreVersions?filter[platform]=IOS` +
    `&limit=${VERSION_PAGE_LIMIT}&include=appStoreVersionPhasedRelease`;

  for (let page = 0; page < MAX_VERSION_PAGES && url; page += 1) {
    const result = await appStoreConnectRequest(token, url);

    for (const version of result?.data ?? []) {
      const phasedReleaseId = version.relationships?.appStoreVersionPhasedRelease?.data?.id;
      const phasedRelease = result.included?.find(
        (entry) => entry.type === "appStoreVersionPhasedReleases" && entry.id === phasedReleaseId,
      );
      candidates.push({version, phasedRelease: phasedRelease ?? null});
    }

    url = result?.links?.next ?? null;
  }

  return candidates;
}

function describe({version, phasedRelease}) {
  const lines = [
    `Version:       ${version.attributes?.versionString ?? "(unknown)"}`,
    `Store state:   ${version.attributes?.appStoreState ?? "(unknown)"}`,
  ];

  if (!phasedRelease) {
    lines.push("Phased release: NOT CONFIGURED - this version would go to 100% at once.");
    return lines.join("\n");
  }

  const attributes = phasedRelease.attributes ?? {};
  lines.push(
    `Phased release: ${attributes.phasedReleaseState ?? "(unknown)"}`,
    `  day number:   ${attributes.currentDayNumber ?? "-"} of 7`,
    `  started:      ${attributes.startDate ?? "-"}`,
    `  paused for:   ${attributes.totalPauseDuration ?? 0} day(s) of the 30 allowed`,
  );
  return lines.join("\n");
}

async function enable(token, {version, phasedRelease}) {
  if (phasedRelease) {
    console.log("Phased release is already configured for this version. Nothing to do.");
    return;
  }

  await appStoreConnectRequest(token, "/appStoreVersionPhasedReleases", {
    method: "POST",
    body: {
      data: {
        type: "appStoreVersionPhasedReleases",
        attributes: {phasedReleaseState: "INACTIVE"},
        relationships: {
          appStoreVersion: {data: {type: "appStoreVersions", id: version.id}},
        },
      },
    },
  });

  console.log(
    `Phased release armed for ${version.attributes?.versionString}. ` +
      "It becomes ACTIVE when the version is released.",
  );
}

async function setState(token, phasedRelease, state) {
  if (!phasedRelease) {
    throw new Error(
      "This version has no phased release to change. Run `enable --confirm` first.",
    );
  }

  await appStoreConnectRequest(token, `/appStoreVersionPhasedReleases/${phasedRelease.id}`, {
    method: "PATCH",
    body: {
      data: {
        type: "appStoreVersionPhasedReleases",
        id: phasedRelease.id,
        attributes: {phasedReleaseState: state},
      },
    },
  });

  console.log(`Phased release state set to ${state}.`);
}

async function main() {
  const [command, ...rest] = process.argv.slice(2);

  if (!command || !COMMANDS.has(command)) {
    throw new Error(
      `Usage: appstore-phased-release.mjs <${[...COMMANDS].join("|")}> ` +
        "[--confirm] [--version <versionString>]",
    );
  }

  const confirmed = rest.includes("--confirm");
  if (MUTATING_COMMANDS.has(command) && !confirmed) {
    throw new Error(`\`${command}\` changes the live rollout. Re-run with --confirm.`);
  }

  const versionFlagIndex = rest.indexOf("--version");
  const requestedVersionString = versionFlagIndex === -1 ? null : rest[versionFlagIndex + 1];
  if (versionFlagIndex !== -1 && !requestedVersionString) {
    throw new Error("`--version` needs a version string, for example `--version 1.0.1`.");
  }

  const token = makeAppStoreConnectToken(readAppStoreConnectCredentials());
  const app = await findApp(token);
  const candidates = await fetchVersionCandidates(token, app.id);
  const state = selectVersion(candidates, {command, requestedVersionString});

  console.log(describe(state));

  if (command === "status") {
    // Naming the newer record explicitly, because "status reported on 1.0.1" is only
    // reassuring if the operator can see that 1.0.2 exists and is not the one rolling out.
    const newest = newestCandidate(candidates);
    if (newest && newest.version.id !== state.version.id) {
      console.log(
        `\nNewer record not rolling out: ${newest.version.attributes?.versionString ?? "(unknown)"} ` +
          `(${newest.version.attributes?.appStoreState ?? "unknown state"}).`,
      );
    }
    return;
  }

  console.log("");
  if (command === "enable") {
    await enable(token, state);
    return;
  }

  await setState(token, state.phasedRelease, STATE_FOR_COMMAND[command]);
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
