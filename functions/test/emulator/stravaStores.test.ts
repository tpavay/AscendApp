/**
 * The Strava adapters against real Firestore.
 *
 * Unit tests prove the queue's decisions with in-memory ports. This suite
 * proves the shipped transactions: a climb is queued once however often its
 * workout is rewritten, a claim can be held by one run only, a rotated
 * refresh token is never overwritten by a stale one, and disconnecting
 * leaves no Strava record behind.
 */

import assert from "node:assert/strict";
import test, {before, beforeEach} from "node:test";
import * as admin from "firebase-admin";
import {
  STRAVA_CONNECTIONS_COLLECTION,
  STRAVA_OAUTH_STATES_COLLECTION,
  STRAVA_UPLOAD_JOBS_COLLECTION,
} from "../../src/strava/access.js";
import {
  StravaApiError,
  type StravaClient,
  type StravaTokenGrant,
} from "../../src/strava/api.js";
import {
  StravaConnectionStore,
  type StravaConnection,
} from "../../src/strava/connections.js";
import {
  consumeStravaOAuthState,
  saveStravaOAuthState,
  sweepExpiredStravaOAuthStates,
} from "../../src/strava/oauth.js";
import {
  enqueueStravaUpload,
  FirestoreStravaUploadJobStore,
  FirestoreStravaWorkoutSource,
  STRAVA_UPLOAD_JOB_RETENTION_MS,
} from "../../src/strava/uploadJobStore.js";
import {stravaUploadJobId} from "../../src/strava/uploadProcessor.js";
import {handleStravaDeauthorization} from "../../src/strava/webhook.js";

const NOW = new Date("2026-09-29T12:00:00.000Z");
const uid = "strava-climber-1";
let db: admin.firestore.Firestore;

before(() => {
  assert.ok(
    process.env.FIRESTORE_EMULATOR_HOST,
    "FIRESTORE_EMULATOR_HOST is unset - run this through npm run test:emulator"
  );
  if (admin.apps.length === 0) {
    admin.initializeApp({projectId: "demo-ascend-leaderboard-derivation"});
  }
  db = admin.firestore();
});

beforeEach(async () => {
  for (const collection of [
    STRAVA_CONNECTIONS_COLLECTION,
    STRAVA_OAUTH_STATES_COLLECTION,
    STRAVA_UPLOAD_JOBS_COLLECTION,
    `users/${uid}/workouts`,
  ]) {
    const snapshot = await db.collection(collection).get();
    await Promise.all(snapshot.docs.map((document) => document.ref.delete()));
  }
});

/**
 * A connection whose token expires at the given time.
 * @param {number} expiresAtMillis Token expiry.
 * @return {StravaConnection} The connection.
 */
function connection(expiresAtMillis: number): StravaConnection {
  return {
    userId: uid,
    athleteId: "987",
    athleteDisplayName: "Elias M.",
    accessToken: "access-1",
    refreshToken: "refresh-1",
    expiresAtMillis,
    scopes: ["activity:write"],
    connectedAtMillis: NOW.getTime(),
  };
}

/**
 * A Strava client whose refresh is scripted.
 * @param {Function} refresh Refresh behaviour.
 * @param {Array<string>} revoked Collects revoked tokens.
 * @return {StravaClient} The client.
 */
function client(
  refresh: (token: string) => Promise<StravaTokenGrant>,
  revoked: string[] = []
): StravaClient {
  return {
    exchangeCode: async () => {
      throw new Error("unused");
    },
    refresh,
    revoke: async (token) => {
      revoked.push(token);
    },
    createUpload: async () => {
      throw new Error("unused");
    },
    getUpload: async () => {
      throw new Error("unused");
    },
  };
}

test("a climb is queued once, however often its workout is rewritten",
  async () => {
    const job = {
      jobId: stravaUploadJobId(uid, "w1"),
      userId: uid,
      workoutId: "w1",
      readyAt: NOW,
    };
    assert.equal(await enqueueStravaUpload(db, job), true);
    assert.equal(await enqueueStravaUpload(db, job), false);
    const rows = await db.collection(STRAVA_UPLOAD_JOBS_COLLECTION).get();
    assert.equal(rows.size, 1);
    assert.equal(rows.docs[0].get("status"), "queued");
  });

test("a queued climb is claimed by exactly one run", async () => {
  await enqueueStravaUpload(db, {
    jobId: stravaUploadJobId(uid, "w1"),
    userId: uid,
    workoutId: "w1",
    readyAt: NOW,
  });
  const store = new FirestoreStravaUploadJobStore(db);

  const [first, second] = await Promise.all([
    store.claimDue(NOW, 10),
    store.claimDue(NOW, 10),
  ]);

  assert.equal(first.length + second.length, 1);
  const claim = [...first, ...second][0];
  assert.equal(claim.attemptCount, 1);
  assert.equal(claim.uploadId, null);
});

test("an upload id survives a requeue, and a refunded attempt is not spent",
  async () => {
    await enqueueStravaUpload(db, {
      jobId: stravaUploadJobId(uid, "w1"),
      userId: uid,
      workoutId: "w1",
      readyAt: NOW,
    });
    const store = new FirestoreStravaUploadJobStore(db);
    const [claim] = await store.claimDue(NOW, 10);

    await store.requeue(claim, {
      readyAt: NOW,
      errorCode: "rate_limited",
      uploadId: "u-1",
      refundAttempt: true,
    }, NOW);

    const [again] = await store.claimDue(NOW, 10);
    assert.equal(again.uploadId, "u-1");
    assert.equal(again.attemptCount, 1);

    await store.markUploaded(again, "a-1", false, NOW);
    const row = await db.doc(
      `${STRAVA_UPLOAD_JOBS_COLLECTION}/${claim.jobId}`
    ).get();
    assert.equal(row.get("status"), "uploaded");
    assert.equal(row.get("activityId"), "a-1");
    assert.equal(
      row.get("retainUntil").toMillis(),
      NOW.getTime() + STRAVA_UPLOAD_JOB_RETENTION_MS
    );
  });

test("a stale claim cannot overwrite a newer one", async () => {
  await enqueueStravaUpload(db, {
    jobId: stravaUploadJobId(uid, "w1"),
    userId: uid,
    workoutId: "w1",
    readyAt: NOW,
  });
  const store = new FirestoreStravaUploadJobStore(db);
  const [stale] = await store.claimDue(NOW, 10);
  const later = new Date(NOW.getTime() + 11 * 60 * 1000);

  assert.equal(await store.reclaimStale(later, 10), 1);
  const [fresh] = await store.claimDue(later, 10);
  await store.markFailed(stale, "late", later);

  const row = await db.doc(
    `${STRAVA_UPLOAD_JOBS_COLLECTION}/${fresh.jobId}`
  ).get();
  assert.equal(row.get("status"), "processing");
  assert.equal(row.get("claimId"), fresh.claimId);
});

test("a fresh token is used as stored, an expiring one is rotated",
  async () => {
    const store = new StravaConnectionStore(db);
    await store.save(connection(NOW.getTime() + 3 * 60 * 60 * 1000));
    const refreshed: string[] = [];
    const strava = client(async (token) => {
      refreshed.push(token);
      return {
        accessToken: "access-2",
        refreshToken: "refresh-2",
        expiresAtMillis: NOW.getTime() + 6 * 60 * 60 * 1000,
      };
    });

    assert.equal(
      await store.validAccessToken(uid, strava, NOW.getTime()),
      "access-1"
    );
    assert.deepEqual(refreshed, []);

    const nearExpiry = NOW.getTime() + 3 * 60 * 60 * 1000 - 10 * 60 * 1000;
    assert.equal(
      await store.validAccessToken(uid, strava, nearExpiry),
      "access-2"
    );
    assert.deepEqual(refreshed, ["refresh-1"]);
    assert.equal((await store.read(uid))?.refreshToken, "refresh-2");
  });

test("a refresh that lost the rotation race uses the winner's token",
  async () => {
    const store = new StravaConnectionStore(db);
    await store.save(connection(NOW.getTime()));
    const strava = client(async () => {
      // Another caller rotates the token while this refresh is in flight,
      // and Strava refuses the now-dead refresh token.
      await db.doc(`${STRAVA_CONNECTIONS_COLLECTION}/${uid}`).update({
        accessToken: "access-winner",
        refreshToken: "refresh-winner",
      });
      throw new StravaApiError("unauthorized", 400, "invalid refresh");
    });

    assert.equal(
      await store.validAccessToken(uid, strava, NOW.getTime()),
      "access-winner"
    );
  });

test("disconnecting revokes at Strava and leaves nothing behind", async () => {
  const store = new StravaConnectionStore(db);
  await store.save(connection(NOW.getTime()));
  await saveStravaOAuthState(db, uid, "state-token-0123456789", NOW);
  await enqueueStravaUpload(db, {
    jobId: stravaUploadJobId(uid, "w1"),
    userId: uid,
    workoutId: "w1",
    readyAt: NOW,
  });
  await enqueueStravaUpload(db, {
    jobId: stravaUploadJobId("someone-else", "w9"),
    userId: "someone-else",
    workoutId: "w9",
    readyAt: NOW,
  });
  const revoked: string[] = [];

  const outcome = await store.disconnect(uid, client(async () => {
    throw new Error("unused");
  }, revoked));

  assert.deepEqual(outcome, {revoked: true, deleted: 3});
  assert.deepEqual(revoked, ["refresh-1"]);
  assert.equal(await store.read(uid), null);
  const jobs = await db.collection(STRAVA_UPLOAD_JOBS_COLLECTION).get();
  assert.deepEqual(jobs.docs.map((document) => document.get("userId")),
    ["someone-else"]);
});

test("a Strava outage never blocks a disconnect", async () => {
  const store = new StravaConnectionStore(db);
  await store.save(connection(NOW.getTime()));
  const failing: StravaClient = {
    ...client(async () => {
      throw new Error("unused");
    }),
    revoke: async () => {
      throw new StravaApiError("transient", 503, "down");
    },
  };

  const outcome = await store.disconnect(uid, failing);

  assert.equal(outcome.revoked, false);
  assert.equal(await store.read(uid), null);
});

test("a pending connection is consumed once, and only by its climber",
  async () => {
    await saveStravaOAuthState(db, uid, "state-token-0123456789", NOW);

    assert.equal(
      await consumeStravaOAuthState(db, "intruder", "state-token-0123456789",
        NOW),
      "wrong_user"
    );
    assert.equal(
      await consumeStravaOAuthState(db, uid, "state-token-0123456789", NOW),
      "missing"
    );

    await saveStravaOAuthState(db, uid, "state-token-abcdefghij", NOW);
    assert.equal(
      await consumeStravaOAuthState(db, uid, "state-token-abcdefghij", NOW),
      "valid"
    );

    await saveStravaOAuthState(db, uid, "state-token-expired0000",
      new Date(NOW.getTime() - 60 * 60 * 1000));
    assert.equal(await sweepExpiredStravaOAuthStates(db, NOW), 1);
  });

test("a deauthorization is honoured only once Strava confirms it",
  async () => {
    const store = new StravaConnectionStore(db);
    await store.save(connection(NOW.getTime() + 6 * 60 * 60 * 1000));
    const live = client(async () => ({
      accessToken: "access-1",
      refreshToken: "refresh-1",
      expiresAtMillis: NOW.getTime() + 6 * 60 * 60 * 1000,
    }));

    assert.equal(await handleStravaDeauthorization("987", store, live), 0);
    assert.notEqual(await store.read(uid), null);

    const revoked = client(async () => {
      throw new StravaApiError("unauthorized", 400, "invalid refresh");
    });
    assert.equal(await handleStravaDeauthorization("987", store, revoked), 1);
    assert.equal(await store.read(uid), null);
  });

test("a deauthorization Strava cannot confirm keeps the connection",
  async () => {
    const store = new StravaConnectionStore(db);
    await store.save(connection(NOW.getTime() + 6 * 60 * 60 * 1000));
    const misconfigured = client(async () => {
      throw new StravaApiError("misconfigured", 400, "bad client secret");
    });

    await assert.rejects(
      handleStravaDeauthorization("987", store, misconfigured),
      (error: unknown) =>
        error instanceof StravaApiError && error.kind === "misconfigured"
    );
    assert.notEqual(await store.read(uid), null);
  });

test("the uploaded climb is read from the canonical workout", async () => {
  await db.doc(`users/${uid}/workouts/w1`).set({
    name: "Burj Khalifa",
    startedAt: admin.firestore.Timestamp.fromDate(NOW),
    durationSeconds: 1800,
    steps: 2909,
    floors: 163,
    notes: "",
    source: "headphone_motion",
    avgHeartRateBpm: 160,
  });
  const source = new FirestoreStravaWorkoutSource(db, () => {
    throw new Error("no sidecar is referenced, so storage is never touched");
  });

  const result = await source.read(uid, "w1");

  assert.equal(result?.workout.name, "Burj Khalifa");
  assert.equal(result?.workout.avgHeartRateBpm, 160);
  assert.equal(result?.workout.caloriesBurned, null);
  assert.deepEqual(result?.heartRate, []);
  assert.equal(await source.read(uid, "missing"), null);
});
