import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));
const pathFromRoot = (...parts) => join(repositoryRoot, ...parts);

const sourcePaths = {
  home: pathFromRoot("web/src/pages/index.astro"),
  support: pathFromRoot("web/src/pages/support.astro"),
  privacy: pathFromRoot("web/src/pages/privacy.astro"),
  terms: pathFromRoot("web/src/pages/terms.astro"),
  proposal: pathFromRoot("docs/app-store-racing-repositioning-proposal.md"),
  projectMemory: pathFromRoot("CLAUDE.md")
};

async function source(name) {
  return readFile(sourcePaths[name], "utf8");
}

function sectionBetween(contents, start, end) {
  const startIndex = contents.indexOf(start);
  assert.notEqual(startIndex, -1, `missing section start: ${start}`);

  const endIndex = contents.indexOf(end, startIndex + start.length);
  assert.notEqual(endIndex, -1, `missing section end: ${end}`);

  return contents.slice(startIndex, endIndex);
}

function textCodeBlockAfter(contents, heading) {
  const sectionStart = contents.indexOf(`## ${heading}`);
  assert.notEqual(sectionStart, -1, `missing proposal heading: ${heading}`);

  const match = contents.slice(sectionStart).match(/```text\n([^\n]+)\n```/);
  assert.ok(match, `missing proposal value: ${heading}`);
  return match[1];
}

test("the App Store proposal pins the settled racing metadata", async () => {
  const proposal = await source("proposal");
  const appName = textCodeBlockAfter(proposal, "App name");
  const subtitle = textCodeBlockAfter(proposal, "Subtitle");
  const keywords = textCodeBlockAfter(proposal, "Keywords");

  assert.equal(appName, "Ascend: Stair Stepper Racing");
  assert.equal(subtitle, "Race real towers from any gym");
  assert.equal([...appName].length, 28);
  assert.equal([...subtitle].length, 29);
  assert.equal(Buffer.byteLength(keywords, "utf8"), 100);
  assert.match(proposal, /Status: \*\*proposal\*\*, not applied\./);
  assert.match(proposal, /Nothing here has been written to App Store Connect\./);

  const indexedTokens = new Set(
    `${appName} ${subtitle}`.toLowerCase().match(/[a-z0-9]+/g)
  );
  const repeatedTokens = keywords
    .split(",")
    .filter((keyword) => indexedTokens.has(keyword));

  assert.deepEqual(repeatedTokens, []);
});

test("the public website consistently presents Ascend as racing", async () => {
  const publicSources = await Promise.all([
    source("home"),
    source("support"),
    source("privacy"),
    source("terms")
  ]);
  const outwardCopy = publicSources.join("\n");

  assert.match(outwardCopy, /stair stepper racing app/i);
  assert.match(outwardCopy, /Race real towers/);
  assert.match(outwardCopy, /Tower running, without the tower\./);
  assert.match(outwardCopy, /The first finisher claims it forever/);
  assert.match(outwardCopy, /does not import workouts from Apple Health/i);
  assert.match(outwardCopy, /does not accept manually entered workouts/i);

  for (const retiredCopy of [
    "Track the stair stepper like the workout it is",
    "fitness tracking and competition app",
    "helps you track stair-stepper workouts",
    "log sessions",
    "import supported workout data"
  ]) {
    assert.doesNotMatch(outwardCopy, new RegExp(retiredCopy, "i"));
  }
});

test("post-import-removal HealthKit disclosures describe quantity-sample enrichment only", async () => {
  const [privacy, terms, proposal, projectMemory] = await Promise.all([
    source("privacy"),
    source("terms"),
    source("proposal"),
    source("projectMemory")
  ]);
  const healthKitDisclosures = [
    [
      "Privacy Policy",
      sectionBetween(privacy, "<h2>Apple HealthKit</h2>", "<h2>Analytics, Tracking, and Advertising</h2>")
    ],
    [
      "Terms of Service",
      sectionBetween(terms, "<h2>What Ascend Does</h2>", "<h2>Eligibility</h2>")
    ],
    [
      "App Store proposal assumptions",
      sectionBetween(proposal, "## What this copy assumes about the app", "## App name")
    ],
    [
      "project memory",
      sectionBetween(projectMemory, "- Not a logger or an importer.", "Full rationale:")
    ]
  ];

  const forbiddenClaims = [
    [/step count/i, "pins an Apple Health step-count read"],
    [/resting energy/i, "pins a resting-energy identifier"],
    [/matching (?:Apple Health )?workout/i, "claims foreign workout matching"],
    [/workout entries/i, "claims foreign workout-entry reads"],
    [/average METs/i, "claims METs from a foreign workout"],
    [/lists Workouts/i, "claims Workouts read permission"]
  ];
  const violations = [];

  for (const [label, disclosure] of healthKitDisclosures) {
    if (!/heart-rate and energy samples/i.test(disclosure)) {
      violations.push(`${label}: does not use the stable heart-rate and energy-samples contract`);
    }
    for (const [pattern, description] of forbiddenClaims) {
      if (pattern.test(disclosure)) {
        violations.push(`${label}: ${description}`);
      }
    }
  }

  assert.deepEqual(violations, []);
});
