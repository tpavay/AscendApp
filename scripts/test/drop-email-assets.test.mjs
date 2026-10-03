import test from "node:test";
import assert from "node:assert/strict";

import {
  checkDropEmailAssets,
  hashedName,
  plannedAssets,
} from "../build-drop-email-assets.mjs";

test("published drop pictures and their name map match the sources", () => {
  // A picture added, edited or removed without rerunning
  // `node scripts/build-drop-email-assets.mjs` fails here, so a changed
  // picture can never be served under a name a mailbox already cached.
  assert.deepEqual(checkDropEmailAssets(), []);
  assert.ok(plannedAssets().length > 0);
});

test("a changed picture always gets a new name", () => {
  const before = hashedName("hero.jpg", Buffer.from("one"));
  const after = hashedName("hero.jpg", Buffer.from("two"));
  assert.match(before, /^hero-[0-9a-f]{12}\.jpg$/);
  assert.notEqual(before, after);
  assert.equal(hashedName("hero.jpg", Buffer.from("one")), before);
});
