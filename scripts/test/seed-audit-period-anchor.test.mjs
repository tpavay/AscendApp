import assert from "node:assert/strict";
import test from "node:test";
import {
  PROFILE_SEED_PERSONAS,
  buildLeaderboardSeedWrites,
  buildProfileSeedWrites,
  expectedLeaderboardDocIds,
  seedAsOfInstant,
} from "../seed/fixtures/profile-fixtures.mjs";

const BEFORE_MIDNIGHT = new Date("2026-08-06T23:59:30.000Z");
const AFTER_MIDNIGHT = new Date("2026-08-07T00:00:30.000Z");

const Timestamp = {
  fromDate: (date) => ({toMillis: () => date.getTime(), toDate: () => date}),
};
const FieldValue = {serverTimestamp: () => "server-timestamp"};

function fakeSeedFirestore() {
  const collectionAt = (path) => ({
    doc: (documentId) => documentAt(`${path}/${documentId}`),
  });
  const documentAt = (path) => ({
    path,
    collection: (collectionId) => collectionAt(`${path}/${collectionId}`),
  });
  return {collection: collectionAt};
}

function publishedJoinedAt(now) {
  return new Map(
    buildProfileSeedWrites({
      db: fakeSeedFirestore(),
      catalog: new Map(),
      Timestamp,
      FieldValue,
      now,
      includeLeaderboardRows: false,
    })
      .filter((entry) => entry.shape === "publicProfile")
      .map((entry) => [entry.data.userId, entry.data.joined_at])
  );
}

function seededLeaderboardDocIds(now) {
  const publicIdentities = new Map(
    PROFILE_SEED_PERSONAS.map((persona) => [
      persona.id,
      {
        displayName: persona.name,
        identityChangedAt: "server-timestamp",
        identityPolicyVersion: 1,
        photoURL: "",
        userId: persona.id,
      },
    ])
  );

  return buildLeaderboardSeedWrites({
    db: fakeSeedFirestore(),
    catalog: new Map(),
    Timestamp,
    FieldValue,
    publicIdentities,
    now,
  }).map((entry) => entry.ref.path.split("/").at(-1));
}

test("a published pack carries the instant it was seeded", () => {
  assert.deepEqual(
    seedAsOfInstant(publishedJoinedAt(BEFORE_MIDNIGHT)),
    BEFORE_MIDNIGHT
  );
});

test("a pack seeded before UTC midnight still audits after it", () => {
  const seeded = seededLeaderboardDocIds(BEFORE_MIDNIGHT);
  const recovered = seedAsOfInstant(publishedJoinedAt(BEFORE_MIDNIGHT));
  const expected = new Set(expectedLeaderboardDocIds(recovered));

  assert.ok(seeded.length > 0);
  for (const docId of seeded) {
    assert.ok(expected.has(docId), `${docId} is not an expected seeded row`);
  }

  // The clock the audit itself runs on is exactly what used to report every
  // daily row as missing once the day rolled over.
  const auditClock = new Set(expectedLeaderboardDocIds(AFTER_MIDNIGHT));
  assert.ok(seeded.some((docId) => !auditClock.has(docId)));
});

test("a pack with no published identity leaves the anchor unresolved", () => {
  assert.equal(seedAsOfInstant(new Map()), null);
});
