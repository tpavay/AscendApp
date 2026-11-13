import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { assertAasaServed } from "../ci/assert-aasa-served.mjs";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));

const shipped = await readFile(join(repositoryRoot, "web/public/.well-known/apple-app-site-association"), "utf8");
// What Firebase Hosting serves on its own when `appAssociation` is AUTO, copied from the live site.
const generated = '{"applinks":{"apps":[],"details":[{"appID":"QWGVB7TN4T.com.TylerPavay.AscendApp","paths":["NOT /__/auth/action/","NOT /__/auth/handler/","NOT /_/*","/*"]}]}}';

function respond({ status = 200, contentType = "application/json", body }) {
  return async () =>
    new Response(body, { status, headers: contentType === null ? {} : { "content-type": contentType } });
}

test("the file this repository ships passes", async () => {
  assert.deepEqual(await assertAasaServed("https://example.test", respond({ body: shipped })), []);
});

test("asks for the well-known path and refuses to follow a redirect", async () => {
  let seen;
  await assertAasaServed("https://example.test", async (url, init) => {
    seen = { url: String(url), redirect: init.redirect };
    return new Response(shipped, { headers: { "content-type": "application/json" } });
  });
  assert.deepEqual(seen, {
    url: "https://example.test/.well-known/apple-app-site-association",
    redirect: "manual"
  });
});

test("a redirect, a wrong content type, a missing file and broken JSON each fail", async () => {
  const redirect = await assertAasaServed("https://example.test", respond({ status: 301, body: "" }));
  assert.match(redirect.join("\n"), /answered 301/);

  const wrongType = await assertAasaServed("https://example.test", respond({ contentType: "text/html", body: shipped }));
  assert.match(wrongType.join("\n"), /must be application\/json/);

  const noType = await assertAasaServed("https://example.test", respond({ contentType: null, body: shipped }));
  assert.match(noType.join("\n"), /"\(none\)"|must be application\/json/);

  const missing = await assertAasaServed("https://example.test", respond({ status: 404, body: "<html>" }));
  assert.ok(missing.length >= 2);

  const broken = await assertAasaServed("https://example.test", respond({ body: "{" }));
  assert.match(broken.join("\n"), /not valid JSON/);
});

test("Firebase's generated file, which claims every path, fails", async () => {
  const problems = await assertAasaServed("https://example.test", respond({ body: generated }));
  assert.match(problems.join("\n"), /appAssociation is NONE/);
});

test("both deploy workflows run the check right after they deploy Hosting", async () => {
  for (const [workflow, host] of [
    ["deploy-production.yml", "https://${{ vars.FIREBASE_PROJECT_ID_PRODUCTION }}.web.app"],
    ["deploy-staging.yml", "https://ascend-staging-fa7d5.web.app"]
  ]) {
    const text = await readFile(join(repositoryRoot, ".github/workflows", workflow), "utf8");
    const deploy = text.indexOf("      - name: Deploy Hosting\n");
    const verify = text.indexOf("      - name: Verify Hosting serves the apple-app-site-association file\n");
    assert.ok(deploy !== -1 && verify > deploy, `${workflow} verifies after the Hosting deploy`);
    assert.ok(text.includes(`node scripts/ci/assert-aasa-served.mjs "${host}"`), `${workflow} checks ${host}`);
  }
});
