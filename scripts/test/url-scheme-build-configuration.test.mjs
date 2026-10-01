import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { buildConfigurations, settingValue } from "../lib/monetization-build-settings.mjs";

// Every build used to register `ascendapp`, so with more than one installed iOS handed a link
// to whichever it chose: a production climber connecting Strava was sent back into the staging
// build. Each configuration now claims exactly one scheme of its own, and production keeps the
// one its STRAVA_SERVER_CONFIG redirect already names. functions/test/strava.test.ts holds the
// Cloud Functions to accepting exactly these same three.
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

// The XML property-list subset Info.plist files use, read into plain values so the assertions
// are about the keys Info.plist declares rather than how the file happens to be laid out.
function parsePlist(xml) {
  const tokens = [...xml.replace(/<!--[\s\S]*?-->/g, "").matchAll(/<(\/?)([a-z]+)[^>]*?(\/?)>([^<]*)/g)]
    .map(([, closing, tag, selfClosing, text]) => ({closing: closing === "/", tag, selfClosing: selfClosing === "/", text}));
  let index = tokens.findIndex(({tag, closing}) => tag === "plist" && !closing) + 1;
  const unescape = (text) => text
    .replaceAll("&lt;", "<").replaceAll("&gt;", ">").replaceAll("&quot;", "\"").replaceAll("&apos;", "'").replaceAll("&amp;", "&");

  function value() {
    const {tag, selfClosing, text} = tokens[index++];
    switch (tag) {
      case "true": case "false":
        if (!selfClosing) index++;
        return tag === "true";
      case "string": case "date": case "data":
        if (selfClosing) return "";
        index++;
        return unescape(text);
      case "integer": case "real":
        index++;
        return Number(text);
      case "array": {
        const items = [];
        if (selfClosing) return items;
        while (!tokens[index].closing) items.push(value());
        index++;
        return items;
      }
      case "dict": {
        const entries = {};
        if (selfClosing) return entries;
        while (!tokens[index].closing) {
          assert.equal(tokens[index].tag, "key", "a dict alternates keys and values");
          const key = unescape(tokens[index].text);
          index += 2;
          entries[key] = value();
        }
        index++;
        return entries;
      }
      default:
        throw new Error(`unsupported plist element <${tag}>`);
    }
  }
  return value();
}

test("the app registers only its configuration's scheme, and both bundles can read it", async () => {
  const appInfo = parsePlist(await read("AscendApp/Info.plist"));
  const widgetInfo = parsePlist(await read("AscendLiveActivityWidgets/Info.plist"));

  const registered = appInfo.CFBundleURLTypes.flatMap((type) => type.CFBundleURLSchemes ?? []);
  assert.equal(registered.filter((scheme) => scheme === "$(ASCEND_URL_SCHEME)").length, 1);
  assert.deepEqual(
    registered.filter((scheme) => scheme.startsWith("ascendapp")),
    [],
    "a literal scheme is shared by every build"
  );
  for (const info of [appInfo, widgetInfo]) {
    assert.equal(info.AscendURLScheme, "$(ASCEND_URL_SCHEME)");
  }
});
