import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const paywallPath = new URL(
  "../../web/public/superwall/onboarding-paywall.html",
  import.meta.url,
);

test("onboarding paywall paints a dark canvas before external resources load", async () => {
  const markup = await readFile(paywallPath, "utf8");
  const inlineStyleIndex = markup.indexOf("<style>");
  const runtimeScriptIndex = markup.indexOf("cdn.superwall.me/runtime/entrypoint.js");
  const externalStylesheetIndex = markup.indexOf('rel="stylesheet"');

  assert.notEqual(inlineStyleIndex, -1);
  assert.match(markup, /background:\s*#000/);
  assert.ok(inlineStyleIndex < runtimeScriptIndex);
  assert.ok(inlineStyleIndex < externalStylesheetIndex);
});
