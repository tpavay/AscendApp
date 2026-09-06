import assert from "node:assert/strict";
import {test} from "node:test";

import {
  REPAIR_DISPLAY_NAMES,
  planIdentityRepair,
  repairNameFor,
} from "../lib/staging-identity-repair.mjs";
import {PROFILE_SEED_PERSONAS} from "../seed/fixtures/profile-fixtures.mjs";
import {isAllowedDisplayName} from "../seed/lib/public-identity-contract.mjs";
import {unphotographableDisplayName} from "../seed/lib/content-ready-contract.mjs";

const PHOTO = "https://firebasestorage.googleapis.com/v0/b/ascend-staging-fa7d5.firebasestorage.app/o/x.jpg";

test("every repair name is one the server would publish and a camera would believe", () => {
  for (const name of REPAIR_DISPLAY_NAMES) {
    assert.ok(isAllowedDisplayName(name), `${name} fails the shared screening`);
    assert.equal(unphotographableDisplayName(name), null, `${name} is not fit to photograph`);
  }
  assert.equal(new Set(REPAIR_DISPLAY_NAMES).size, REPAIR_DISPLAY_NAMES.length);
});

// The repair pool stands on the same boards as the seeded climbers, and a
// repeated name reads as one person posting twice.
test("no repair name collides with a seeded persona", () => {
  const personas = new Set(PROFILE_SEED_PERSONAS.map((persona) => persona.name.toLowerCase()));
  for (const name of REPAIR_DISPLAY_NAMES) {
    assert.ok(!personas.has(name.toLowerCase()), `${name} is already a persona`);
  }
});

test("an account keeps the same name across runs, so who is who does not shuffle", () => {
  const taken = new Set();
  assert.equal(repairNameFor("uid-a", taken), repairNameFor("uid-a", new Set()));
  assert.notEqual(repairNameFor("uid-a", new Set()), repairNameFor("uid-b", new Set()));
});

test("a real climber's own name is never taken away", () => {
  const {renames} = planIdentityRepair([
    {uid: "real", displayName: "Bryce", photoURL: PHOTO},
    {uid: "other", displayName: "Tyler Pavay", photoURL: PHOTO},
  ], {protectedUid: "capture"});

  assert.deepEqual(renames, []);
});

test("placeholder and machine-shaped names are the ones repaired", () => {
  const {renames} = planIdentityRepair([
    {uid: "a", displayName: "CHANGE ME", photoURL: PHOTO},
    {uid: "b", displayName: "Content Capture", photoURL: PHOTO},
    {uid: "c", displayName: "Climber 6J84R7", photoURL: PHOTO},
    {uid: "d", displayName: null, photoURL: PHOTO},
    {uid: "keep", displayName: "Marisol Del Rio", photoURL: PHOTO},
  ], {protectedUid: "capture"});

  assert.deepEqual(renames.map((rename) => rename.uid), ["a", "b", "c", "d"]);
  assert.equal(new Set(renames.map((rename) => rename.to)).size, 4, "two accounts took the same name");
  for (const rename of renames) {
    assert.equal(unphotographableDisplayName(rename.to), null);
  }
});

test("a repaired name never collides with one already standing on the boards", () => {
  const {renames} = planIdentityRepair([
    ...REPAIR_DISPLAY_NAMES.slice(0, 3).map((name, index) => ({
      uid: `holder-${index}`,
      displayName: name,
      photoURL: PHOTO,
    })),
    {uid: "broken", displayName: "CHANGE ME", photoURL: PHOTO},
  ], {protectedUid: "capture"});

  assert.equal(renames.length, 1);
  assert.ok(!REPAIR_DISPLAY_NAMES.slice(0, 3).includes(renames[0].to));
});

// The capture account has its own contract check, and its name is the captain's
// own. Renaming it would be the repair overwriting the thing it exists to frame.
test("the account being captured is never renamed", () => {
  const {renames} = planIdentityRepair([
    {uid: "capture", displayName: "CHANGE ME", photoURL: PHOTO},
  ], {protectedUid: "capture"});

  assert.deepEqual(renames, []);
});

// A rename here would fix the board until the next seed wrote the fixture name
// straight back. A repair that has to be re-run to stay true is not a repair.
test("a fixture-owned identity fails the run rather than being renamed", () => {
  const {renames, seedOwnedFailures} = planIdentityRepair([
    {uid: "profile_tied_gold", displayName: "Mateo G.", photoURL: PHOTO},
  ], {protectedUid: "capture", seedOwnedUids: new Set(["profile_tied_gold"])});

  assert.deepEqual(renames, []);
  assert.equal(seedOwnedFailures.length, 1);
  assert.equal(seedOwnedFailures[0].uid, "profile_tied_gold");
  assert.match(seedOwnedFailures[0].reason, /initial for a surname/);
});

// A face has to be a picture somebody chose. The seed has one avatar per
// synthetic climber and one reserved for the capture account, with none spare.
test("a missing photo is reported, never invented", () => {
  const {renames, photoless} = planIdentityRepair([
    {uid: "a", displayName: "Marisol Del Rio", photoURL: ""},
    {uid: "b", displayName: "Bryce", photoURL: PHOTO},
  ], {protectedUid: "capture"});

  assert.deepEqual(renames, []);
  assert.deepEqual(photoless, ["a"]);
});
