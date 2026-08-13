#!/usr/bin/env node
// Assert that a built .app ships a usable App Store app icon.
//
// This failure is invisible to the build. An `AppIcon.appiconset` whose
// Contents.json declares a size slot with no `filename` compiles clean, emits
// no icon rendition, and emits no icon key into the processed Info.plist. The
// build reports `** BUILD SUCCEEDED **` and the first sign of trouble is
// Apple's server-side upload validation, one full deploy cycle later:
//
//   Missing Icons. No icons found for watch application
//   'AscendApp.app/Watch/AscendWatch.app'.
//   Missing Info.plist value. A value for the Info.plist key 'CFBundleIconName'
//   is missing in the bundle '...'.
//
// That is exactly what an empty placeholder set in AscendWatch did on
// 2026-08-13, blocking three staging deploys.
//
// The rendition checks matter as much as the key: Apple rejects an icon with an
// alpha channel, and that rejection is indistinguishable from this one at a
// glance. `Opaque` on the compiled rendition is the same fact `hasAlpha: no` on
// the source PNG reports, read from the artifact that actually ships.
//
// Usage: assert-app-icon-present.mjs <path/to/Bundle.app> <expected-idiom>

import {spawnSync} from "node:child_process";
import {existsSync} from "node:fs";
import path from "node:path";
import process from "node:process";

const REQUIRED_PIXEL_SIZE = 1024;

const [appBundle, expectedIdiom] = process.argv.slice(2);
if (!appBundle || !expectedIdiom) {
  fail("Usage: assert-app-icon-present.mjs <path/to/Bundle.app> <expected-idiom>", 2);
}

const infoPlistPath = path.join(appBundle, "Info.plist");
if (!existsSync(infoPlistPath)) {
  fail(`No processed Info.plist at ${infoPlistPath}.`);
}

const infoDictionary = readPlist(infoPlistPath);

// Xcode writes the key at the top level for some target types and nested under
// CFBundleIcons for others; Apple accepts either, so accept either here rather
// than pinning the shape one SDK happens to produce.
const iconName =
  nonEmptyString(infoDictionary.CFBundleIconName) ??
  nonEmptyString(infoDictionary.CFBundleIcons?.CFBundlePrimaryIcon?.CFBundleIconName);

if (!iconName) {
  fail(
    `${infoPlistPath} declares no non-empty CFBundleIconName. The bundle's ` +
      "ASSETCATALOG_COMPILER_APPICON_NAME must name an app icon set that has an image file."
  );
}

const assetsPath = path.join(appBundle, "Assets.car");
if (!existsSync(assetsPath)) {
  fail(`${appBundle} declares app icon '${iconName}' but ships no compiled Assets.car.`);
}

const assetutil = spawnSync("xcrun", ["assetutil", "--info", assetsPath], {
  encoding: "utf8",
  maxBuffer: 64 * 1024 * 1024
});
if (assetutil.status !== 0) {
  fail(`Could not inspect ${assetsPath}: ${assetutil.stderr?.trim() ?? "assetutil failed"}`);
}

let renditions;
try {
  renditions = JSON.parse(assetutil.stdout);
} catch {
  fail(`Could not decode the asset catalog listing for ${assetsPath}.`);
}

const iconImages = renditions.filter(
  (rendition) =>
    rendition.AssetType === "Icon Image" &&
    rendition.Name === iconName &&
    rendition.Idiom === expectedIdiom
);

if (iconImages.length === 0) {
  fail(
    `${assetsPath} carries no '${expectedIdiom}' icon image named '${iconName}'. ` +
      "The app icon set is declared but empty - give its size slot a filename."
  );
}

const marketingSize = iconImages.find(
  (rendition) =>
    rendition.PixelWidth === REQUIRED_PIXEL_SIZE && rendition.PixelHeight === REQUIRED_PIXEL_SIZE
);
if (!marketingSize) {
  const sizes = iconImages.map((r) => `${r.PixelWidth}x${r.PixelHeight}`).join(", ");
  fail(
    `Icon '${iconName}' (${expectedIdiom}) in ${assetsPath} has no ` +
      `${REQUIRED_PIXEL_SIZE}x${REQUIRED_PIXEL_SIZE} rendition. Found: ${sizes}.`
  );
}

const transparent = iconImages.filter((rendition) => rendition.Opaque !== true);
if (transparent.length > 0) {
  fail(
    `Icon '${iconName}' (${expectedIdiom}) in ${assetsPath} has a rendition with transparency. ` +
      "App icons must be fully opaque; Apple rejects the upload otherwise."
  );
}

console.log(
  `Verified ${appBundle} declares CFBundleIconName '${iconName}' and ships an opaque ` +
    `${REQUIRED_PIXEL_SIZE}x${REQUIRED_PIXEL_SIZE} '${expectedIdiom}' rendition.`
);

function readPlist(plistPath) {
  const converted = spawnSync("plutil", ["-convert", "json", "-o", "-", plistPath], {
    encoding: "utf8"
  });
  if (converted.status !== 0) {
    fail(`Could not parse ${plistPath}.`);
  }

  try {
    return JSON.parse(converted.stdout);
  } catch {
    fail(`Could not decode ${plistPath}.`);
  }
}

function nonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0 ? value : undefined;
}

function fail(message, code = 1) {
  console.error(`::error::${message}`);
  process.exit(code);
}
