import {createHash} from "node:crypto";

export const ANONYMOUS_CLIMBER_NAME = "Anonymous Climber";
export const PUBLIC_IDENTITY_POLICY_VERSION = 1;
export const PUBLIC_IDENTITY_STATE_PUBLISHED = "published";
export const PUBLIC_IDENTITY_STATE_PENDING = "pending_public_profile";
export const PUBLIC_IDENTITY_STATE_DELETED = "deleted";

export type PublicIdentityState =
  typeof PUBLIC_IDENTITY_STATE_PUBLISHED |
  typeof PUBLIC_IDENTITY_STATE_PENDING |
  typeof PUBLIC_IDENTITY_STATE_DELETED;

// Mirrors PublicClimberIdentity.tokenAlphabet. Every letter is absent from
// every screened term and the generator never repeats a character back to back,
// so isAllowedDisplayName accepts every handle this can produce.
const TOKEN_ALPHABET = "2346789AEFJMNQRT";
const MAXIMUM_DISPLAY_NAME_LENGTH = 80;
const MAXIMUM_PHOTO_URL_LENGTH = 2048;
// Mirrors isValidPublicPhotoURL in firestore.rules.
const PROFILE_PHOTO_URL_PATTERN =
  /^https:\/\/firebasestorage\.googleapis\.com\/v0\/b\/[A-Za-z0-9][A-Za-z0-9._-]*\/o\/[^/]+$/u;
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

export interface PublicIdentity {
  displayName: string;
  photoURL: string | null;
  avatarToken: string;
}

/**
 * Returns the same stable fallback handle produced by the Swift client.
 * @param {string} userId Firebase Auth uid.
 * @return {string} Stable non-authored public handle.
 */
export function publicSystemHandle(userId: string): string {
  const normalizedUserId = userId.trim();
  if (
    normalizedUserId.length === 0 ||
    Buffer.byteLength(normalizedUserId, "utf8") > 128 ||
    Array.from(normalizedUserId).some((character) => {
      const codePoint = character.codePointAt(0) ?? 0;
      return codePoint <= 31 || codePoint === 127;
    })
  ) {
    return ANONYMOUS_CLIMBER_NAME;
  }

  const digest = createHash("sha256")
    .update(normalizedUserId, "utf8")
    .digest();
  const prefix = digest.readUInt32BE(0);
  const token = [20, 16, 12, 8, 4, 0].reduce<string[]>((token, shift) => {
    const character = TOKEN_ALPHABET[(prefix >>> shift) & 0x0F];
    const previous = token[token.length - 1];
    token.push(
      previous === character ? nextTokenCharacter(character) : character
    );
    return token;
  }, []).join("");

  return `Climber ${token}`;
}

/**
 * Advances one position in the token alphabet to break a repeated character.
 * @param {string} character Token character to advance past.
 * @return {string} The next alphabet character.
 */
function nextTokenCharacter(character: string): string {
  const index = TOKEN_ALPHABET.indexOf(character);
  return index < 0 ?
    character :
    TOKEN_ALPHABET[(index + 1) % TOKEN_ALPHABET.length];
}

/**
 * Resolves a profile mirror into identity safe to copy to public projections.
 * Invalid or absent authored identity falls back to a stable uid-derived name.
 * @param {string} userId Firebase Auth uid.
 * @param {Record<string, unknown> | undefined} data Profile mirror fields.
 * @return {PublicIdentity} Validated public identity.
 */
export function publicIdentityFromData(
  userId: string,
  data: Record<string, unknown> | undefined
): PublicIdentity {
  const candidate = stringValue(data?.displayName);
  const displayName = candidate !== null && isAllowedDisplayName(candidate) ?
    candidate :
    publicSystemHandle(userId);
  const photoURL = validPhotoURL(data?.photoURL);

  return {
    avatarToken: avatarToken(displayName),
    displayName,
    photoURL,
  };
}

/**
 * Identifies the account-deletion sentinel, which propagation must preserve.
 * @param {unknown} value Candidate stored display name.
 * @return {boolean} Whether the value is the reserved sentinel.
 */
export function isAnonymousClimberName(value: unknown): boolean {
  return typeof value === "string" &&
    digitSubstituted(foldedForScreening(value))
      .replace(/[^a-z]/gu, "") === "anonymousclimber";
}

/**
 * Screens an account-authored display name with the shared policy semantics.
 * @param {string} value Candidate authored name.
 * @return {boolean} Whether the name may be publicly projected.
 */
export function isAllowedDisplayName(value: string): boolean {
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
    return new RegExp(`(^|[^a-z])${pattern}([^a-z]|$)`, "u")
      .test(normalized);
  });
}

/**
 * Returns a bounded Firebase Storage download URL or null.
 *
 * Every viewer's device fetches this URL, so an arbitrary host would let a
 * modified client point the whole leaderboard at a server it controls.
 * @param {unknown} value Candidate profile photo field.
 * @return {string | null} Validated URL string.
 */
function validPhotoURL(value: unknown): string | null {
  const candidate = stringValue(value);
  if (
    candidate === null ||
    candidate.length > MAXIMUM_PHOTO_URL_LENGTH ||
    !PROFILE_PHOTO_URL_PATTERN.test(candidate)
  ) {
    return null;
  }

  return candidate;
}

/**
 * Normalizes case, diacritics, and confusable letters.
 *
 * Digits stay digits so the repeated-character check cannot invent a letter run
 * out of an ordinary numeric name.
 * @param {string} value Candidate display name.
 * @return {string} Folded screening form.
 */
function foldedForScreening(value: string): string {
  const substitutions: Record<string, string> = {
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
  const folded = value
    .normalize("NFKD")
    .replace(/\p{Diacritic}/gu, "")
    .toLocaleLowerCase();
  const substituted = Array.from(folded)
    .map((character) => substitutions[character] ?? character)
    .join("");

  return substituted;
}

/**
 * Applies leetspeak folding, used only by the blocked-term checks.
 * @param {string} folded Case- and confusable-folded name.
 * @return {string} Blocked-term screening form.
 */
function digitSubstituted(folded: string): string {
  const substitutions: Record<string, string> = {
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

  return Array.from(folded)
    .map((character) => substitutions[character] ?? character)
    .join("");
}

function containsUnsupportedCompatibilityGlyph(value: string): boolean {
  return Array.from(value).some((character) => {
    const codePoint = character.codePointAt(0) ?? 0;
    // U+02BB okina and U+02BC modifier apostrophe carry meaning in Hawaiian and
    // many other orthographies, so they stay spellable.
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

/**
 * Returns up to two initials for a generic avatar.
 * @param {string} displayName Resolved display name.
 * @return {string} Avatar initials.
 */
function avatarToken(displayName: string): string {
  return displayName
    .trim()
    .split(/\s+/u)
    .slice(0, 2)
    .map((component) => Array.from(component)[0] ?? "")
    .join("")
    .toLocaleUpperCase();
}

/**
 * Returns a trimmed string or null.
 * @param {unknown} value Candidate value.
 * @return {string | null} Trimmed non-empty string.
 */
function stringValue(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}

/**
 * Escapes a literal character for insertion into a RegExp.
 * @param {string} value Literal character.
 * @return {string} Escaped character.
 */
function escapeRegularExpression(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&");
}
