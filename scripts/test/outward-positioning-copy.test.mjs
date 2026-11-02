import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));
const pathFromRoot = (...parts) => join(repositoryRoot, ...parts);

const sourcePaths = {
  home: pathFromRoot("web/src/pages/index.astro"),
  go: pathFromRoot("web/src/pages/go.astro"),
  support: pathFromRoot("web/src/pages/support.astro"),
  privacy: pathFromRoot("web/src/pages/privacy.astro"),
  terms: pathFromRoot("web/src/pages/terms.astro"),
  proposal: pathFromRoot("docs/app-store-ranked-repositioning-proposal.md"),
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

test("the App Store proposal pins the settled ranked metadata", async () => {
  const proposal = await source("proposal");
  const appName = textCodeBlockAfter(proposal, "App name");
  const subtitle = textCodeBlockAfter(proposal, "Subtitle");
  const keywords = textCodeBlockAfter(proposal, "Keywords");

  assert.equal(appName, "Ascend: Ranked Stair Stepper");
  assert.equal(subtitle, "Climb real towers from any gym");
  assert.equal([...appName].length, 28);
  assert.equal([...subtitle].length, 30);
  assert.equal(Buffer.byteLength(keywords, "utf8"), 99);
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

test("the proposed listing copy sells import and logging only as the second way to climb", async () => {
  const proposal = await source("proposal");
  const description = fencedBlockAfter(proposal, "Description");
  const reviewNotes = fencedBlockAfter(proposal, "App Review notes");

  // The live listing sold "Log stair-stepper workouts in Ascend or import
  // supported workouts from Apple Health" as the way the app works, and #437
  // removed both paths on 2026-08-08. Both returned in 1.3.0 as the second way
  // to climb: live headphone climbs stay first, and a climb Ascend did not
  // measure itself ranks only on a plausible pace. The copy has to say it in
  // that order and may not slide back into the tracker framing.
  for (const sentence of [
    "Live climbs with compatible AirPods or Beats are the main way to climb.",
    "Already climbed? Log a climb you did without a session, or bring in a stair stepper workout a watch or another app saved to Apple Health.",
    "A climb Ascend did not measure itself ranks only if its pace is plausible.",
    "Ascend reads from Apple Health and never writes to it."
  ]) {
    assert.ok(description.includes(sentence), `description no longer says: ${sentence}`);
  }
  assert.ok(
    description.indexOf("main way to climb") < description.indexOf("Already climbed?"),
    "the description must lead with live climbs, then the second way"
  );

  for (const [pattern, why] of [
    [/KEEP YOUR HISTORY TOGETHER/, "brings back the history-keeping section"],
    [/\btrack(s|ing|er)?\b/i, "uses tracker language outside its denial"],
    [/import (all|every|any) (of your )?workouts?/i, "promises importing every workout"]
  ]) {
    const remainder = description.replace(
      "It is not a generic activity tracker and it is not a social feed.",
      ""
    );
    assert.doesNotMatch(remainder, pattern, `description ${why}`);
  }

  // The reviewer has to be told how to reach both paths, and that neither is
  // reviewed by a person.
  for (const phrase of [
    "Log it",
    "Connect Health",
    "automatic pace check",
    "Ascend never writes to Health"
  ]) {
    assert.ok(reviewNotes.includes(phrase), `App Review notes no longer mention: ${phrase}`);
  }

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

  // `manual` returned in 1.3.0 (Log it) and `apple_health` with the import, so
  // both are sources the app records again. These three never were: no build
  // has ever set them, and `isValidWorkoutSource` in firestore.rules refuses them.
  for (const neverProduced of ["garmin", "fitbit", "hevy"]) {
    assert.doesNotMatch(
      seeder,
      new RegExp(`source:\\s*"${neverProduced}"`),
      `seed-demo-user.mjs seeds a ${neverProduced} workout, a source no build of the app has ever produced`
    );
  }
});

test("the public website consistently presents Ascend as ranked", async () => {
  const publicSources = await Promise.all([
    source("home"),
    source("go"),
    source("support"),
    source("privacy"),
    source("terms")
  ]);
  const outwardCopy = publicSources.join("\n").replace(/<[^>]+>/g, "");

  // Ranked, not racing, since the captain's repositioning on 2026-10-15: the
  // product is ranked stair stepper workouts, and every outward surface says so.
  assert.match(outwardCopy, /Ascend ranks stair stepper workouts\./);
  assert.match(outwardCopy, /Ranked stair stepper workouts\./);
  // The homepage the captain approved on 2026-10-01 leads with competition on the
  // machine itself, not with towers.
  assert.match(outwardCopy, /Compete on the stair stepper\./);
  assert.match(outwardCopy, /Ascend ranks every one of them against other climbers/);
  // Since 1.3.0 live climbs stay the main way to climb, and a climb done without
  // a session can be typed in or imported from Apple Health, ranking only on a
  // plausible pace.
  assert.match(outwardCopy, /Live climbs recorded in Ascend are the main way to climb/);
  assert.match(outwardCopy, /imported from Apple Health/i);
  assert.match(outwardCopy, /ranks it only if an automatic pace check finds its pace plausible/i);
  assert.doesNotMatch(outwardCopy, /does not import workouts/i);
  assert.doesNotMatch(outwardCopy, /does not accept manually entered workouts/i);

  for (const retiredCopy of [
    "Track the stair stepper like the workout it is",
    "fitness tracking and competition app",
    "helps you track stair-stepper workouts",
    "log sessions",
    "import supported workout data",
    // Read as "this is a running app" in the positioning review; the machine leads now.
    "Tower running, without the tower",
    // Racing was the positioning until 2026-10-15; "race" now names only the live run
    // against other climbers, never the product.
    "stair stepper racing app",
    "Stair Stepper Racing",
    "into a race against other climbers",
    "Race real towers",
    "Get back to racing",
    "a racing and fitness app",
    "You race other climbers"
  ]) {
    assert.doesNotMatch(outwardCopy, new RegExp(retiredCopy, "i"));
  }
});

test("the real HealthKit read set is the five types Ascend requests, read only", async () => {
  const client = await readFile(
    pathFromRoot("AscendApp/Shared/Services/HealthKitAuthorizationClient.swift"),
    "utf8"
  );
  const readTypes = sectionBetween(client, "var readTypes: Set<HKObjectType>", "var authorizationRequestStatus");
  const enrichmentTypes = sectionBetween(client, "var enrichmentReadTypes", "/// Everything Ascend asks Health for");

  // `enrichmentReadTypes` is the pair enrichment attaches to a live climb; the
  // full set adds what import reads off a workout.
  assert.match(enrichmentTypes, /\.heartRate/);
  assert.match(enrichmentTypes, /\.activeEnergyBurned/);
  assert.doesNotMatch(enrichmentTypes, /stepCount|workoutType|flightsClimbed/);
  assert.match(readTypes, /enrichmentReadTypes/);
  assert.match(readTypes, /HKObjectType\.workoutType\(\)/);
  assert.match(readTypes, /\.stepCount/);
  assert.match(readTypes, /\.flightsClimbed/);
  assert.doesNotMatch(readTypes, /basalEnergyBurned|appleExerciseTime|restingHeartRate/);
  assert.match(client, /requestAuthorization\(toShare: \[\]/, "Ascend must never request write access");
});

test("HealthKit disclosures match the real read set", async () => {
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
      sectionBetween(projectMemory, "- Not a tracker, and not an importer or a logger first.", "Full rationale:")
    ]
  ];

  // Naming anything wider than the five types in the client is a false
  // disclosure in a legal page, so these patterns guard against reads that
  // were never requested, and against promising more than stair workouts.
  const forbiddenClaims = [
    [/resting energy/i, "claims a resting-energy read Ascend does not request"],
    [/average METs/i, "claims a METs attachment that Ascend does not read"],
    [/lists Workouts in the Health permission sheet/i, "describes the permission sheet from before 1.3.0"],
    [
      /imports? (?:all|every|any) (?:of your )?workouts?/i,
      "promises importing every workout, when only stair stepper workouts are read"
    ],
    [/Ascend (?:also |then )?(?:writes?|saves?|adds?) [^.]{0,40}(?:to|into) (?:the )?Apple Health/i, "claims a write to Apple Health"]
  ];

  // The five types, the window the enrichment pair is read over, and that
  // Ascend never writes. Prose spells the types out; CLAUDE.md names the
  // HealthKit identifiers directly, so each pattern accepts either.
  const requiredDisclosures = [
    [/workouts?\b|workoutType/i, "the workouts read"],
    [/\bsteps?\b|stepCount/i, "the steps read"],
    [/flights climbed|flightsClimbed/i, "the flights-climbed read"],
    [/heart[- ]rate|heartRate/i, "the heart-rate read"],
    [/active[- ]energy|activeEnergyBurned/i, "the active-energy read"],
    [/own (?:time )?window|time window of a (?:climb|session)/i, "the session-window bound"],
    [/never writes|does not write|do not write|does not create or change anything/i, "that Ascend never writes to Apple Health"]
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
