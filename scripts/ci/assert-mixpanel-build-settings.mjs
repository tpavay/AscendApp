#!/usr/bin/env node
/**
 * Proves the Mixpanel destination `xcodebuild` actually resolves for a
 * configuration, without printing the token.
 *
 * Usage: assert-mixpanel-build-settings.mjs [Debug|Staging|Release]
 *
 * With a configuration named, only that one is resolved and checked against
 * its own contract. Each `-showBuildSettings` resolves the whole package
 * graph - 55 s on a `macos-15` runner, measured 2026-09-02 on job
 * 100376172708 - so a job that builds one configuration pays for one. The
 * pairwise distinctness of all three destinations is a property of the
 * project file, and `scripts/test/mixpanel-build-configuration.test.mjs`
 * proves it from `project.pbxproj` without resolving anything. With no
 * argument all three are resolved and checked together, as the deploy
 * workflows do.
 */
import {spawnSync} from "node:child_process";
import {join} from "node:path";
import process from "node:process";
import {fileURLToPath} from "node:url";

import {
  MIXPANEL_CONFIGURATION_CONTRACTS,
  mixpanelConfigurationReasons,
  mixpanelDestinationReasons
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

const [requestedConfiguration] = process.argv.slice(2);

if (requestedConfiguration && !MIXPANEL_CONFIGURATION_CONTRACTS.has(requestedConfiguration)) {
  fail(
    `Unknown configuration ${requestedConfiguration}; expected one of ` +
      `${[...MIXPANEL_CONFIGURATION_CONTRACTS.keys()].join(", ")}.`
  );
}

const configurationNames = requestedConfiguration
  ? [requestedConfiguration]
  : [...MIXPANEL_CONFIGURATION_CONTRACTS.keys()];

const configurations = new Map();

for (const configurationName of configurationNames) {
  const contract = MIXPANEL_CONFIGURATION_CONTRACTS.get(configurationName);
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

const reasons = requestedConfiguration
  ? mixpanelDestinationReasons(requestedConfiguration, configurations.get(requestedConfiguration))
  : mixpanelConfigurationReasons(configurations);

if (reasons.length > 0) {
  for (const reason of reasons) {
    console.error(`::error::${reason}`);
  }
  process.exit(1);
}

if (requestedConfiguration) {
  console.log(`Verified the ${requestedConfiguration} Mixpanel destination.`);
} else {
  console.log("Verified distinct Mixpanel destinations for Debug, Staging, and Release.");
}

function fail(message) {
  console.error(`::error::${message}`);
  process.exit(2);
}
