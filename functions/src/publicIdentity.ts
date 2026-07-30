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

const TOKEN_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
const MAXIMUM_DISPLAY_NAME_LENGTH = 80;
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
  const token = [27, 22, 17, 12, 7, 2]
    .map((shift) => TOKEN_ALPHABET[(prefix >>> shift) & 0x1F])
    .join("");

  return `Climber ${token}`;
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
    normalizedForScreening(value)
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
    Array.from(trimmed).length > MAXIMUM_DISPLAY_NAME_LENGTH
  ) {
    return false;
  }

  const normalized = normalizedForScreening(trimmed);
  if (/([a-z])\1{2,}/u.test(normalized)) {
    return false;
  }
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
 * Returns a bounded HTTP(S) photo URL or null.
 * @param {unknown} value Candidate profile photo field.
 * @return {string | null} Validated URL string.
 */
function validPhotoURL(value: unknown): string | null {
  const candidate = stringValue(value);
  if (
    candidate === null ||
    candidate.length > MAXIMUM_PHOTO_URL_LENGTH
  ) {
    return null;
  }

  try {
    const url = new URL(candidate);
    return url.protocol === "https:" || url.protocol === "http:" ?
      candidate :
      null;
  } catch {
    return null;
  }
}

/**
 * Normalizes common separator, digit, and confusable obfuscations.
 * @param {string} value Candidate display name.
 * @return {string} Screening form.
 */
function normalizedForScreening(value: string): string {
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
