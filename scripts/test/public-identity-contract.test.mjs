import test from "node:test";
import assert from "node:assert/strict";
import {execFileSync} from "node:child_process";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";

import {
  isExplicitPhotoClear,
  resolveHydratePhotoURL,
} from "../dev-db.mjs";

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
  // An omitted flag arrives as null from trimmed(); it is not an identity the
  // caller is setting, so it must not be screened as one.
  assert.doesNotThrow(() => assertPublishablePublicIdentity(
    {displayName: null, photoURL: null},
    "hydrate-user"
  ));
});

test("hydrate-user allows omitting --display-name entirely", () => {
  const result = runDevDb([
    "hydrate-user", "--project", "dev", "--user", "seed-user",
    "--age", "30", "--gender", "man",
    "--height-cm", "180", "--weight-kg", "80", "--country", "usa",
  ]);

  assert.equal(result.failed, true);
  assert.match(result.output, /--country as an ISO-2 code/u);
  assert.doesNotMatch(result.output, /display name/u);
});

const DEV_DB = fileURLToPath(new URL("../dev-db.mjs", import.meta.url));

function runDevDb(args) {
  try {
    execFileSync(process.execPath, [DEV_DB, ...args], {
      encoding: "utf-8",
      stdio: ["ignore", "pipe", "pipe"],
    });
    return {failed: false, output: ""};
  } catch (error) {
    return {failed: true, output: `${error.stdout ?? ""}${error.stderr ?? ""}`};
  }
}

// The escape hatch has to survive argument parsing, which is where it used to
// die: requireValue rejected an empty string before the command ever ran. These
// invoke the CLI exactly as the skill and the error message instruct.
test("hydrate-user accepts the documented empty --photo-url through argv", () => {
  const baseArgs = [
    "hydrate-user", "--project", "dev", "--user", "seed-user",
    "--age", "30", "--gender", "man",
    "--height-cm", "180", "--weight-kg", "80",
  ];

  // Parsing and identity validation both pass, so the run gets as far as the
  // country check rather than dying on the photo argument.
  const cleared = runDevDb([...baseArgs, "--photo-url", "", "--country", "usa"]);
  assert.equal(cleared.failed, true);
  assert.match(cleared.output, /--country as an ISO-2 code/u);
  assert.doesNotMatch(cleared.output, /--photo-url requires a value/u);
  assert.doesNotMatch(cleared.output, /not a Firebase Storage download URL/u);

  const clearFlag = runDevDb([...baseArgs, "--clear-photo", "--country", "usa"]);
  assert.equal(clearFlag.failed, true);
  assert.match(clearFlag.output, /--country as an ISO-2 code/u);
  assert.doesNotMatch(clearFlag.output, /not a Firebase Storage download URL/u);
});

test("hydrate-user still refuses an off-contract --photo-url through argv", () => {
  const result = runDevDb([
    "hydrate-user", "--project", "dev", "--user", "seed-user",
    "--photo-url", "https://ui-avatars.com/api/?name=Noah",
    "--age", "30", "--gender", "man",
    "--height-cm", "180", "--weight-kg", "80", "--country", "US",
  ]);

  assert.equal(result.failed, true);
  assert.match(result.output, /not a Firebase Storage download URL/u);
  // The message has to name an invocation that actually works.
  assert.match(result.output, /--photo-url "" \(or --clear-photo\)/u);
});

test("hydrate-user reports a missing --photo-url value distinctly", () => {
  const result = runDevDb([
    "hydrate-user", "--project", "dev", "--user", "seed-user", "--photo-url",
  ]);

  assert.equal(result.failed, true);
  assert.match(result.output, /--photo-url requires a value/u);
});

// An explicit clear must beat the stored value; that fallback was the second
// blocker behind the documented escape.
test("an explicit photo clear wins over the stored profile picture", () => {
  const stored = "https://ui-avatars.com/api/?name=Noah";

  assert.equal(resolveHydratePhotoURL("", stored), "");
  assert.equal(resolveHydratePhotoURL("   ", stored), "");
  assert.equal(resolveHydratePhotoURL(undefined, stored), stored);
  assert.equal(resolveHydratePhotoURL(null, undefined), "");
  assert.equal(
    resolveHydratePhotoURL(SDK_EMITTED_PHOTO_URL, stored),
    SDK_EMITTED_PHOTO_URL
  );

  assert.equal(isExplicitPhotoClear(""), true);
  assert.equal(isExplicitPhotoClear(undefined), false);
  assert.equal(isExplicitPhotoClear(stored), false);
});
