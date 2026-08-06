#!/usr/bin/env node

import {isEntrypoint} from "../lib/is-entrypoint.mjs";
import {buildUploadReservesNumber} from "../lib/app-store-connect-build-uploads.mjs";
import {
  BUILD_NUMBER_PATTERN,
  appStoreConnectRequest,
  assertAppOwnsBundleId,
  makeAppStoreConnectToken,
  readAppStoreConnectCredentials,
  requestUnderContract,
} from "../lib/app-store-connect-client.mjs";

export const MAX_BUILD_NUMBER = 4_294_967_295;
export const PREVIOUS_BUILD_NUMBER_FLOOR = 37_105_794;
export const BUILDS_PER_DAY = 99;

const PAGE_LIMIT = 200;
const MAX_PAGES = 1_000;

function parseInteger(value, label) {
  if (!BUILD_NUMBER_PATTERN.test(String(value))) {
    throw new Error(`${label} must be a non-negative integer, got '${value}'.`);
  }

  return BigInt(value);
}

export function utcDateStamp(timestampSeconds = Math.floor(Date.now() / 1000)) {
  const timestamp = Number(parseInteger(timestampSeconds, "UTC timestamp"));
  const date = new Date(timestamp * 1_000);
  if (Number.isNaN(date.valueOf())) {
    throw new Error(`UTC timestamp is outside the supported date range: '${timestampSeconds}'.`);
  }

  const year = date.getUTCFullYear();
  if (year < 1_000 || year > 9_999) {
    throw new Error(`UTC year must have exactly four digits, got '${year}'.`);
  }

  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");
  return `${year}${month}${day}`;
}

export function deriveReadableBuildNumber(dateStamp, highestUploadedBuildNumber) {
  if (!/^\d{8}$/.test(dateStamp)) {
    throw new Error(`UTC date must use YYYYMMDD, got '${dateStamp}'.`);
  }

  const firstBuildToday = BigInt(`${dateStamp}01`);
  const lastBuildToday = BigInt(`${dateStamp}${BUILDS_PER_DAY}`);
  const previous = highestUploadedBuildNumber === null
    ? null
    : parseInteger(highestUploadedBuildNumber, "Highest uploaded build number");

  let candidate;
  if (previous === null || previous < firstBuildToday) {
    candidate = firstBuildToday;
  } else if (previous < lastBuildToday) {
    candidate = previous + 1n;
  } else if (previous === lastBuildToday) {
    throw new Error(
      `Daily build-number sequence exhausted for ${dateStamp}: suffix 99 is already uploaded. ` +
        "A 100th build cannot be represented by YYYYMMDDNN.",
    );
  } else {
    throw new Error(
      `Highest uploaded build number ${previous} is not below today's maximum ${lastBuildToday}. ` +
        "Refusing to emit a duplicate or regressing build number.",
    );
  }

  if (candidate <= BigInt(PREVIOUS_BUILD_NUMBER_FLOOR)) {
    throw new Error(
      `Derived build number ${candidate} is not above the legacy cutover floor ` +
        `${PREVIOUS_BUILD_NUMBER_FLOOR}.`,
    );
  }

  if (previous !== null && candidate <= previous) {
    throw new Error(
      `Derived build number ${candidate} is not above the highest uploaded build number ${previous}.`,
    );
  }

  if (candidate > BigInt(MAX_BUILD_NUMBER)) {
    throw new Error(
      `Derived build number ${candidate} exceeds the App Store limit ${MAX_BUILD_NUMBER}.`,
    );
  }

  return Number(candidate);
}

async function collectVersions({
  token,
  request,
  appId,
  firstPage,
  readVersion,
  label,
  contract,
  reservesNumber = () => true,
}) {
  const versions = [];
  let next = firstPage;

  for (let page = 0; next && page < MAX_PAGES; page += 1) {
    const result = await requestUnderContract(token, next, request, contract);
    if (!Array.isArray(result?.data)) {
      throw new Error(
        `APP_STORE_CONTRACT_UNEXPECTED_SHAPE: The App Store Connect ${label} listing for app ` +
          `${appId} returned no 'data' array. Refusing to allocate against an unread listing.`,
      );
    }

    for (const record of result.data) {
      if (!reservesNumber(record)) continue;

      const version = readVersion(record);
      if (!BUILD_NUMBER_PATTERN.test(String(version))) {
        throw new Error(
          `App Store Connect app ${appId} has non-numeric ${label} number '${version}'. ` +
            "Refusing to guess its ordering.",
        );
      }
      versions.push(BigInt(version));
    }
    next = result?.links?.next ?? null;
  }

  if (next) {
    throw new Error(`App Store Connect ${label} listing exceeded ${MAX_PAGES} pages.`);
  }

  return versions;
}

export async function fetchHighestUploadedBuildNumber(
  {token, appId, expectedBundleId},
  request = appStoreConnectRequest,
) {
  await assertAppOwnsBundleId({token, appId, expectedBundleId}, request);

  const buildVersions = await collectVersions({
    token,
    request,
    appId,
    firstPage: `/builds?filter%5Bapp%5D=${appId}&fields%5Bbuilds%5D=version&limit=${PAGE_LIMIT}`,
    readVersion: (build) => build?.attributes?.version,
    label: "build",
    contract:
      "GET /v1/builds accepts filter[app], fields[builds]=version and " +
      `limit=${PAGE_LIMIT}`,
  });

  // `/v1/builds` contains only processed binaries. The upload ledger exists
  // earlier and is the authoritative reservation while Apple is still
  // processing a Transporter upload. Counting both prevents a queued run from
  // reusing a number that has uploaded successfully but is not a Build yet.
  const uploadVersions = await collectVersions({
    token,
    request,
    appId,
    firstPage:
      `/apps/${appId}/buildUploads?fields%5BbuildUploads%5D=` +
      `cfBundleVersion,state&limit=${PAGE_LIMIT}`,
    reservesNumber: buildUploadReservesNumber,
    readVersion: (upload) => upload?.attributes?.cfBundleVersion,
    label: "build upload",
    contract:
      "GET /v1/apps/{id}/buildUploads accepts fields[buildUploads]=cfBundleVersion,state " +
      `and limit=${PAGE_LIMIT}`,
  });

  // Both listings are bounded at MAX_PAGES x PAGE_LIMIT records, which is far
  // past the engine's argument-count limit for a spread call.
  const versions = buildVersions.concat(uploadVersions);

  if (versions.length === 0) return null;
  return versions.reduce((highest, version) => version > highest ? version : highest).toString();
}

async function main() {
  const [appId, expectedBundleId, timestampArgument] = process.argv.slice(2);
  if (!appId || !expectedBundleId || process.argv.length > 5) {
    throw new Error(
      "Usage: derive-build-number.sh <app-store-connect-app-id> <bundle-id> [utc-timestamp]",
    );
  }

  const timestamp = timestampArgument ?? Math.floor(Date.now() / 1_000);
  const token = makeAppStoreConnectToken(readAppStoreConnectCredentials());
  const highest = await fetchHighestUploadedBuildNumber({token, appId, expectedBundleId});
  const buildNumber = deriveReadableBuildNumber(utcDateStamp(timestamp), highest);
  process.stdout.write(`${buildNumber}\n`);
}

// A guard that silently fails to match exits 0 with no output, and the deploy
// archives an empty CFBundleVersion from it.
if (isEntrypoint(import.meta.url)) {
  main().catch((error) => {
    console.error(`::error::${error.message}`);
    process.exitCode = 1;
  });
}
