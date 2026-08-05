#!/usr/bin/env node
import {spawnSync} from "node:child_process";
import process from "node:process";

import {
  MIXPANEL_CONFIGURATION_CONTRACTS,
  mixpanelConfigurationReasons
} from "../lib/mixpanel-build-settings.mjs";

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
