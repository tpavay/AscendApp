#!/usr/bin/env node
import {spawnSync} from "node:child_process";
import {join} from "node:path";
import process from "node:process";
import {fileURLToPath} from "node:url";

import {
  MIXPANEL_CONFIGURATION_CONTRACTS,
  mixpanelConfigurationReasons
} from "../lib/mixpanel-build-settings.mjs";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));

// Resolving build settings for a scheme with SPM dependencies populates whichever
// DerivedData it is pointed at, so a local run from a throwaway worktree would
// orphan one under ~/Library/Developer/Xcode/DerivedData exactly as a bare build
// would. CI must stay on the default store and byte-identical: ci.yml,
// deploy-staging.yml and deploy-production.yml all restore an actions/cache keyed
// on ~/Library/Developer/Xcode/DerivedData/**/SourcePackages, and resolving
// packages anywhere else would silently defeat that cache.
const derivedDataArguments =
  process.env.GITHUB_ACTIONS === "true"
    ? []
    : ["-derivedDataPath", join(repositoryRoot, ".build/dd")];

const configurations = new Map();

for (const [configurationName, contract] of MIXPANEL_CONFIGURATION_CONTRACTS) {
  const result = spawnSync(
    "xcodebuild",
    [
      "-project",
      "AscendApp.xcodeproj",
      "-scheme",
      contract.scheme,
      "-configuration",
      configurationName,
      ...derivedDataArguments,
      "-showBuildSettings",
      "-json"
    ],
    {encoding: "utf8"}
  );

  if (result.status !== 0) {
    fail(`Could not resolve ${configurationName} build settings.`);
  }

  let settings;
  try {
    const targets = JSON.parse(result.stdout);
    settings = targets.find(({target}) => target === "AscendApp")?.buildSettings;
  } catch {
    fail(`Could not parse ${configurationName} build settings.`);
  }

  if (!settings) {
    fail(`Resolved build settings contain no AscendApp target for ${configurationName}.`);
  }

  configurations.set(configurationName, {
    projectID: settings.ASCEND_MIXPANEL_PROJECT_ID ?? null,
    token: settings.ASCEND_MIXPANEL_TOKEN ?? null
  });
}

const reasons = mixpanelConfigurationReasons(configurations);
if (reasons.length > 0) {
  for (const reason of reasons) {
    console.error(`::error::${reason}`);
  }
  process.exit(1);
}

console.log("Verified distinct Mixpanel destinations for Debug, Staging, and Release.");

function fail(message) {
  console.error(`::error::${message}`);
  process.exit(2);
}
