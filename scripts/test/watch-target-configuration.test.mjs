import assert from "node:assert/strict";
import {readdir, readFile} from "node:fs/promises";
import {basename, join, relative} from "node:path";
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

// No Xcode target compiles an asset catalog out of these, and walking them
// costs more than the rest of the repository put together.
const UNSEARCHED_DIRECTORY_NAMES = new Set([
  ".build",
  ".git",
  "DerivedData",
  "node_modules",
  "build",
  "dist"
]);

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

test("the 1.0 phone app does not embed the retained watch product", async () => {
  const project = await readFile(projectPath, "utf8");

  // docs/heart-rate-zones-plan.md owns the 1.0 and 1.1 packaging split.
  // The target and product reference stay ready for 1.1, but no copy phase may
  // place the watch bundle under the shipping phone app's Watch directory.
  assert.match(project, /path = AscendWatch\.app;/);
  assert.doesNotMatch(
    project,
    /isa = PBXBuildFile; fileRef = [^;]+ \/\* AscendWatch\.app \*\//
  );
  assert.doesNotMatch(project, /AscendWatch\.app in Embed Watch Content/);
  assert.doesNotMatch(project, /name = "Embed Watch Content";/);
  assert.doesNotMatch(project, /dstPath = "\$\(CONTENTS_FOLDER_PATH\)\/Watch";/);
});

async function appIconSetDirectories(directory) {
  const found = [];

  for (const entry of await readdir(directory, {withFileTypes: true})) {
    if (!entry.isDirectory() || UNSEARCHED_DIRECTORY_NAMES.has(entry.name)) {
      continue;
    }

    const child = join(directory, entry.name);
    if (entry.name.endsWith(".appiconset")) {
      found.push(child);
      continue;
    }

    found.push(...(await appIconSetDirectories(child)));
  }

  return found;
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
    // command line overrides SDKROOT for every target in the build. Keeping the
    // explicit supported-platform list prevents an iOS build of the retained
    // watch target now and a wrong-platform bundle when 1.1 embeds it later.
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

test("every app icon set the project names ships an image file", async () => {
  const project = await readFile(projectPath, "utf8");

  const iconNames = new Set(
    [...project.matchAll(/ASSETCATALOG_COMPILER_APPICON_NAME = ([^;]+);/g)].map(([, value]) =>
      value.trim().replace(/^"(.*)"$/, "$1")
    )
  );

  // The watch app shipped exactly this defect: a single 1024x1024 slot with no
  // filename. It builds clean, emits no rendition and no CFBundleIconName, and
  // is caught only by Apple's server-side upload validation a whole deploy
  // cycle later. Read from the project rather than from a list here, so the
  // per-environment phone sets the Release compile check never resolves
  // (AppIconDev, AppIconStaging) are covered by the same assertion.
  assert.ok(iconNames.size > 0, "the project names no app icon set at all");

  const iconSets = await appIconSetDirectories(repositoryRoot);

  for (const iconName of iconNames) {
    const matching = iconSets.filter(
      (directory) => basename(directory) === `${iconName}.appiconset`
    );

    assert.ok(
      matching.length > 0,
      `the project builds against ${iconName} but no ${iconName}.appiconset exists`
    );

    for (const directory of matching) {
      const contents = JSON.parse(await readFile(join(directory, "Contents.json"), "utf8"));
      const withFiles = (contents.images ?? []).filter(
        (image) => typeof image.filename === "string" && image.filename.trim().length > 0
      );

      assert.ok(
        withFiles.length > 0,
        `${relative(repositoryRoot, directory)} declares icon slots but names no image file, ` +
          "so its bundle ships no icon and Apple rejects the upload"
      );
    }
  }
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
