import test from "node:test";
import assert from "node:assert/strict";
import {
  isAllowedDisplayName,
  publicIdentityFromData,
  publicSystemHandle,
} from "../src/publicIdentity.js";

test("matches the Swift stable public handle vectors", () => {
  assert.equal(publicSystemHandle("user-123"), "Climber 7TPMNX");
  assert.equal(publicSystemHandle("user-456"), "Climber ZA5MJ6");
});

test("uses validated account-authored identity", () => {
  assert.deepEqual(
    publicIdentityFromData("user-123", {
      displayName: "Maya Chen",
      photoURL: "https://example.com/maya.jpg",
    }),
    {
      avatarToken: "MC",
      displayName: "Maya Chen",
      photoURL: "https://example.com/maya.jpg",
    }
  );
});

test("falls back for absent or invalid account-authored identity", () => {
  assert.equal(
    publicIdentityFromData("user-123", undefined).displayName,
    "Climber 7TPMNX"
  );
  assert.equal(
    publicIdentityFromData("user-123", {
      displayName: "fuuuck",
      photoURL: "javascript:alert(1)",
    }).displayName,
    "Climber 7TPMNX"
  );
  assert.equal(
    publicIdentityFromData("user-123", {
      displayName: "Anonymous Climber",
    }).displayName,
    "Climber 7TPMNX"
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
  assert.equal(isAllowedDisplayName("Maaaya"), false);
  assert.equal(isAllowedDisplayName("Марія"), true);
});
