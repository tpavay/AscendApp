import assert from "node:assert/strict";
import {test} from "node:test";
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";

import {
  ACTIVE_CLIMBS,
  RACEABLE_RELEASE_STATE,
  WARM_CLIMBS,
  contestedClimbIds,
  firstAscentOpenConfigs,
} from "../seed/lib/live-replay-climb-tiers.mjs";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../..");

function catalog() {
  const raw = JSON.parse(readFileSync(
    resolve(REPO_ROOT, "web/public/climbs/catalog-v1.json"),
    "utf-8"
  ));
  const climbs = Array.isArray(raw) ? raw : raw.climbs;
  return new Map(climbs.map((climb) => [climb.id, climb]));
}

test("every contested climb is in the catalog and raceable", () => {
  const climbs = catalog();
  for (const config of [...ACTIVE_CLIMBS, ...WARM_CLIMBS]) {
    const climb = climbs.get(config.id);
    assert.ok(climb, `${config.id} is not in the climb catalog`);
    assert.equal(
      climb.releaseState,
      RACEABLE_RELEASE_STATE,
      `${config.id} is seeded with competitors but cannot be raced`
    );
  }
});

test("no climb is both contested and left open", () => {
  const contested = contestedClimbIds();
  const open = firstAscentOpenConfigs(catalog(), contested);

  for (const config of open) {
    assert.equal(
      contested.has(config.id),
      false,
      `${config.id} is seeded both ways, so whichever write lands last decides it`
    );
  }
});

// The point of the split. A contested board's First Ascent is spent for good, so
// the only thing standing between seeding and a catalog with nothing left to
// claim is how many climbs the pack contests.
test("the seed leaves most of the raceable catalog claimable", () => {
  const climbs = catalog();
  const contested = contestedClimbIds();
  const open = firstAscentOpenConfigs(climbs, contested);
  const raceable = Array.from(climbs.values())
    .filter((climb) => climb.releaseState === RACEABLE_RELEASE_STATE);

  assert.equal(open.length + contested.size, raceable.length);
  assert.ok(
    open.length > contested.size,
    `${open.length} claimable vs ${contested.size} contested: seeding is ` +
    "spending more First Ascents than it leaves"
  );
});

test("an open climb is seeded with no completions, so its slot is claimable", () => {
  for (const config of firstAscentOpenConfigs(catalog(), contestedClimbIds())) {
    assert.equal(config.totalClimbers, 0);
    assert.equal(config.replayEntries, 0);
    assert.equal(config.completionRate, 0);
  }
});

// `ProfileFirstAscentService` fills its open list in catalog order and caps it at
// four, so widening the open set changes which climbs the profile previews. These
// four are the ones QA and content capture have been using.
test("the profile's open preview still leads with the same four climbs", () => {
  const open = firstAscentOpenConfigs(catalog(), contestedClimbIds());

  assert.deepEqual(open.slice(0, 4).map((config) => config.id), [
    "el-penon-de-guatape",
    "oriental-pearl-tower",
    "charminar",
    "sky-tower-auckland",
  ]);
});

test("the demo account claims a First Ascent no competitor has spent", () => {
  const source = readFileSync(
    resolve(REPO_ROOT, "scripts/seed-demo-user.mjs"),
    "utf-8"
  );
  const match = source.match(
    /const DEFAULT_FIRST_ASCENT_CLIMB_ID = "([a-z0-9-]+)";/
  );

  assert.ok(match, "seed-demo-user no longer declares a default First Ascent climb");
  assert.equal(contestedClimbIds().has(match[1]), false);
  assert.equal(catalog().get(match[1])?.releaseState, RACEABLE_RELEASE_STATE);
});

// seed-demo-user merges its completions into the same summary this pack owns,
// but only claims the slot for its one --first-ascent-climb. A climb it
// completes that neither the pack contests nor the account claims lands with
// completions and no holder - the state the app can never produce or leave.
test("every climb the demo account completes ends with a First Ascent holder", () => {
  const source = readFileSync(
    resolve(REPO_ROOT, "scripts/seed-demo-user.mjs"),
    "utf-8"
  );
  const specs = source.slice(
    source.indexOf("const LIVE_CLIMB_SPECS = ["),
    source.indexOf("const EXTRA_WORKOUT_SPECS = [")
  );
  const demoClimbIds = [...specs.matchAll(/climbId: "([a-z0-9-]+)"/g)]
    .map((match) => match[1]);
  const demoFirstAscentClimbId = source.match(
    /const DEFAULT_FIRST_ASCENT_CLIMB_ID = "([a-z0-9-]+)";/
  )?.[1];

  assert.ok(demoClimbIds.length > 0, "expected demo account live climb specs");
  assert.ok(demoFirstAscentClimbId, "expected a default First Ascent climb");

  const contested = contestedClimbIds();
  for (const climbId of demoClimbIds) {
    assert.ok(
      contested.has(climbId) || climbId === demoFirstAscentClimbId,
      `${climbId} takes a demo completion but nothing seeds it a First Ascent holder`
    );
  }
});

// The specs list is the only place the account's First Ascent climb can be
// completed from, and a holder without a completion is the other dead state.
test("the demo account actually climbs the First Ascent it claims", () => {
  const source = readFileSync(
    resolve(REPO_ROOT, "scripts/seed-demo-user.mjs"),
    "utf-8"
  );
  const demoFirstAscentClimbId = source.match(
    /const DEFAULT_FIRST_ASCENT_CLIMB_ID = "([a-z0-9-]+)";/
  )?.[1];

  assert.match(
    source.slice(
      source.indexOf("const LIVE_CLIMB_SPECS = ["),
      source.indexOf("const EXTRA_WORKOUT_SPECS = [")
    ),
    new RegExp(`climbId: DEFAULT_FIRST_ASCENT_CLIMB_ID|climbId: "${demoFirstAscentClimbId}"`)
  );
});
