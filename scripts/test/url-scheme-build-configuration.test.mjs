import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { buildConfigurations, settingValue } from "../lib/monetization-build-settings.mjs";

// Every build used to register `ascendapp`, so with more than one installed iOS handed a link
// to whichever it chose: a production climber connecting Strava was sent back into the staging
// build. Each configuration now claims exactly one scheme of its own, production keeps the one
// its STRAVA_SERVER_CONFIG redirect already names, and the Cloud Functions accept exactly these.
const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));
const EXPECTED_SCHEMES = new Map([
  ["Debug", "ascendapp-dev"],
  ["Staging", "ascendapp-stg"],
  ["Release", "ascendapp"]
]);

async function read(path) {
  return readFile(join(repositoryRoot, path), "utf8");
}

test("each build configuration names its own URL scheme, and production keeps ascendapp", async () => {
  const project = await read("AscendApp.xcodeproj/project.pbxproj");
  const declared = buildConfigurations(project)
    .map(({name, buildSettings}) => ({name, scheme: settingValue(buildSettings, "ASCEND_URL_SCHEME")}))
    .filter(({scheme}) => scheme !== null);

  assert.deepEqual(
    new Map(declared.map(({name, scheme}) => [name, scheme])),
    EXPECTED_SCHEMES,
    "declared once per configuration at project level, so the app and its widget agree"
  );
  assert.equal(declared.length, EXPECTED_SCHEMES.size, "a target-level override would split the app from its widget");
});

test("the app registers only its configuration's scheme, and both bundles can read it", async () => {
  const appInfo = await read("AscendApp/Info.plist");
  const widgetInfo = await read("AscendLiveActivityWidgets/Info.plist");

  assert.match(appInfo, /<key>CFBundleURLSchemes<\/key>\s*<array>\s*<string>\$\(ASCEND_URL_SCHEME\)<\/string>\s*<\/array>/);
  assert.doesNotMatch(appInfo, /<string>ascendapp(-[a-z]+)?<\/string>/, "a literal scheme is shared by every build");
  for (const info of [appInfo, widgetInfo]) {
    assert.match(info, /<key>AscendURLScheme<\/key>\s*<string>\$\(ASCEND_URL_SCHEME\)<\/string>/);
  }
});

test("the Cloud Functions accept exactly the schemes the builds register", async () => {
  const config = await read("functions/src/strava/config.ts");
  const declared = config.match(/STRAVA_REDIRECT_SCHEMES: readonly string\[\] = \[([\s\S]*?)\];/);
  assert.ok(declared, "STRAVA_REDIRECT_SCHEMES is declared as a literal list");
  const schemes = [...declared[1].matchAll(/"([^"]+)"/g)].map(([, scheme]) => scheme).sort();
  assert.deepEqual(schemes, [...EXPECTED_SCHEMES.values()].sort());
});
