/**
 * The public identity contract every seeding entry point has to satisfy.
 *
 * The Admin SDK bypasses firestore.rules, so a seed tool is the one writer that
 * can publish an identity the rules would have rejected. The server trigger
 * then strips it on the way to leaderboard_stats, leaving the mirror and the
 * row disagreeing and scripts/audit-seed-data.mjs failing. These helpers make
 * the seed fail first instead.
 *
 * This is the JavaScript home of the screening. It mirrors DisplayNamePolicy in
 * Swift, isAllowedDisplayName in functions/src/publicIdentity.ts, and
 * isAllowedDisplayName in firestore.rules, and
 * SharedTestVectors/display-name-screening-vector.json pins it against the
 * Cloud Functions implementation so the two cannot drift apart.
 */

// Mirrors isValidPublicPhotoURL in firestore.rules and validPhotoURL in
// functions/src/publicIdentity.ts, including the default port the Firebase iOS
// SDK leaves in every download URL it emits.
export const PUBLIC_PHOTO_URL_PATTERN =
  /^https:\/\/firebasestorage\.googleapis\.com(:443)?\/v0\/b\/[A-Za-z0-9][A-Za-z0-9._-]*\/o\/[^/]+$/u;

export const MAXIMUM_DISPLAY_NAME_LENGTH = 80;
const MAXIMUM_PHOTO_URL_LENGTH = 2048;

const BLOCKED_TERMS = [
  "asshole",
  "bastard",
  "bitch",
  "blowjob",
  "chink",
  "cock",
  "cunt",
  "dick",
  "douchebag",
  "dyke",
  "fag",
  "faggot",
  "fuck",
  "fucker",
  "fucking",
  "heilhitler",
  "hitler",
  "jackass",
  "kike",
  "killyourself",
  "motherfucker",
  "nazi",
  "nigga",
  "nigger",
  "pedo",
  "pedophile",
  "piss",
  "pussy",
  "rape",
  "rapist",
  "retard",
  "retarded",
  "shit",
  "slut",
  "spic",
  "wetback",
  "whore",
  "whitepower",
];

const EMBEDDED_BLOCKED_TERMS = [
  "faggot",
  "fuck",
  "fucker",
  "nigger",
  "pedophile",
];

const CONFUSABLE_SUBSTITUTIONS = {
  "а": "a",
  "ɑ": "a",
  "α": "a",
  "β": "b",
  "е": "e",
  "ё": "e",
  "ε": "e",
  "і": "i",
  "ӏ": "i",
  "ι": "i",
  "κ": "k",
  "о": "o",
  "ο": "o",
  "р": "p",
  "ρ": "p",
  "с": "c",
  "τ": "t",
  "υ": "u",
  "х": "x",
  "χ": "x",
  "у": "y",
  "ս": "u",
};

const DIGIT_SUBSTITUTIONS = {
  "0": "o",
  "1": "i",
  "3": "e",
  "4": "a",
  "5": "s",
  "7": "t",
  "@": "a",
  "$": "s",
  "!": "i",
};

/**
 * Screens an account-authored display name with the shared policy semantics.
 * @param {string} value Candidate authored name.
 * @return {boolean} Whether the name may be publicly projected.
 */
export function isAllowedDisplayName(value) {
  if (typeof value !== "string") {
    return false;
  }

  const trimmed = value.trim();
  if (
    trimmed.length === 0 ||
    Array.from(trimmed).length > MAXIMUM_DISPLAY_NAME_LENGTH ||
    containsUnsupportedCompatibilityGlyph(trimmed)
  ) {
    return false;
  }

  const folded = foldedForScreening(trimmed);
  if (/([a-z])\1{2,}/u.test(folded)) {
    return false;
  }

  const normalized = digitSubstituted(folded);
  const lettersOnly = normalized.replace(/[^a-z]/gu, "");
  if (lettersOnly === "anonymousclimber") {
    return false;
  }

  if (EMBEDDED_BLOCKED_TERMS.some((term) => lettersOnly.includes(term))) {
    return false;
  }

  return !BLOCKED_TERMS.some((term) => {
    const pattern = term
      .split("")
      .map(escapeRegularExpression)
      .join("[^a-z]*");
    return new RegExp(`(^|[^a-z])${pattern}([^a-z]|$)`, "u").test(normalized);
  });
}

/**
 * Returns whether a photo URL may be published to a public projection.
 * @param {string} value Candidate photo URL, empty for no photo.
 * @return {boolean} Whether the URL satisfies the contract.
 */
export function isAllowedPublicPhotoURL(value) {
  if (typeof value !== "string") {
    return false;
  }
  if (value.length === 0) {
    return true;
  }
  return value.length <= MAXIMUM_PHOTO_URL_LENGTH &&
    PUBLIC_PHOTO_URL_PATTERN.test(value);
}

/**
 * Throws an operator-facing error when an identity would be published in a
 * shape the rules reject and the propagation trigger strips.
 * A null or absent field is one the caller is not setting, so it is skipped;
 * the resolved values are checked again before the write.
 * @param {object} identity Candidate identity.
 * @param {string} [identity.displayName] Candidate display name.
 * @param {string} [identity.photoURL] Candidate photo URL, empty for no photo.
 * @param {string} [context] Command name used in the error message.
 */
export function assertPublishablePublicIdentity(
  {displayName, photoURL},
  context = "seed"
) {
  if (displayName != null && !isAllowedDisplayName(displayName)) {
    throw new Error(
      `${context}: display name ${JSON.stringify(displayName)} fails the ` +
      "shared display-name screening, so firestore.rules would reject it and " +
      "the identity propagation trigger would replace it. Choose another name."
    );
  }

  if (photoURL != null && !isAllowedPublicPhotoURL(photoURL)) {
    throw new Error(
      `${context}: photo URL ${JSON.stringify(photoURL)} is not a Firebase ` +
      "Storage download URL " +
      "(https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<object>), so " +
      "firestore.rules would reject it and the identity propagation trigger " +
      "would blank it. Upload the image to Storage and use its download URL, " +
      "or pass --photo-url \"\" (or --clear-photo) to publish no photo."
    );
  }
}

function foldedForScreening(value) {
  const folded = value
    .normalize("NFKD")
    .replace(/\p{Diacritic}/gu, "")
    .toLocaleLowerCase();

  return Array.from(folded)
    .map((character) => CONFUSABLE_SUBSTITUTIONS[character] ?? character)
    .join("");
}

function digitSubstituted(folded) {
  return Array.from(folded)
    .map((character) => DIGIT_SUBSTITUTIONS[character] ?? character)
    .join("");
}

function containsUnsupportedCompatibilityGlyph(value) {
  return Array.from(value).some((character) => {
    const codePoint = character.codePointAt(0) ?? 0;
    if (codePoint === 0x02BB || codePoint === 0x02BC) {
      return false;
    }
    return (
      (codePoint >= 0x02B0 && codePoint <= 0x02FF) ||
      (codePoint >= 0x1D00 && codePoint <= 0x1D7F) ||
      (codePoint >= 0x2070 && codePoint <= 0x209F) ||
      (codePoint >= 0x2100 && codePoint <= 0x218F) ||
      (codePoint >= 0x2460 && codePoint <= 0x24FF) ||
      (codePoint >= 0x3200 && codePoint <= 0x33FF) ||
      (codePoint >= 0xFB00 && codePoint <= 0xFB06) ||
      (codePoint >= 0xFE10 && codePoint <= 0xFE6B) ||
      (codePoint >= 0xFF00 && codePoint <= 0xFFEF) ||
      (codePoint >= 0x1D400 && codePoint <= 0x1D7FF) ||
      (codePoint >= 0x1F100 && codePoint <= 0x1F2FF)
    );
  });
}

function escapeRegularExpression(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&");
}
