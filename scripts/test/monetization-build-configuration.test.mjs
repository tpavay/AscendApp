import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  PLACEHOLDER_API_KEY_PREFIX,
  appBuildConfigurations,
  settingValue
} from "../lib/monetization-build-settings.mjs";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));
const projectPath = join(repositoryRoot, "AscendApp.xcodeproj/project.pbxproj");
const infoPlistPath = join(repositoryRoot, "AscendApp/Info.plist");
const preflightScript = join(
  repositoryRoot,
  "scripts/ci/assert-monetization-keys-configured.mjs"
);

function requiredSetting(buildSettings, name) {
  const value = settingValue(buildSettings, name);
  assert.notEqual(value, null, `Missing ${name}`);
  return value;
}

async function monetizationConfigurations() {
  const project = await readFile(projectPath, "utf8");
  const configurations = new Map();

  for (const [name, {bundleID, buildSettings}] of appBuildConfigurations(project)) {
    configurations.set(name, {
      bundleID,
      revenueCatAPIKey: requiredSetting(buildSettings, "ASCEND_REVENUECAT_API_KEY"),
      revenueCatTestAPIKey: requiredSetting(buildSettings, "ASCEND_REVENUECAT_TEST_API_KEY"),
      revenueCatTestStore: requiredSetting(buildSettings, "ASCEND_USE_REVENUECAT_TEST_STORE"),
      superwallAPIKey: requiredSetting(buildSettings, "ASCEND_SUPERWALL_API_KEY"),
      superwallTestMode: requiredSetting(buildSettings, "ASCEND_SUPERWALL_TEST_MODE")
    });
  }

  return configurations;
}

function runPreflight(configurationName, projectFilePath = projectPath) {
  return spawnSync(process.execPath, [preflightScript, configurationName, projectFilePath], {
    encoding: "utf8"
  });
}

async function projectWithSubstitutions(substitutions) {
  let project = await readFile(projectPath, "utf8");

  for (const [from, to] of Object.entries(substitutions)) {
    assert.ok(project.includes(from), `Project no longer contains ${from}`);
    project = project.replaceAll(from, to);
  }

  const path = join(mkdtempSync(join(tmpdir(), "ascend-monetization-")), "project.pbxproj");
  writeFileSync(path, project);
  return path;
}

test("each app build configuration owns its monetization project keys", async () => {
  const configurations = await monetizationConfigurations();

  assert.deepEqual([...configurations.keys()].sort(), ["Debug", "Release", "Staging"]);

  const debug = configurations.get("Debug");
  const staging = configurations.get("Staging");
  const release = configurations.get("Release");

  assert.equal(debug.bundleID, "com.TylerPavay.AscendApp.dev");
  assert.match(debug.revenueCatAPIKey, /^appl_/);
  assert.match(debug.superwallAPIKey, /^pk_/);

  assert.equal(staging.bundleID, "com.TylerPavay.AscendApp.staging");
  assert.equal(staging.revenueCatAPIKey, "REPLACE_ME_STAGING_REVENUECAT_KEY");
  assert.equal(staging.superwallAPIKey, "REPLACE_ME_STAGING_SUPERWALL_KEY");

  assert.equal(release.bundleID, "com.TylerPavay.AscendApp");
  assert.equal(release.revenueCatAPIKey, "REPLACE_ME_PRODUCTION_REVENUECAT_KEY");
  assert.equal(release.superwallAPIKey, "REPLACE_ME_PRODUCTION_SUPERWALL_KEY");

  assert.equal(
    new Set([...configurations.values()].map((configuration) => configuration.revenueCatAPIKey)).size,
    3
  );
  assert.equal(
    new Set([...configurations.values()].map((configuration) => configuration.superwallAPIKey)).size,
    3
  );
});

test("test-store and test-mode settings remain disabled in every environment", async () => {
  const configurations = await monetizationConfigurations();

  for (const [name, configuration] of configurations) {
    assert.equal(configuration.revenueCatTestAPIKey, "", name);
    assert.equal(configuration.revenueCatTestStore, "NO", name);
    assert.equal(configuration.superwallTestMode, "NO", name);
  }
});

test("Info.plist resolves the selected build settings for runtime configuration", async () => {
  const infoPlist = await readFile(infoPlistPath, "utf8");
  const runtimeMappings = new Map([
    ["AscendRevenueCatAPIKey", "ASCEND_REVENUECAT_API_KEY"],
    ["AscendRevenueCatTestAPIKey", "ASCEND_REVENUECAT_TEST_API_KEY"],
    ["AscendUseRevenueCatTestStore", "ASCEND_USE_REVENUECAT_TEST_STORE"],
    ["AscendSuperwallAPIKey", "ASCEND_SUPERWALL_API_KEY"],
    ["AscendSuperwallTestMode", "ASCEND_SUPERWALL_TEST_MODE"]
  ]);

  for (const [infoKey, buildSetting] of runtimeMappings) {
    const escapedBuildSetting = buildSetting.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    assert.match(
      infoPlist,
      new RegExp(`<key>${infoKey}<\\/key>\\s*<string>\\$\\(${escapedBuildSetting}\\)<\\/string>`)
    );
  }
});

test("the placeholder prefix is identical on the build gate and in the app", async () => {
  const configuration = await readFile(
    join(repositoryRoot, "AscendApp/Features/Monetization/Models/MonetizationConfiguration.swift"),
    "utf8"
  );
  const swiftPrefix = configuration.match(/static let placeholderAPIKeyPrefix = "(.*)"/)?.[1];

  assert.equal(swiftPrefix, PLACEHOLDER_API_KEY_PREFIX);
});

test("today's placeholder keys fail the staging and production preflight", () => {
  for (const configurationName of ["Staging", "Release"]) {
    const result = runPreflight(configurationName);

    assert.equal(result.status, 1, `${configurationName} must be rejected: ${result.stdout}`);
    assert.match(
      result.stderr,
      /::error::ASCEND_REVENUECAT_API_KEY is still the REPLACE_ME_ placeholder/
    );
    assert.match(
      result.stderr,
      /::error::ASCEND_SUPERWALL_API_KEY is still the REPLACE_ME_ placeholder/
    );
    assert.match(result.stderr, new RegExp(`for the ${configurationName} configuration`));
    assert.match(result.stderr, /docs\/superwall-paywall-setup\.md/);
  }
});

test("the preflight passes once real keys replace the placeholders", async () => {
  const replaced = await projectWithSubstitutions({
    REPLACE_ME_STAGING_REVENUECAT_KEY: "appl_stagingRevenueCatKey",
    REPLACE_ME_STAGING_SUPERWALL_KEY: "pk_stagingSuperwallKey",
    REPLACE_ME_PRODUCTION_REVENUECAT_KEY: "appl_productionRevenueCatKey",
    REPLACE_ME_PRODUCTION_SUPERWALL_KEY: "pk_productionSuperwallKey"
  });

  for (const configurationName of ["Staging", "Release"]) {
    const result = runPreflight(configurationName, replaced);

    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Verified real RevenueCat and Superwall keys/);
  }
});

test("the preflight also rejects emptied and unexpanded keys", async () => {
  const emptied = await projectWithSubstitutions({
    "ASCEND_REVENUECAT_API_KEY = REPLACE_ME_PRODUCTION_REVENUECAT_KEY;":
      'ASCEND_REVENUECAT_API_KEY = "";',
    "ASCEND_SUPERWALL_API_KEY = REPLACE_ME_PRODUCTION_SUPERWALL_KEY;":
      'ASCEND_SUPERWALL_API_KEY = "$(ASCEND_SUPERWALL_API_KEY)";'
  });
  const result = runPreflight("Release", emptied);

  assert.equal(result.status, 1);
  assert.match(result.stderr, /ASCEND_REVENUECAT_API_KEY is empty/);
  assert.match(result.stderr, /ASCEND_SUPERWALL_API_KEY is the unexpanded reference/);
});

test("the preflight reports unusable inputs as structural failures", () => {
  const unshippableConfiguration = runPreflight("Debug");
  assert.equal(unshippableConfiguration.status, 2);
  assert.match(unshippableConfiguration.stderr, /must be one of Staging, Release/);

  const missingProject = runPreflight("Release", join(tmpdir(), "ascend-missing.pbxproj"));
  assert.equal(missingProject.status, 2);
  assert.match(missingProject.stderr, /Cannot read/);
});

test("both shippable deploy paths run the preflight before the archive", async () => {
  const shippableWorkflows = new Map([
    ["deploy-staging.yml", "Staging"],
    ["deploy-production.yml", "Release"]
  ]);

  for (const [name, configurationName] of shippableWorkflows) {
    const workflow = await readFile(join(repositoryRoot, ".github/workflows", name), "utf8");
    const preflightIndex = workflow.indexOf(
      `node scripts/ci/assert-monetization-keys-configured.mjs ${configurationName}`
    );
    const archiveIndex = workflow.search(/bundle exec fastlane build_/);

    assert.notEqual(preflightIndex, -1, `${name} must run the monetization preflight`);
    assert.notEqual(archiveIndex, -1, `${name} must archive`);
    assert.ok(preflightIndex < archiveIndex, `${name} must gate before archiving`);
  }
});
