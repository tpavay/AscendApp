import assert from "node:assert/strict";
import {test} from "node:test";
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";

import {PROFILE_SEED_PERSONAS} from "../seed/fixtures/profile-fixtures.mjs";
import {unphotographableDisplayName} from "../seed/lib/content-ready-contract.mjs";
import {isAllowedDisplayName} from "../seed/lib/public-identity-contract.mjs";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../..");

/**
 * Reads the seeded competitor names out of the seed script.
 *
 * The list is a private constant in a script with no exports, and pulling it out
 * by hand into a fixture would create a second copy that drifts. What matters is
 * the list the seed actually writes.
 * @return {string[]} Seeded competitor display names, in order.
 */
function seededDisplayNames() {
  const source = readFileSync(
    resolve(REPO_ROOT, "scripts/seed-live-replay-leaderboards.mjs"),
    "utf8"
  );
  const block = source.match(/const SEEDED_DISPLAY_NAMES = \[([\s\S]*?)\n\];/)?.[1];
  assert.ok(block, "could not locate SEEDED_DISPLAY_NAMES in the seed script");
  return [...block.matchAll(/"([^"]+)"/g)].map((match) => match[1]);
}

const SEEDED = seededDisplayNames();
const PERSONAS = PROFILE_SEED_PERSONAS.map((persona) => persona.name);

test("every seeded name is one the server would publish", () => {
  for (const name of [...SEEDED, ...PERSONAS]) {
    assert.ok(isAllowedDisplayName(name), `${name} fails the shared display-name screening`);
  }
});

// A leaderboard row is the product's shop window. "Sarah K." is not a name the
// product can produce - `SuppliedNameAdoption` publishes the given and family
// name a sign-in supplies - so an abbreviated fixture reads as fixture data
// beside a real row, which is what a podium showed.
test("no seeded name is fit only for a fixture", () => {
  for (const name of [...SEEDED, ...PERSONAS]) {
    assert.equal(unphotographableDisplayName(name), null, `${name} is not fit to photograph`);
  }
});

test("every seeded name is distinct, so no board shows one climber twice", () => {
  const all = [...SEEDED, ...PERSONAS].map((name) => name.toLowerCase());
  const duplicates = all.filter((name, index) => all.indexOf(name) !== index);
  assert.deepEqual(duplicates, []);
});

// Two climbers called Sarah on one board is a coincidence; a "Tyler R." next to
// the capture account's "Tyler Pavay" is a fixture wearing the captain's name.
test("no two seeded climbers share a first name", () => {
  const firstNames = [...SEEDED, ...PERSONAS].map((name) => name.split(" ")[0].toLowerCase());
  const duplicates = firstNames.filter((name, index) => firstNames.indexOf(name) !== index);
  assert.deepEqual(duplicates, []);
});

// `avatarURLForDisplayName` resolves a face by a name's position in this list,
// and `displayNameForAttempt` falls back to "Climber 061" past its end. Both
// failures are invisible until they are on a screenshot.
test("the competitor name list is the size the avatar pool expects", () => {
  assert.equal(SEEDED.length, 82);
});
