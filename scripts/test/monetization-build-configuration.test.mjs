import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const projectFileURL = new URL("../../AscendApp.xcodeproj/project.pbxproj", import.meta.url);
const infoPlistURL = new URL("../../AscendApp/Info.plist", import.meta.url);

function settingValue(buildSettings, name) {
  const match = buildSettings.match(new RegExp(`^\\s*${name} = (.*);$`, "m"));
  assert.ok(match, `Missing ${name}`);
  return match[1].replace(/^"(.*)"$/, "$1");
}

function appBuildConfigurations(project) {
  const configurations = new Map();
  const appBundleIDs = new Set([
    "com.TylerPavay.AscendApp.dev",
    "com.TylerPavay.AscendApp.staging",
    "com.TylerPavay.AscendApp"
  ]);
  const configurationPattern =
    /[A-F0-9]{24} \/\* (Debug|Staging|Release) \*\/ = \{\n\s+isa = XCBuildConfiguration;\n\s+buildSettings = \{([\s\S]*?)\n\s+\};\n\s+name = \1;\n\s+\};/g;

  for (const match of project.matchAll(configurationPattern)) {
    const [, name, buildSettings] = match;
    const bundleIDMatch = buildSettings.match(/^\s*PRODUCT_BUNDLE_IDENTIFIER = (.*);$/m);
    if (!bundleIDMatch) {
      continue;
    }

    const bundleID = bundleIDMatch[1].replace(/^"(.*)"$/, "$1");
    if (!appBundleIDs.has(bundleID)) {
      continue;
    }

    configurations.set(name, {
      bundleID,
      revenueCatAPIKey: settingValue(buildSettings, "ASCEND_REVENUECAT_API_KEY"),
      revenueCatTestAPIKey: settingValue(buildSettings, "ASCEND_REVENUECAT_TEST_API_KEY"),
      revenueCatTestStore: settingValue(buildSettings, "ASCEND_USE_REVENUECAT_TEST_STORE"),
      superwallAPIKey: settingValue(buildSettings, "ASCEND_SUPERWALL_API_KEY"),
      superwallTestMode: settingValue(buildSettings, "ASCEND_SUPERWALL_TEST_MODE")
    });
  }

  return configurations;
}

test("each app build configuration owns its monetization project keys", async () => {
  const project = await readFile(projectFileURL, "utf8");
  const configurations = appBuildConfigurations(project);

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
  const project = await readFile(projectFileURL, "utf8");
  const configurations = appBuildConfigurations(project);

  for (const [name, configuration] of configurations) {
    assert.equal(configuration.revenueCatTestAPIKey, "", name);
    assert.equal(configuration.revenueCatTestStore, "NO", name);
    assert.equal(configuration.superwallTestMode, "NO", name);
  }
});

test("Info.plist resolves the selected build settings for runtime configuration", async () => {
  const infoPlist = await readFile(infoPlistURL, "utf8");
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
