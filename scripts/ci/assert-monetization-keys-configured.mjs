#!/usr/bin/env node
// Fails a staging or production archive whose RevenueCat / Superwall keys are
// still placeholders, or whose access and test-mode settings would reopen the
// hard paywall. Without this, the deploy pipeline happily ships a build whose
// hard paywall can never resolve an entitlement, or never fires at all.
//
// Usage: assert-monetization-keys-configured.mjs <Staging|Release> [project.pbxproj]
//
// Exit codes: 0 shippable, 1 unshippable keys, 2 structural or usage error.
import {readFile} from "node:fs/promises";
import process from "node:process";

import {
  appBuildConfigurations,
  unshippableMonetizationReasons
} from "../lib/monetization-build-settings.mjs";

const SHIPPABLE_CONFIGURATIONS = ["Staging", "Release"];
const STRUCTURAL_EXIT_CODE = 2;

function failStructurally(message) {
  console.error(`::error::${message}`);
  process.exit(STRUCTURAL_EXIT_CODE);
}

const [configurationName, projectPath = "AscendApp.xcodeproj/project.pbxproj"] =
  process.argv.slice(2);

if (!SHIPPABLE_CONFIGURATIONS.includes(configurationName)) {
  failStructurally(
    `Build configuration must be one of ${SHIPPABLE_CONFIGURATIONS.join(", ")}, got "${configurationName ?? ""}".`
  );
}

let project;
try {
  project = await readFile(projectPath, "utf8");
} catch (error) {
  failStructurally(`Cannot read ${projectPath}: ${error.message}`);
}

const configuration = appBuildConfigurations(project).get(configurationName);

if (!configuration) {
  failStructurally(
    `No AscendApp build configuration named ${configurationName} in ${projectPath}.`
  );
}

const reasons = unshippableMonetizationReasons(
  configuration.buildSettings,
  configurationName
);

if (reasons.length > 0) {
  for (const reason of reasons) {
    console.error(`::error::${reason}`);
  }
  console.error(
    "Correct the monetization build settings before shipping this build. " +
      "See docs/superwall-paywall-setup.md."
  );
  process.exit(1);
}

console.log(
  `Verified real RevenueCat and Superwall keys and a gated paywall for ` +
    `${configuration.bundleID} (${configurationName}).`
);
