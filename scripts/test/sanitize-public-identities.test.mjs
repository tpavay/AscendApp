import assert from "node:assert/strict";
import test from "node:test";
import {
  collectPublishedPhotoURLs,
  downloadTokensFromMetadata,
  firstAscentIdentityWrite,
  isMarkedSanitized,
  isUserProfilePicturePath,
  packBatches,
  parseSanitizationArgs,
  planProfilePictureSweep,
  planSanitizationPage,
  replacementDownloadURL,
  SANITIZATION_MARKER_KEY,
  storageObjectFromDownloadURL,
} from "../lib/public-identity-sanitization.mjs";

test("requires an explicit mode and named environment", () => {
  assert.throws(
    () => parseSanitizationArgs(["node", "script", "--env", "dev"]),
    /exactly one/
  );
  assert.deepEqual(
    parseSanitizationArgs(["node", "script", "--env", "staging", "--dry-run"]),
    {
      env: "staging",
      mode: "dry-run",
      rerun: false,
      productionConfirmation: null,
      batchSize: 400,
      help: false,
    }
  );
});

test("real identities sanitize once and are idempotent", () => {
  const unsafe = [{
    path: "leaderboard_stats/weekly_user",
    data: {displayName: "objectionable", photoURL: "https://example.com/photo.jpg"},
  }];
  const firstPlan = planSanitizationPage(unsafe, "leaderboard");
  assert.equal(firstPlan.length, 1);
  assert.deepEqual(firstPlan[0].update, {displayName: "Climber", photoURL: ""});

  const secondPlan = planSanitizationPage([{
    path: unsafe[0].path,
    data: {...unsafe[0].data, ...firstPlan[0].update},
  }], "leaderboard");
  assert.deepEqual(secondPlan, []);
});

test("pagination-sized pages preserve every planned real record", () => {
  const records = Array.from({length: 17}, (_, index) => ({
    path: `entries/${index}`,
    data: {
      avatarToken: "UGC",
      displayName: `User ${index}`,
      isSynthetic: false,
      photoURL: `https://example.com/${index}.jpg`,
    },
  }));
  const pages = packBatches(records, 4);
  const plan = pages.flatMap((page) => planSanitizationPage(page, "replay"));
  assert.equal(pages.length, 5);
  assert.equal(plan.length, records.length);
});

test("trusted synthetic fixtures retain first-party names and photos", () => {
  const records = [{
    path: "entries/synthetic",
    data: {
      displayName: "Summit Sprinter",
      photoURL: "https://fixture.example/avatar.png",
      isSynthetic: true,
      source: "synthetic",
    },
  }];
  assert.deepEqual(planSanitizationPage(records, "replay"), []);

  assert.deepEqual(firstAscentIdentityWrite({
    firstAscentUserId: "seeded:launch:climb:0",
    seedPackId: "launch",
    source: "seeded",
  }), {firstAscentIsSynthetic: true});
});

test("published Firebase URLs produce a token-rotation target and replacement", () => {
  const oldURL = "https://firebasestorage.googleapis.com/v0/b/ascend.firebasestorage.app/o/" +
    "users%2Fuid-1%2Fprofile_pictures%2Favatar.jpg?alt=media&token=old-token";
  const parsed = storageObjectFromDownloadURL(oldURL);
  assert.deepEqual(parsed, {
    bucket: "ascend.firebasestorage.app",
    path: "users/uid-1/profile_pictures/avatar.jpg",
    token: "old-token",
    url: oldURL,
  });

  const urls = collectPublishedPhotoURLs([
    {photoURL: oldURL},
    {firstAscentPhotoURL: oldURL},
  ]);
  assert.equal(urls.size, 1);
  assert.match(
    replacementDownloadURL(parsed.bucket, parsed.path, "new-token"),
    /token=new-token$/
  );
});

function sweepObject(path, {tokens, marked, timeCreated} = {}) {
  const metadata = {};
  if (tokens) metadata.firebaseStorageDownloadTokens = tokens;
  if (marked) metadata[SANITIZATION_MARKER_KEY] = "1";
  return {
    bucket: "ascend.firebasestorage.app",
    path,
    metadata: {timeCreated, metadata},
  };
}

test("sweep rotates every profile-picture object, referenced or not", () => {
  const ownerURL = "https://firebasestorage.googleapis.com/v0/b/ascend.firebasestorage.app/o/" +
    "users%2Fuid-1%2Fprofile_pictures%2Fcurrent.jpg?alt=media&token=tok-current";
  const plan = planProfilePictureSweep({
    objects: [
      sweepObject("users/uid-1/profile_pictures/current.jpg", {tokens: "tok-current"}),
      sweepObject("users/uid-2/profile_pictures/orphaned.jpg", {tokens: "tok-old, tok-older"}),
      sweepObject("users/uid-2/photos/workout.jpg", {tokens: "tok-photo"}),
    ],
    ownersByObjectKey: new Map([[
      "ascend.firebasestorage.app/users/uid-1/profile_pictures/current.jpg",
      [{ref: {}, userId: "uid-1", parsed: {url: ownerURL}}],
    ]]),
    publishedURLsByObject: new Map(),
    operationVersion: 1,
    exposureCutoff: null,
  });

  assert.equal(plan.rotations.length, 2);
  const orphan = plan.rotations.find((item) => item.path.endsWith("orphaned.jpg"));
  assert.equal(orphan.owners.length, 0);
  assert.equal(orphan.oldURLs.filter((url) => /token=tok-old(er)?$/.test(url)).length, 2);
  const referenced = plan.rotations.find((item) => item.path.endsWith("current.jpg"));
  assert.equal(referenced.owners.length, 1);
  assert.ok(referenced.oldURLs.includes(ownerURL));
});

test("rerun skips marked objects but still rotates newly discovered ones", () => {
  const plan = planProfilePictureSweep({
    objects: [
      sweepObject("users/uid-1/profile_pictures/done.jpg", {tokens: "tok-new", marked: true}),
      sweepObject("users/uid-3/profile_pictures/missed.jpg", {tokens: "tok-exposed"}),
    ],
    ownersByObjectKey: new Map(),
    publishedURLsByObject: new Map(),
    operationVersion: 1,
    exposureCutoff: null,
  });

  assert.equal(plan.alreadySanitized, 1);
  assert.deepEqual(plan.rotations.map((item) => item.path), [
    "users/uid-3/profile_pictures/missed.jpg",
  ]);

  assert.ok(isMarkedSanitized({metadata: {[SANITIZATION_MARKER_KEY]: "1"}}, 1));
  assert.ok(!isMarkedSanitized({metadata: {[SANITIZATION_MARKER_KEY]: "1"}}, 2));
});

test("objects uploaded after the first successful run are exempt, earlier ones are not", () => {
  const plan = planProfilePictureSweep({
    objects: [
      sweepObject("users/uid-1/profile_pictures/pre.jpg", {
        tokens: "tok-pre",
        timeCreated: "2026-07-01T00:00:00Z",
      }),
      sweepObject("users/uid-2/profile_pictures/post.jpg", {
        tokens: "tok-post",
        timeCreated: "2026-07-15T00:00:00Z",
      }),
    ],
    ownersByObjectKey: new Map(),
    publishedURLsByObject: new Map(),
    operationVersion: 1,
    exposureCutoff: new Date("2026-07-10T00:00:00Z"),
  });

  assert.equal(plan.createdAfterCutoff, 1);
  assert.deepEqual(plan.rotations.map((item) => item.path), [
    "users/uid-1/profile_pictures/pre.jpg",
  ]);
});

test("published URLs whose objects are gone become verify-only targets", () => {
  const deletedURL = "https://firebasestorage.googleapis.com/v0/b/ascend.firebasestorage.app/o/" +
    "users%2Fuid-9%2Fprofile_pictures%2Fdeleted.jpg?alt=media&token=tok-deleted";
  const plan = planProfilePictureSweep({
    objects: [],
    ownersByObjectKey: new Map(),
    publishedURLsByObject: new Map([[
      "ascend.firebasestorage.app/users/uid-9/profile_pictures/deleted.jpg",
      new Set([deletedURL]),
    ]]),
    operationVersion: 1,
    exposureCutoff: null,
  });

  assert.deepEqual(plan.rotations, []);
  assert.deepEqual(plan.verifyOnlyURLs, [deletedURL]);
});

test("profile-picture path matching and token parsing stay strict", () => {
  assert.ok(isUserProfilePicturePath("users/uid-1/profile_pictures/a.jpg"));
  assert.ok(!isUserProfilePicturePath("users/uid-1/photos/a.jpg"));
  assert.ok(!isUserProfilePicturePath("profile_pictures/a.jpg"));
  assert.ok(!isUserProfilePicturePath("users/uid-1/profile_pictures/"));

  assert.deepEqual(
    downloadTokensFromMetadata({metadata: {firebaseStorageDownloadTokens: "a, b ,c"}}),
    ["a", "b", "c"]
  );
  assert.deepEqual(downloadTokensFromMetadata({metadata: {}}), []);
  assert.deepEqual(downloadTokensFromMetadata(undefined), []);
});
