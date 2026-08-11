import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {join} from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";

import {buildConfigurations, settingValue} from "../lib/monetization-build-settings.mjs";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));
const projectPath = join(repositoryRoot, "AscendApp.xcodeproj/project.pbxproj");
const watchInfoPlistPath = join(repositoryRoot, "AscendWatch/Info.plist");

// The iOS app's identifier per configuration, and the watch app's, which is that
// identifier plus `.watch`. WKCompanionAppBundleIdentifier has to name the
// matching environment's phone app: a mismatch produces a watch app that
// installs and never pairs, and nothing about the build says so.
const EXPECTED_IDENTIFIERS = new Map([
  ["Debug", "com.TylerPavay.AscendApp.dev"],
  ["Staging", "com.TylerPavay.AscendApp.staging"],
  ["Release", "com.TylerPavay.AscendApp"]
]);

const WATCH_SUFFIX = ".watch";

async function watchBuildConfigurations() {
  const project = await readFile(projectPath, "utf8");
  const configurations = new Map();

  for (const configuration of buildConfigurations(project)) {
    const {name, bundleID} = configuration;
    if (bundleID === null || !bundleID.endsWith(WATCH_SUFFIX)) {
      continue;
    }

    configurations.set(name, configuration);
  }

  return configurations;
}

function infoPlistString(plist, key) {
  const match = plist.match(new RegExp(`<key>${key}</key>\\s*\\n\\s*<string>([^<]*)</string>`));
  return match ? match[1] : null;
}

test("the watch target defines all three project configurations", async () => {
  const configurations = await watchBuildConfigurations();

  // Xcode requires every target to define every project configuration. A missing
  // Staging configuration falls back silently and would build the watch app
  // against the wrong environment rather than failing.
  assert.deepEqual([...configurations.keys()].sort(), ["Debug", "Release", "Staging"]);
});

test("each watch configuration pairs with its own environment's phone app", async () => {
  const configurations = await watchBuildConfigurations();

  for (const [name, {bundleID, buildSettings}] of configurations) {
    const companion = EXPECTED_IDENTIFIERS.get(name);

    assert.equal(bundleID, `${companion}${WATCH_SUFFIX}`, `${name} watch bundle identifier`);
    assert.equal(
      settingValue(buildSettings, "ASCEND_WATCH_COMPANION_BUNDLE_IDENTIFIER"),
      companion,
      `${name} names the wrong companion app, so the watch app would install and never pair`
    );
  }
});

test("the watch target builds for watchOS and nothing else", async () => {
  const configurations = await watchBuildConfigurations();

  for (const [name, {buildSettings}] of configurations) {
    assert.equal(settingValue(buildSettings, "SDKROOT"), "watchos", name);
    assert.equal(settingValue(buildSettings, "TARGETED_DEVICE_FAMILY"), "4", name);
    assert.equal(settingValue(buildSettings, "WATCHOS_DEPLOYMENT_TARGET"), "26.0", name);

    // Load-bearing beyond documentation. `-sdk <platform>` on an xcodebuild
    // command line overrides SDKROOT for every target in the build, and the
    // watch app is embedded regardless of what it was built for. Measured here:
    // with this setting the override is refused and the embedded binary stays
    // `platform WATCHOS`; without it, the same command produces `platform IOS`
    // and still reports BUILD SUCCEEDED.
    assert.equal(
      settingValue(buildSettings, "SUPPORTED_PLATFORMS"),
      "watchos watchsimulator",
      `${name} drops the supported-platform list that refuses an -sdk override`
    );
  }
});

test("the watch target's distribution signing is conditioned on the watchOS SDK", async () => {
  const configurations = await watchBuildConfigurations();

  // The widget extension is the precedent for the shape, but its conditionals
  // read [sdk=iphoneos*]. Copying those verbatim leaves the watch target
  // unsigned in the archive, which fails at signing rather than at build.
  for (const name of ["Staging", "Release"]) {
    const {buildSettings, bundleID} = configurations.get(name);

    assert.equal(settingValue(buildSettings, "CODE_SIGN_STYLE"), "Manual", name);
    assert.equal(
      settingValue(buildSettings, '"CODE_SIGN_IDENTITY\\[sdk=watchos\\*\\]"'),
      "Apple Distribution",
      `${name} does not condition its signing identity on the watchOS SDK`
    );
    assert.equal(
      settingValue(buildSettings, '"PROVISIONING_PROFILE_SPECIFIER\\[sdk=watchos\\*\\]"'),
      `match AppStore ${bundleID}`,
      `${name} does not name its match profile against the watchOS SDK`
    );
    assert.doesNotMatch(
      buildSettings,
      /sdk=iphoneos\*/,
      `${name} conditions watch signing on the iOS SDK, which leaves the target unsigned`
    );
  }

  assert.equal(
    settingValue(configurations.get("Debug").buildSettings, "CODE_SIGN_STYLE"),
    "Automatic",
    "Debug"
  );
});

test("the watch bundle declares what App Store Connect and the pairing need", async () => {
  const plist = await readFile(watchInfoPlistPath, "utf8");

  // Its own bundle, so its own declaration. A missing key on either bundle parks
  // the upload in Missing Compliance.
  assert.match(
    plist,
    /<key>ITSAppUsesNonExemptEncryption<\/key>\s*\n\s*<false\/>/,
    "the watch bundle must declare ITSAppUsesNonExemptEncryption as boolean false"
  );

  assert.match(plist, /<key>WKApplication<\/key>\s*\n\s*<true\/>/);

  assert.equal(
    infoPlistString(plist, "WKCompanionAppBundleIdentifier"),
    "$(ASCEND_WATCH_COMPANION_BUNDLE_IDENTIFIER)",
    "the companion identifier must come from the per-configuration build setting"
  );

  // Ascend's watch app is useless without the phone, and a dependent companion
  // app is the one that auto-installs alongside the iPhone app.
  assert.doesNotMatch(plist, /WKRunsIndependentlyOfCompanionApp/);
});
