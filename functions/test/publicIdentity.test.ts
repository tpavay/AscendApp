import test from "node:test";
import assert from "node:assert/strict";
import {
  isAllowedDisplayName,
  publicIdentityFromData,
  publicSystemHandle,
} from "../src/publicIdentity.js";

test("matches the Swift stable public handle vectors", () => {
  assert.equal(publicSystemHandle("user-123"), "Climber QRN9QT");
  assert.equal(publicSystemHandle("user-456"), "Climber 6JN7TM");
});

const STORAGE_PHOTO_URL =
  "https://firebasestorage.googleapis.com/v0/b/ascend-dev.appspot.com/o/" +
  "users%2Fuser-123%2Fprofile_pictures%2Fphoto.jpg?alt=media&token=abc";
// The exact shape StorageReference.downloadURL() emits: it sets
// URLComponents.port from Storage.port, which defaults to 443, and Foundation
// keeps that default port.
const SDK_EMITTED_PHOTO_URL =
  "https://firebasestorage.googleapis.com:443/v0/b/" +
  "ascend-staging-fa7d5.firebasestorage.app/o/" +
  "users%2FabC123%2Fprofile_pictures%2FDEAD-BEEF.jpg" +
  "?alt=media&token=11111111-2222-3333-4444-555555555555";

test("keeps the download URL the Firebase iOS SDK actually emits", () => {
  assert.equal(
    publicIdentityFromData("user-123", {
      displayName: "Maya Chen",
      photoURL: SDK_EMITTED_PHOTO_URL,
    }).photoURL,
    SDK_EMITTED_PHOTO_URL
  );
});

test("rejects the anonymous sentinel spelled with an okina", () => {
  assert.equal(isAllowedDisplayName("Anonymous\u02bb Climber"), false);
  assert.equal(isAllowedDisplayName("Anonymous\u02bcClimber"), false);
  assert.equal(isAllowedDisplayName("Anonymous Climber"), false);
});

test("uses validated account-authored identity", () => {
  assert.deepEqual(
    publicIdentityFromData("user-123", {
      displayName: "Maya Chen",
      photoURL: STORAGE_PHOTO_URL,
    }),
    {
      avatarToken: "MC",
      displayName: "Maya Chen",
      photoURL: STORAGE_PHOTO_URL,
    }
  );
});

test("drops a photo URL outside Firebase Storage", () => {
  // Every viewer's device fetches this URL, so an arbitrary host would leak
  // viewer IPs and render content outside the reactive moderation path.
  for (const photoURL of [
    "https://example.com/maya.jpg",
    "http://firebasestorage.googleapis.com/v0/b/ascend-dev.appspot.com/o/x",
    "https://firebasestorage.googleapis.com.evil.test/v0/b/bucket/o/x",
    "https://firebasestorage.googleapis.com/evil.jpg",
    "https://firebasestorage.googleapis.com/v0/b/bucket/o/users/plain/path",
    "https://firebasestorage.googleapis.com:8080/v0/b/bucket/o/photo.jpg",
    "javascript:alert(1)",
  ]) {
    assert.equal(
      publicIdentityFromData("user-123", {
        displayName: "Maya Chen",
        photoURL,
      }).photoURL,
      null,
      photoURL
    );
  }
});

test("keeps ordinary names containing digits and an okina", () => {
  assert.equal(isAllowedDisplayName("Climber2000"), true);
  assert.equal(isAllowedDisplayName("Runner000"), true);
  assert.equal(isAllowedDisplayName("Team111"), true);
  assert.equal(isAllowedDisplayName("Level333"), true);
  assert.equal(isAllowedDisplayName("Route555"), true);
  assert.equal(isAllowedDisplayName("Step777"), true);
  assert.equal(isAllowedDisplayName("Ka\u02bbiulani"), true);
  assert.equal(isAllowedDisplayName("O\u02bcahu Climber"), true);
});

test("falls back for absent or invalid account-authored identity", () => {
  assert.equal(
    publicIdentityFromData("user-123", undefined).displayName,
    "Climber QRN9QT"
  );
  assert.equal(
    publicIdentityFromData("user-123", {
      displayName: "fuuuck",
      photoURL: "javascript:alert(1)",
    }).displayName,
    "Climber QRN9QT"
  );
  assert.equal(
    publicIdentityFromData("user-123", {
      displayName: "Anonymous Climber",
    }).displayName,
    "Climber QRN9QT"
  );
});

test("screens canonical, repeated, and confusable objectionable names", () => {
  assert.equal(isAllowedDisplayName("asshole"), false);
  assert.equal(isAllowedDisplayName("fuuuck"), false);
  assert.equal(isAllowedDisplayName("fuсk"), false);
  assert.equal(isAllowedDisplayName("fυck"), false);
  assert.equal(isAllowedDisplayName("fucκ"), false);
  assert.equal(isAllowedDisplayName("fսck"), false);
  assert.equal(isAllowedDisplayName("ｆｕｃｋ"), false);
  assert.equal(isAllowedDisplayName("ｎｉｇｇｅｒ"), false);
  assert.equal(isAllowedDisplayName("fųck"), false);
  assert.equal(isAllowedDisplayName("f𝕦ck"), false);
  assert.equal(isAllowedDisplayName("fⓤck"), false);
  assert.equal(isAllowedDisplayName("f⒰ck"), false);
  assert.equal(isAllowedDisplayName("f🅤ck"), false);
  assert.equal(isAllowedDisplayName("fᵘck"), false);
  assert.equal(isAllowedDisplayName("Maaaya"), false);
  assert.equal(isAllowedDisplayName("Марія"), true);
});
