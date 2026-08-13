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
// Given an .ipa, both shipped bundles are checked - the installable app and the
// watch app nested inside it - because the artifact Apple rejects is the IPA,
// and the phone icon set it carries is the per-configuration one (AppIconDev,
// AppIconStaging) that the Release compile check never resolves.
//
// An IPA carrying no watch app passes, loudly. This guard's job is "the icon
// Apple rejects is present"; it must not also quietly assert "the watch app
// ships". Whether the watch app rides along in the 1.0 submission is an open
// product decision, and the research on it recommended dropping it from 1.0 -
// so a hard requirement here would fail the deploy after the archive is already
// built, at exactly the moment someone is unblocking a submission. Announcing
// the absence keeps a watch app that silently vanished from the scheme visible
// in the deploy log without blocking anyone on it. A friendlier failure message
// was considered and rejected: it still hard-fails an intentional removal. More
// than one nested watch bundle stays fatal, because that is a real defect
// however the scope question lands.
//
// Usage: assert-app-icon-present.mjs <path/to/Bundle.app> <expected-idiom>
//        assert-app-icon-present.mjs <path/to/App.ipa>

import {spawnSync} from "node:child_process";
import {existsSync, mkdtempSync, rmSync} from "node:fs";
import {tmpdir} from "node:os";
import path from "node:path";
import process from "node:process";

import {mainAppInfoPlistPath} from "../lib/ipa-bundle.mjs";

const REQUIRED_PIXEL_SIZE = 1024;

// The nested bundle Apple names in the rejection: one app bundle beneath the
// installable app's Watch directory.
const WATCH_APP_INFO_PLIST_PATTERN = /^Payload\/[^/]+\.app\/Watch\/[^/]+\.app\/Info\.plist$/;

const [artifactPath, expectedIdiom] = process.argv.slice(2);
const isArchive = artifactPath?.endsWith(".ipa") ?? false;

if (!artifactPath || (!isArchive && !expectedIdiom)) {
  fail(
    "Usage: assert-app-icon-present.mjs <path/to/Bundle.app> <expected-idiom> | <path/to/App.ipa>",
    2
  );
}

if (isArchive) {
  assertArchive(artifactPath);
} else {
  assertBundle(artifactPath, expectedIdiom);
}

function assertArchive(ipaPath) {
  const zipinfo = spawnSync("zipinfo", ["-1", ipaPath], {
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024
  });
  if (zipinfo.status !== 0) {
    fail(`Could not inspect the contents of ${ipaPath}.`);
  }

  const entries = zipinfo.stdout.split(/\r?\n/);

  let mainInfoPlist;
  try {
    mainInfoPlist = mainAppInfoPlistPath(entries);
  } catch (error) {
    fail(`${ipaPath} ${error.message}`);
  }

  const watchInfoPlists = entries.filter((entry) => WATCH_APP_INFO_PLIST_PATTERN.test(entry));
  if (watchInfoPlists.length > 1) {
    fail(
      `${ipaPath} contains ${watchInfoPlists.length} watch app bundles at ` +
        `Payload/<app>.app/Watch/<watch app>.app (${watchInfoPlists.join(", ")}); ` +
        "expected at most one."
    );
  }

  const staging = mkdtempSync(path.join(tmpdir(), "ascend-app-icon-"));
  // fail() exits the process, so a finally block would never run.
  process.on("exit", () => rmSync(staging, {recursive: true, force: true}));

  assertBundle(extractBundle(ipaPath, path.dirname(mainInfoPlist), staging), "phone");

  if (watchInfoPlists.length === 0) {
    console.log(
      `Skipped the nested icon check: ${ipaPath} embeds no watch app at ` +
        "Payload/<app>.app/Watch/<watch app>.app. If the watch app is still meant to ship, " +
        "it has left the scheme."
    );
    return;
  }

  assertBundle(extractBundle(ipaPath, path.dirname(watchInfoPlists[0]), staging), "watch");
}

// Only the two members the check reads, so answering a question about two files
// does not cost unpacking the whole archive. A member the archive does not carry
// simply stays absent, which assertBundle reports in its own words.
function extractBundle(ipaPath, bundleEntry, destination) {
  for (const member of [`${bundleEntry}/Info.plist`, `${bundleEntry}/Assets.car`]) {
    spawnSync("unzip", ["-o", "-q", ipaPath, member, "-d", destination]);
  }

  return path.join(destination, bundleEntry);
}

function assertBundle(appBundle, idiom) {
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
      rendition.Idiom === idiom
  );

  if (iconImages.length === 0) {
    fail(
      `${assetsPath} carries no '${idiom}' icon image named '${iconName}'. ` +
        "The app icon set is declared but empty - give its size slot a filename."
    );
  }

  // The dark and tinted variants are authored *without* a background, because
  // the system composites its own behind them, so they are legitimately not
  // opaque and asserting otherwise would fail a correct icon set the day
  // someone fills those slots. assetutil tags them with an `Appearance`
  // (`UIAppearanceDark`, `ISAppearanceTintable`) and leaves the key off the
  // default icon, which is the one Apple rejects for carrying alpha.
  const primaryIcons = iconImages.filter((rendition) => rendition.Appearance === undefined);
  if (primaryIcons.length === 0) {
    const variants = iconImages.map((r) => r.Appearance).join(", ");
    fail(
      `Icon '${iconName}' (${idiom}) in ${assetsPath} ships only appearance variants ` +
        `(${variants}) and no default icon. The default size slot needs a filename.`
    );
  }

  const marketingSize = primaryIcons.find(
    (rendition) =>
      rendition.PixelWidth === REQUIRED_PIXEL_SIZE && rendition.PixelHeight === REQUIRED_PIXEL_SIZE
  );
  if (!marketingSize) {
    const sizes = primaryIcons.map((r) => `${r.PixelWidth}x${r.PixelHeight}`).join(", ");
    fail(
      `Icon '${iconName}' (${idiom}) in ${assetsPath} has no ` +
        `${REQUIRED_PIXEL_SIZE}x${REQUIRED_PIXEL_SIZE} rendition. Found: ${sizes}.`
    );
  }

  const transparent = primaryIcons.filter((rendition) => rendition.Opaque !== true);
  if (transparent.length > 0) {
    fail(
      `Icon '${iconName}' (${idiom}) in ${assetsPath} has a rendition with transparency. ` +
        "App icons must be fully opaque; Apple rejects the upload otherwise."
    );
  }

  console.log(
    `Verified ${appBundle} declares CFBundleIconName '${iconName}' and ships an opaque ` +
      `${REQUIRED_PIXEL_SIZE}x${REQUIRED_PIXEL_SIZE} '${idiom}' rendition.`
  );
}

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
