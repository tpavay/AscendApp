/**
 * Closed-board placings after they are frozen, against a real Firestore.
 *
 * A placing outlives the leaderboard_stats row it was copied from, so two
 * things keep it honest afterwards, and both reach it through a
 * collection-group query on `userId` that no unit test can exercise:
 *
 * - the `champion` identity-propagation kind, which pages a climber's placings
 *   across every result by document path, and
 * - account cleanup, which de-identifies them without re-ranking anything.
 *
 * Lives under test/emulator/ so `npm test` does not pick it up without a
 * Firestore behind it. `npm run test:emulator` runs it.
 */

import test, {before, beforeEach} from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {anonymizeLeaderboardPlacings} from "../../src/accountCleanup.js";
import {
  IdentityPropagationJob,
  identitySourceGeneration,
  processIdentityPropagationJob,
  publicIdentityPropagationTestHooks,
} from "../../src/publicIdentityPropagation.js";

const PROJECT_ID = "demo-ascend-leaderboard-derivation";
const CHAMPION = "champ";
const RIVAL = "rival";
const OLD_CHANGED_AT = admin.firestore.Timestamp.fromDate(
  new Date("2026-04-09T12:00:00.000Z")
);
const NEW_CHANGED_AT = admin.firestore.Timestamp.fromDate(
  new Date("2026-09-20T12:00:00.000Z")
);
const RESULT_IDS = [
  "weekly_2026-W37",
  "weekly_2026-W38",
  "monthly_2026-M08",
  "yearly_2025",
];

let db: admin.firestore.Firestore;

before(() => {
  assert.ok(
    process.env.FIRESTORE_EMULATOR_HOST,
    "FIRESTORE_EMULATOR_HOST is unset - run this through npm run test:emulator"
  );
  admin.initializeApp({projectId: PROJECT_ID});
  db = admin.firestore();
});

beforeEach(async () => {
  await clearFirestore();
  const batch = db.batch();
  for (const [index, resultId] of RESULT_IDS.entries()) {
    batch.set(placingRef(resultId, CHAMPION), placing(CHAMPION, index + 1));
    batch.set(placingRef(resultId, RIVAL), placing(RIVAL, index + 2));
  }
  // A seeded rival's frozen identity is content, not a stale copy.
  batch.set(placingRef("weekly_2026-W36", CHAMPION), {
    ...placing(CHAMPION, 1),
    displayName: "Seeded Legend",
    isSynthetic: true,
  });
  await batch.commit();
});

test("a new public name reaches every placing the climber holds",
  async () => {
    const profile = db.doc(`users/${CHAMPION}/public_profile/current`);
    await db.doc(`users/${CHAMPION}`).set({createdAt: OLD_CHANGED_AT});
    await profile.set({
      displayName: "Maya Chen",
      identityChangedAt: NEW_CHANGED_AT,
      identityPolicyVersion: 1,
      photoURL: "",
    });
    const snapshot = await profile.get();
    const jobRef = db.doc(
      `_public_identity_propagation_jobs/${CHAMPION}/kinds/champion`
    );
    await jobRef.set({
      complete: false,
      cursor: null,
      kind: "champion",
      sequence: 1,
      sourceDeliveryId: "delivery-1",
      sourceGeneration: identitySourceGeneration(snapshot.updateTime),
      sourceTransitionGeneration: "delivery-1",
      userId: CHAMPION,
    });

    // One placing per page, so the sweep has to resume across results by
    // document path - the cursor a collection-group ordering needs.
    let writes = 0;
    for (let page = 0; page < 10; page += 1) {
      const job = (await jobRef.get()).data() as IdentityPropagationJob;
      if (job.complete) {
        break;
      }
      writes += await processIdentityPropagationJob(
        job,
        publicIdentityPropagationTestHooks
          .firestoreIdentityPropagationJobPort(job),
        1
      );
    }

    assert.equal(writes, RESULT_IDS.length);
    assert.equal((await jobRef.get()).data()?.complete, true);
    for (const resultId of RESULT_IDS) {
      const stored = (await placingRef(resultId, CHAMPION).get()).data();
      assert.equal(stored?.displayName, "Maya Chen");
      assert.ok(stored?.identityChangedAt.isEqual(NEW_CHANGED_AT));
      assert.equal(stored?.identityState, "published");
      // Identity only: the frozen standing does not move.
      assert.equal(stored?.rank, RESULT_IDS.indexOf(resultId) + 1);
      assert.equal(stored?.totalSteps, 50_000);

      assert.equal(
        (await placingRef(resultId, RIVAL).get()).data()?.displayName,
        "Old rival"
      );
    }
    assert.equal(
      (await placingRef("weekly_2026-W36", CHAMPION).get()).data()
        ?.displayName,
      "Seeded Legend"
    );
  });

test("account cleanup de-identifies every placing and keeps every rank",
  async () => {
    const count = await anonymizeLeaderboardPlacings(db, CHAMPION, 2);

    // Four placings plus the seeded one, in three bounded pages.
    assert.equal(count, RESULT_IDS.length + 1);
    for (const [index, resultId] of RESULT_IDS.entries()) {
      const stored = (await placingRef(resultId, CHAMPION).get()).data();
      assert.deepEqual(
        {
          displayName: stored?.displayName,
          identityState: stored?.identityState,
          isSynthetic: stored?.isSynthetic,
          photoURL: stored?.photoURL,
        },
        {
          displayName: "Anonymous Climber",
          identityState: "deleted",
          isSynthetic: false,
          photoURL: "",
        }
      );
      // A champion who deletes their account stays champion.
      assert.equal(stored?.userId, CHAMPION);
      assert.equal(stored?.rank, index + 1);
      assert.equal(stored?.totalSteps, 50_000);
      assert.equal(stored?.totalWorkouts, 4);

      const rival = (await placingRef(resultId, RIVAL).get()).data();
      assert.equal(rival?.displayName, "Old rival");
      assert.equal(rival?.photoURL, "https://example.com/rival.jpg");
    }
  });

test("a de-identified placing is never restored by a later propagation",
  async () => {
    await anonymizeLeaderboardPlacings(db, CHAMPION);
    const profile = db.doc(`users/${CHAMPION}/public_profile/current`);
    await profile.set({
      displayName: "Back Again",
      identityChangedAt: NEW_CHANGED_AT,
      identityPolicyVersion: 1,
      photoURL: "",
    });
    const job: IdentityPropagationJob = {
      complete: false,
      cursor: null,
      kind: "champion",
      sequence: 1,
      sourceDeliveryId: "delivery-late",
      sourceGeneration: identitySourceGeneration((await profile.get())
        .updateTime),
      sourceTransitionGeneration: "delivery-late",
      userId: CHAMPION,
    };
    await db.doc(`_public_identity_propagation_jobs/${CHAMPION}/kinds/champion`)
      .set(job);

    const writes = await processIdentityPropagationJob(
      job,
      publicIdentityPropagationTestHooks.firestoreIdentityPropagationJobPort(
        job
      )
    );

    assert.equal(writes, 0);
    assert.equal(
      (await placingRef(RESULT_IDS[0], CHAMPION).get()).data()?.displayName,
      "Anonymous Climber"
    );
  });

function placingRef(
  resultId: string,
  userId: string
): admin.firestore.DocumentReference {
  return db.doc(`leaderboard_results/${resultId}/placings/${userId}`);
}

function placing(userId: string, rank: number): Record<string, unknown> {
  return {
    displayName: userId === CHAMPION ? "Old champ" : "Old rival",
    identityChangedAt: OLD_CHANGED_AT,
    identityPolicyVersion: 1,
    identityState: "published",
    isSynthetic: false,
    periodKey: "2026-W38",
    periodStartAt: admin.firestore.Timestamp.fromDate(
      new Date("2026-09-14T00:00:00.000Z")
    ),
    photoURL: userId === CHAMPION ?
      "https://example.com/champ.jpg" :
      "https://example.com/rival.jpg",
    rank,
    schemaVersion: 1,
    timeFrame: "weekly",
    totalSteps: 50_000,
    totalWorkouts: 4,
    userId,
  };
}

async function clearFirestore(): Promise<void> {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  const response = await fetch(
    `http://${host}/emulator/v1/projects/${PROJECT_ID}` +
      "/databases/(default)/documents",
    {method: "DELETE"}
  );
  assert.ok(response.ok, `emulator reset failed: ${response.status}`);
}
