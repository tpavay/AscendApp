#!/usr/bin/env node
import {spawnSync} from "node:child_process";
import {readFileSync} from "node:fs";
import process from "node:process";

import {
  MIXPANEL_CONFIGURATION_CONTRACTS,
  builtBundleReasons
} from "../lib/mixpanel-build-settings.mjs";
import {mainAppInfoPlistPath} from "../lib/ipa-bundle.mjs";

const [configurationName, artifactPath] = process.argv.slice(2);
if (!MIXPANEL_CONFIGURATION_CONTRACTS.has(configurationName) || !artifactPath) {
  fail("Usage: assert-mixpanel-bundle.mjs <Debug|Staging|Release> <Info.plist|IPA>");
}

let plist;
if (artifactPath.endsWith(".ipa")) {
  const zipinfo = spawnSync("zipinfo", ["-1", artifactPath], {encoding: "utf8"});
  if (zipinfo.status !== 0) {
    fail(`Could not inspect the ${configurationName} IPA contents.`);
  }

  let infoPlistPath;
  try {
    infoPlistPath = mainAppInfoPlistPath(zipinfo.stdout.split(/\r?\n/));
  } catch (error) {
    fail(`The ${configurationName} IPA ${error.message}`);
  }

  const unzip = spawnSync("unzip", ["-p", artifactPath, infoPlistPath]);
  if (unzip.status !== 0 || unzip.stdout.length === 0) {
    fail(
      `Could not read the ${configurationName} iOS app Info.plist at ${infoPlistPath}.`
    );
  }
  plist = unzip.stdout;
} else {
  try {
    plist = readFileSync(artifactPath);
  } catch {
    fail(`Could not read the ${configurationName} processed Info.plist.`);
  }
}

const converted = spawnSync("plutil", ["-convert", "json", "-o", "-", "-"], {input: plist});
if (converted.status !== 0) {
  fail(`Could not parse the ${configurationName} processed Info.plist.`);
}

let infoDictionary;
try {
  infoDictionary = JSON.parse(converted.stdout.toString("utf8"));
} catch {
  fail(`Could not decode the ${configurationName} processed Info.plist.`);
}

const reasons = builtBundleReasons(configurationName, infoDictionary);
if (reasons.length > 0) {
  for (const reason of reasons) {
    console.error(`::error::${reason}`);
  }
  process.exit(1);
}

console.log(`Verified the ${configurationName} bundle resolves its dedicated Mixpanel destination.`);

function fail(message) {
  console.error(`::error::${message}`);
  process.exit(2);
}
