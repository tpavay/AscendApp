import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";

import {
  PUBLIC_PHOTO_URL_PATTERN,
  assertPublishablePublicIdentity,
  isAllowedDisplayName,
  isAllowedPublicPhotoURL,
} from "../seed/lib/public-identity-contract.mjs";

const vector = JSON.parse(readFileSync(
  fileURLToPath(new URL(
    "../../SharedTestVectors/display-name-screening-vector.json",
    import.meta.url
  )),
  "utf-8"
));

// The exact string StorageReference.downloadURL() emits: URLComponents.port is
// set from Storage.port, which defaults to 443, and Foundation keeps it.
const SDK_EMITTED_PHOTO_URL =
  "https://firebasestorage.googleapis.com:443/v0/b/" +
  "ascend-staging-fa7d5.firebasestorage.app/o/" +
  "users%2FabC123%2Fprofile_pictures%2FDEAD-BEEF.jpg" +
  "?alt=media&token=11111111-2222-3333-4444-555555555555";

test("display-name screening matches the shared vector", () => {
  for (const name of vector.allowed) {
    assert.equal(isAllowedDisplayName(name), true, `allowed: ${name}`);
  }
  for (const name of vector.rejected) {
    assert.equal(isAllowedDisplayName(name), false, `rejected: ${name}`);
  }
});

test("photo URLs are limited to Firebase Storage download URLs", () => {
  assert.equal(isAllowedPublicPhotoURL(SDK_EMITTED_PHOTO_URL), true);
  assert.equal(isAllowedPublicPhotoURL(""), true);

  for (const photoURL of [
    "https://ui-avatars.com/api/?name=Noah",
    "https://example.com/x.jpg",
    "http://firebasestorage.googleapis.com/v0/b/bucket/o/photo.jpg",
    "https://firebasestorage.googleapis.com.attacker.test/v0/b/b/o/x.jpg",
    "https://firebasestorage.googleapis.com/evil.jpg",
    "https://firebasestorage.googleapis.com/v0/b/bucket/o/users/plain/path.jpg",
    "https://firebasestorage.googleapis.com:8080/v0/b/bucket/o/photo.jpg",
  ]) {
    assert.equal(isAllowedPublicPhotoURL(photoURL), false, photoURL);
  }

  assert.equal(PUBLIC_PHOTO_URL_PATTERN.test(SDK_EMITTED_PHOTO_URL), true);
});

// The Admin SDK bypasses firestore.rules, so hydrate-user is the one writer
// that could publish an identity the server would strip on projection.
test("hydrate-user rejects an off-host photo URL", () => {
  assert.throws(
    () => assertPublishablePublicIdentity(
      {displayName: "QA Tester", photoURL: "https://example.com/x.jpg"},
      "hydrate-user"
    ),
    /hydrate-user: photo URL .* is not a Firebase Storage download URL/u
  );
});

test("hydrate-user rejects a display name that fails screening", () => {
  assert.throws(
    () => assertPublishablePublicIdentity(
      {displayName: "fuuuck", photoURL: ""},
      "hydrate-user"
    ),
    /hydrate-user: display name .* fails the shared display-name screening/u
  );

  assert.throws(
    () => assertPublishablePublicIdentity(
      {displayName: "Anonymousʻ Climber", photoURL: ""},
      "hydrate-user"
    ),
    /fails the shared display-name screening/u
  );
});

test("hydrate-user accepts a legitimate identity pair", () => {
  assert.doesNotThrow(() => assertPublishablePublicIdentity(
    {displayName: "Kaʻiulani", photoURL: SDK_EMITTED_PHOTO_URL},
    "hydrate-user"
  ));
  assert.doesNotThrow(() => assertPublishablePublicIdentity(
    {displayName: "Climber2000", photoURL: ""},
    "hydrate-user"
  ));
  assert.doesNotThrow(() => assertPublishablePublicIdentity({}, "hydrate-user"));
});
