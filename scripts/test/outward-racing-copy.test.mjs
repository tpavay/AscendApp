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
  projectMemory: pathFromRoot("CLAUDE.md"),
  demoSeed: pathFromRoot("scripts/seed-demo-user.mjs")
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

function fencedBlockAfter(contents, heading) {
  const sectionStart = contents.indexOf(`## ${heading}`);
  assert.notEqual(sectionStart, -1, `missing proposal heading: ${heading}`);

  const match = contents.slice(sectionStart).match(/```text\n([\s\S]*?)\n```/);
  assert.ok(match, `missing proposal block: ${heading}`);
  return match[1];
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

test("the proposed listing copy sells nothing #437 removed", async () => {
  const proposal = await source("proposal");
  const description = fencedBlockAfter(proposal, "Description");
  const reviewNotes = fencedBlockAfter(proposal, "App Review notes");

  // The live listing sold "Log stair-stepper workouts in Ascend or import
  // supported workouts from Apple Health", and the live review notes told the
  // reviewer to exercise the app that way. #437 deleted both paths on
  // 2026-08-08, which makes each sentence a Guideline 2.1/2.3 problem as well
  // as an untruth.
  //
  // Both words survive in exactly one place each: the sentence that denies the
  // feature. Those sentences are asserted, then cut, and whatever still says
  // "manual" or "import" afterwards is the promise coming back.
  const denials = {
    description: [
      "Every climb and every record in Ascend comes from a session you performed in Ascend. There is no manual entry and no importing from other apps."
    ],
    "review notes": [
      "There is no manual entry and no import.",
      "Typed-in workouts and Apple Health workout import were both removed"
    ]
  };
  const forbidden = [
    [/\blog(ging|s|ged)?\b/i, "promises logging"],
    [/\bmanual(ly)?\b/i, "promises manual entry"],
    [/\bimport(s|ing|ed)?\b/i, "promises importing"]
  ];

  const violations = [];
  for (const [label, text] of [
    ["description", description],
    ["review notes", reviewNotes]
  ]) {
    let remainder = text;
    for (const denial of denials[label]) {
      assert.ok(
        remainder.includes(denial),
        `${label} no longer states the exclusion: ${denial}`
      );
      remainder = remainder.replace(denial, "");
    }
    for (const [pattern, promise] of forbidden) {
      if (pattern.test(remainder)) {
        violations.push(`${label}: ${promise}`);
      }
    }
  }

  assert.deepEqual(violations, []);

  // Apple caps Notes for Review at 4,000 bytes, and the bracketed fields still
  // have to grow into whatever is left.
  const noteBytes = Buffer.byteLength(reviewNotes, "utf8");
  assert.ok(
    noteBytes <= 3_850,
    `App Review notes are ${noteBytes} bytes; keep them under 3,850 so the filled-in credentials and video URL still fit Apple's 4,000-byte field`
  );
  assert.match(reviewNotes, /\[STABLE HTTPS URL, NO LOGIN\]/);
});

test("the demo seeder only creates sessions the app can still record", async () => {
  const seeder = await source("demoSeed");

  for (const [pattern, retiredSource] of [
    [/source:\s*"manual"/, "manual"],
    [/source:\s*"apple_health"/, "apple_health"]
  ]) {
    assert.doesNotMatch(
      seeder,
      pattern,
      `seed-demo-user.mjs still seeds a ${retiredSource} workout, a source #437 removed from the app on 2026-08-08`
    );
  }
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
  assert.match(
    outwardCopy,
    /does not import workouts from Apple Health or any other app/i
  );
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

test("post-import-removal HealthKit disclosures match the real enrichment read set", async () => {
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

  // Since #437 (merged 2026-08-08) HealthKitAuthorizationClient.readTypes is
  // exactly {heartRate, activeEnergyBurned}, AppleHealthEnrichmentCoordinator
  // reads the climb's own unpadded window, and HKWorkout is never touched.
  // Naming anything wider is a false disclosure in a legal page, so these
  // patterns guard against resurrecting the pre-#437 read set.
  const forbiddenClaims = [
    [/step count/i, "claims a step-count read that #437 removed"],
    [/resting energy/i, "claims a resting-energy read that #437 removed"],
    [/average METs/i, "claims a METs attachment that came from HKWorkout"],
    [
      /matching Apple Health workout|workout entries/i,
      "claims Ascend matches Apple Health workout entries, which #437 removed"
    ],
    [
      /lists Workouts in the Health permission sheet/i,
      "claims the permission sheet shows Workouts, which it no longer does"
    ],
    [
      /(imports?|importing) (?:supported )?workouts? from Apple Health(?! or any other app, and it does not| into)/i,
      "reads as a promise to import Apple Health workouts"
    ]
  ];

  // The two types Ascend actually asks for, and the window it reads them over.
  // Prose spells them out; CLAUDE.md names the HealthKit identifiers directly.
  const requiredDisclosures = [
    [/heart[- ]rate|heartRate/i, "the heart-rate read"],
    [/active[- ]energy|activeEnergyBurned/i, "the active-energy read"],
    [/own time window|time window of a climb/i, "the session-window bound"]
  ];
  const violations = [];

  for (const [label, disclosure] of healthKitDisclosures) {
    for (const [pattern, description] of forbiddenClaims) {
      if (pattern.test(disclosure)) {
        violations.push(`${label}: ${description}`);
      }
    }
    for (const [pattern, description] of requiredDisclosures) {
      if (!pattern.test(disclosure)) {
        violations.push(`${label}: does not disclose ${description}`);
      }
    }
  }

  assert.deepEqual(violations, []);
});
