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

// Each job's steps as `{ name, run }`, in order. Only the shape these workflows use is read: a
// `- name:` item under a job's `steps:`, and its `run:` either inline or as a `|` block.
function jobSteps(workflow) {
  const jobs = new Map();
  let job = null;
  let step = null;
  let runIndent = null;
  for (const line of workflow.split("\n")) {
    const indent = line.length - line.trimStart().length;
    if (runIndent !== null) {
      if (line.trim() === "" || indent > runIndent) {
        step.run.push(line.trim());
        continue;
      }
      runIndent = null;
    }
    const jobName = line.match(/^  ([A-Za-z0-9_-]+):\s*$/)?.[1];
    if (jobName) {
      job = [];
      jobs.set(jobName, job);
      step = null;
      continue;
    }
    const stepName = line.match(/^ {6}- name:\s*(.+?)\s*$/)?.[1];
    if (stepName && job) {
      step = { name: stepName, run: [] };
      job.push(step);
      continue;
    }
    const run = line.match(/^ {8}run:\s*(.*?)\s*$/)?.[1];
    if (run !== undefined && step) {
      if (run === "|") runIndent = 8;
      else step.run.push(run);
    }
  }
  return jobs;
}

test("both deploy workflows run the check against their own site after they deploy Hosting", async () => {
  for (const [workflow, host] of [
    ["deploy-production.yml", "https://${{ vars.FIREBASE_PROJECT_ID_PRODUCTION }}.web.app"],
    ["deploy-staging.yml", "https://ascend-staging-fa7d5.web.app"]
  ]) {
    const jobs = jobSteps(await readFile(join(repositoryRoot, ".github/workflows", workflow), "utf8"));
    const [steps] = [...jobs.values()].filter((steps) => steps.some(({ name }) => name === "Deploy Hosting"));
    assert.ok(steps, `${workflow} has a job that deploys Hosting`);

    const names = steps.map(({ name }) => name);
    const deploy = names.indexOf("Deploy Hosting");
    const verify = names.indexOf("Verify Hosting serves the apple-app-site-association file");
    assert.ok(verify > deploy, `${workflow} verifies the file in the Hosting job, after the deploy`);

    const invocations = steps[verify].run
      .map((line) => line.match(/node scripts\/ci\/assert-aasa-served\.mjs "([^"]+)"/)?.[1])
      .filter(Boolean);
    assert.deepEqual([...new Set(invocations)], [host], `${workflow} checks ${host}`);
  }
});
