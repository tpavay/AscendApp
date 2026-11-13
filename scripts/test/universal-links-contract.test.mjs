import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { appBuildConfigurations, settingValue } from "../lib/monetization-build-settings.mjs";
import { CI_RELEVANT_PATHS, matchesAny } from "../lib/required-check-routing.mjs";
import { ciFilterPatterns } from "./support/ci-workflow-filters.mjs";

// Universal links are three files that only work together, and each can be right while the link
// still opens Safari: the app's entitlement claims the domain, the site's
// apple-app-site-association file vouches for the app, and the host has to serve that file as
// JSON with no redirect. Nothing in a build or a deploy fails when one of them drifts, so this
// suite is the only place the three are held to each other (`docs/universal-links.md`).
const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));
const pathFromRoot = (...parts) => join(repositoryRoot, ...parts);
const read = (path) => readFile(pathFromRoot(path), "utf8");

const TEAM_ID = "QWGVB7TN4T";
const DOMAIN = "ascendstepper.com";
const AASA_PATH = "web/public/.well-known/apple-app-site-association";
const AASA_URL_PATH = "/.well-known/apple-app-site-association";

// The XML property-list subset an entitlements file uses, read into plain values.
function parseEntitlements(xml) {
  const dict = xml.match(/<dict>([\s\S]*)<\/dict>/)?.[1] ?? "";
  const entitlements = new Map();
  for (const [, key, value] of dict.matchAll(/<key>([^<]+)<\/key>\s*(<array\s*\/>|<array>[\s\S]*?<\/array>|<true\/>|<false\/>|<string>[^<]*<\/string>)/g)) {
    if (value.startsWith("<array")) {
      entitlements.set(key, [...value.matchAll(/<string>([^<]*)<\/string>/g)].map(([, text]) => text));
    } else if (value === "<true/>" || value === "<false/>") {
      entitlements.set(key, value === "<true/>");
    } else {
      entitlements.set(key, value.replace(/<\/?string>/g, ""));
    }
  }
  return entitlements;
}

async function appBundleIdentifiers() {
  const configurations = appBuildConfigurations(await read("AscendApp.xcodeproj/project.pbxproj"));
  const bundleOf = (name) => configurations.get(name)?.bundleID;
  return {
    Debug: bundleOf("Debug"),
    Staging: bundleOf("Staging"),
    Release: bundleOf("Release"),
    configurations
  };
}

test("the site vouches for exactly the staging and production apps, on exactly the /go paths", async () => {
  const aasa = JSON.parse(await read(AASA_PATH));
  const { Debug, Staging, Release } = await appBundleIdentifiers();

  assert.deepEqual(Object.keys(aasa), ["applinks"], "no other service belongs in this file");
  assert.equal(aasa.applinks.details.length, 1);

  const [details] = aasa.applinks.details;
  assert.deepEqual(
    [...details.appIDs].sort(),
    [`${TEAM_ID}.${Release}`, `${TEAM_ID}.${Staging}`].sort(),
    "app IDs are the team ID and the Release and Staging bundle IDs, read from the project"
  );
  assert.ok(!details.appIDs.some((id) => id.endsWith(Debug)), "the dev build is not vouched for");
  assert.ok(!details.appIDs.some((id) => /LiveClimbWidgets|\.watch$/.test(id)), "an extension is never the link's target");

  assert.deepEqual(
    details.components,
    [{ "/": "/go" }, { "/": "/go/*" }],
    "the paths are /go and /go/*, with no query or fragment condition: the email's ?src= must match"
  );
  assert.equal(details.paths, undefined, "the legacy `paths` form is not mixed with `components`");
});

test("every app build configuration claims the domain, and claims nothing else", async () => {
  const { configurations } = await appBundleIdentifiers();

  for (const [name, { buildSettings }] of configurations) {
    assert.equal(
      settingValue(buildSettings, "CODE_SIGN_ENTITLEMENTS"),
      "AscendApp/AscendApp.entitlements",
      `${name} signs with the one entitlements file`
    );
  }
  assert.equal(configurations.size, 3);

  const entitlements = parseEntitlements(await read("AscendApp/AscendApp.entitlements"));
  assert.deepEqual(
    entitlements.get("com.apple.developer.associated-domains"),
    [`applinks:${DOMAIN}`],
    "one applinks entry for the bare domain: no wildcard, no ?mode=developer, no webcredentials"
  );
});

test("Firebase Hosting serves the file as JSON, unredirected, and does not drop the dot directory", async () => {
  const hosting = JSON.parse(await read("firebase.json")).hosting;

  const rule = hosting.headers.find(({ source }) => source === AASA_URL_PATH);
  assert.ok(rule, "a header rule names the file exactly");
  assert.equal(
    rule.headers.find(({ key }) => key.toLowerCase() === "content-type")?.value,
    "application/json",
    "Hosting infers no type for an extensionless file and sends none, which Apple's fetch rejects"
  );

  assert.equal(
    hosting.appAssociation,
    "NONE",
    "left on AUTO, Firebase serves its own file, which claims every path on the site, instead of the deployed one"
  );
  assert.deepEqual(hosting.redirects ?? [], [], "Apple does not follow a redirect for this file");
  for (const rewrite of hosting.rewrites ?? []) {
    assert.ok(
      !AASA_URL_PATH.startsWith(rewrite.source.replace(/\*+$/, "")) || rewrite.source === "/api/unsubscribe",
      `rewrite ${rewrite.source} must not capture ${AASA_URL_PATH}`
    );
  }

  // `**/.*` is the stock ignore, and it only works because the CLI lists files rather than
  // directories. A pattern that reaches inside the directory would deploy a site with no file.
  for (const pattern of hosting.ignore ?? []) {
    assert.ok(
      !/well-known/.test(pattern) && !/\*\/\*\*$/.test(pattern) && !/^\.\*\/\*\*|\/\.\*\/\*\*$/.test(pattern),
      `ignore pattern ${pattern} must not swallow .well-known/`
    );
  }
});

test("CI runs this suite whenever any of the files it holds together changes", async () => {
  const scriptsFilter = ciFilterPatterns(await read(".github/workflows/ci.yml")).get("scripts") ?? [];
  for (const path of [
    "AscendApp/AscendApp.entitlements",
    "AscendApp.xcodeproj/project.pbxproj",
    "firebase.json",
    "web/public/.well-known/apple-app-site-association"
  ]) {
    assert.ok(matchesAny(path, CI_RELEVANT_PATHS), `a change to ${path} does not trigger CI`);
    assert.ok(matchesAny(path, scriptsFilter), `a change to ${path} does not run the scripts suite`);
  }
});
