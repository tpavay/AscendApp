import assert from "node:assert/strict";
import test from "node:test";
import {
  collectPublishedPhotoURLs,
  firstAscentIdentityWrite,
  packBatches,
  parseSanitizationArgs,
  planSanitizationPage,
  replacementDownloadURL,
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
