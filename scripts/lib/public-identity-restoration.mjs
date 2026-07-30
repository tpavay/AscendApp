import {createHash} from "node:crypto";

export const DEFAULT_RESTORATION_BATCH_SIZE = 400;
export const RESTORATION_OPERATION_VERSION = 5;
export const ANONYMOUS_CLIMBER_NAME = "Anonymous Climber";
export const PUBLIC_IDENTITY_POLICY_VERSION = 1;
export const PUBLIC_IDENTITY_STATE_PUBLISHED = "published";
export const PUBLIC_IDENTITY_STATE_PENDING = "pending_public_profile";
export const PUBLIC_IDENTITY_STATE_DELETED = "deleted";
export const MAXIMUM_RESTORATION_REPLANS = 3;

const MODES = new Set(["dry-run", "apply", "audit"]);
const TOKEN_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
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

/**
 * Parses the restoration runner's strict environment and mode arguments.
 * @param {string[]} argv Process argv.
 * @return {object} Validated runner arguments.
 */
export function parseRestorationArgs(argv) {
  const parsed = {
    env: null,
    mode: null,
    rerun: false,
    productionConfirmation: null,
    batchSize: DEFAULT_RESTORATION_BATCH_SIZE,
    help: false,
  };

  for (let index = 2; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--env") {
      parsed.env = requiredValue(argv, ++index, value);
    } else if (value === "--confirm-production") {
      parsed.productionConfirmation = requiredValue(argv, ++index, value);
    } else if (value === "--batch-size") {
      parsed.batchSize = Number(requiredValue(argv, ++index, value));
    } else if (value === "--rerun") {
      parsed.rerun = true;
    } else if (value === "--help" || value === "-h") {
      parsed.help = true;
    } else if (value.startsWith("--") && MODES.has(value.slice(2))) {
      if (parsed.mode) {
        throw new Error(
          "Pass exactly one of --dry-run, --apply, or --audit."
        );
      }
      parsed.mode = value.slice(2);
    } else {
      throw new Error(`Unknown argument: ${value}`);
    }
  }

  if (parsed.help) {
    return parsed;
  }
  if (!parsed.env) {
    throw new Error("Missing --env.");
  }
  if (!parsed.mode) {
    throw new Error("Pass exactly one of --dry-run, --apply, or --audit.");
  }
  if (
    !Number.isInteger(parsed.batchSize) ||
    parsed.batchSize < 1 ||
    parsed.batchSize > 450
  ) {
    throw new Error("--batch-size must be an integer from 1 through 450.");
  }
  if (parsed.rerun && parsed.mode !== "apply") {
    throw new Error("--rerun is valid only with --apply.");
  }

  return parsed;
}

/**
 * Resolves validated account identity with the shared stable uid fallback.
 * @param {string} userId Firebase Auth uid.
 * @param {object} userData Private owner profile fields.
 * @return {{displayName: string, photoURL: string, avatarToken: string}}
 *   Public identity to restore.
 */
export function restoredIdentityForUser(userId, userData) {
  const candidate = nonEmptyString(userData?.displayName);
  const displayName = candidate && isAllowedDisplayName(candidate) ?
    candidate :
    publicSystemHandle(userId);
  const photoURL = validPhotoURL(userData?.profilePictureURL) ?? "";

  return {
    avatarToken: avatarToken(displayName),
    displayName,
    photoURL,
  };
}

/**
 * Returns the same stable handle produced by Swift and Cloud Functions.
 * @param {string} userId Firebase Auth uid.
 * @return {string} Stable public fallback.
 */
export function publicSystemHandle(userId) {
  const normalizedUserId = userId.trim();
  if (
    normalizedUserId.length === 0 ||
    Buffer.byteLength(normalizedUserId, "utf8") > 128 ||
    hasControlCharacter(normalizedUserId)
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
 * Plans every projection write needed for one real user.
 * @param {object} input User source and current projection records.
 * @return {object} Per-user idempotent restoration plan.
 */
export function planUserIdentityRestoration(input) {
  const identity = restoredIdentityForUser(input.userId, input.userData);
  const writes = [];
  const targets = restorationTargetStates(input);
  const targetFingerprint = targetStateFingerprint(targets);
  const missingPublicProfile = input.publicProfile == null;
  if (missingPublicProfile) {
    appendPermanentAnonymousLeaderboardWrites(
      writes,
      input.leaderboards
    );
    return {
      identity,
      identityDigest: identityDigest(
        input.userId,
        identity,
        input.sourceVersion
      ),
      missingPublicProfile,
      skipReason: "missing public_profile/current",
      sourceVersion: input.sourceVersion,
      targetFingerprint,
      targets,
      userId: input.userId,
      writes,
    };
  }
  const protectedIdentity = {
    ...identity,
    identityChangedAt: input.identityChangedAt,
    identityPolicyVersion: PUBLIC_IDENTITY_POLICY_VERSION,
  };

  appendWriteIfChanged(
    writes,
    input.publicProfile,
    publicProfileIdentityFields(protectedIdentity)
  );
  appendProjectionWrites(
    writes,
    input.leaderboards,
    protectedIdentity,
    "leaderboard"
  );
  appendProjectionWrites(
    writes,
    input.replayEntries,
    protectedIdentity,
    "replay"
  );
  appendProjectionWrites(
    writes,
    input.replayFinishers,
    protectedIdentity,
    "replay"
  );
  appendProjectionWrites(
    writes,
    input.firstAscents,
    protectedIdentity,
    "firstAscent"
  );

  return {
    identity,
    identityDigest: identityDigest(
      input.userId,
      protectedIdentity,
      input.sourceVersion
    ),
    missingPublicProfile,
    skipReason: null,
    sourceVersion: input.sourceVersion,
    targetFingerprint,
    targets,
    userId: input.userId,
    writes,
  };
}

/**
 * Plans permanent anonymization for a global row whose account root is gone.
 *
 * Seeded competitors intentionally have no users/{uid} root and remain
 * untouched. Every other orphan row is de-identified, including stale real
 * identity left by interrupted account cleanup.
 * @param {object} record Current leaderboard projection.
 * @param {boolean} userRootExists Whether users/{uid} exists.
 * @return {object | null} Identity-only merge write, if required.
 */
export function planOrphanLeaderboardIdentityRestoration(
  record,
  userRootExists
) {
  if (
    userRootExists ||
    isTrustedSyntheticProjection(record?.data, "leaderboard")
  ) {
    return null;
  }

  const writes = [];
  appendWriteIfChanged(
    writes,
    record,
    deletedLeaderboardIdentityFields()
  );
  return writes[0] ?? null;
}

/**
 * Audits one global row against root existence and deletion identity policy.
 * @param {object} record Current leaderboard projection.
 * @param {boolean} userRootExists Whether users/{uid} exists.
 * @return {string[]} Human-readable audit failures.
 */
export function auditOrphanLeaderboardIdentityRestoration(
  record,
  userRootExists
) {
  const write = planOrphanLeaderboardIdentityRestoration(
    record,
    userRootExists
  );
  return write === null ?
    [] :
    [`${record.path} has noncurrent deleted identity without a user root`];
}

/**
 * Signals that a source or target changed after planning.
 */
export class StaleIdentityRestorationPlanError extends Error {
  constructor(message) {
    super(message);
    this.name = "StaleIdentityRestorationPlanError";
  }
}

/**
 * Replans and retries a user when a concurrent edit invalidates the snapshot.
 * @param {object} port Fresh plan and transactional apply boundary.
 * @param {number} maximumAttempts Bounded replan count.
 * @return {Promise<object>} Applied or explicitly skipped outcome.
 */
export async function applyFreshUserIdentityRestoration(
  port,
  maximumAttempts = MAXIMUM_RESTORATION_REPLANS
) {
  for (let attempt = 1; attempt <= maximumAttempts; attempt += 1) {
    const plan = await port.loadFreshPlan();
    if (
      (plan.missingPublicProfile || plan.skipReason) &&
      plan.writes.length === 0
    ) {
      return {
        plan,
        projectionWrites: 0,
        status: "skipped",
      };
    }

    try {
      const projectionWrites = await port.applyPlan(plan);
      return {
        plan,
        projectionWrites,
        status: "applied",
      };
    } catch (error) {
      if (
        !(error instanceof StaleIdentityRestorationPlanError) ||
        attempt === maximumAttempts
      ) {
        throw error;
      }
    }
  }

  throw new Error("Identity restoration exhausted its replan budget.");
}

/**
 * Replans an audit when the private source changes before verification.
 * @param {object} port Fresh planning and transactional marker boundary.
 * @param {number} maximumAttempts Bounded replan count.
 * @return {Promise<object>} Fresh plan, marker, and audit failures.
 */
export async function auditFreshUserIdentityRestoration(
  port,
  maximumAttempts = MAXIMUM_RESTORATION_REPLANS
) {
  for (let attempt = 1; attempt <= maximumAttempts; attempt += 1) {
    const plan = await port.loadFreshPlan();

    try {
      const marker = await port.loadMarkerForCurrentSource(plan);
      const verifiedPlan = await port.loadFreshPlan();
      if (
        verifiedPlan.sourceVersion !== plan.sourceVersion ||
        verifiedPlan.identityDigest !== plan.identityDigest ||
        verifiedPlan.targetFingerprint !== plan.targetFingerprint
      ) {
        throw new StaleIdentityRestorationPlanError(
          `${plan.userId} source or target changed during audit verification`
        );
      }
      return {
        attempts: attempt,
        failures: auditUserIdentityRestoration(verifiedPlan, marker),
        marker,
        plan: verifiedPlan,
      };
    } catch (error) {
      if (
        !(error instanceof StaleIdentityRestorationPlanError) ||
        attempt === maximumAttempts
      ) {
        throw error;
      }
    }
  }

  throw new Error("Identity restoration audit exhausted its replan budget.");
}

/**
 * Captures every queried restoration target, including already-current and
 * protected projections, so concurrent state changes cannot evade an audit.
 * @param {object} input Planner input.
 * @return {object[]} Deterministically ordered target versions.
 */
function restorationTargetStates(input) {
  return [
    {kind: "publicProfile", record: input.publicProfile},
    ...(input.leaderboards ?? []).map((record) => ({
      kind: "leaderboard",
      record,
    })),
    ...(input.replayEntries ?? []).map((record) => ({
      kind: "replay",
      record,
    })),
    ...(input.replayFinishers ?? []).map((record) => ({
      kind: "replay",
      record,
    })),
    ...(input.firstAscents ?? []).map((record) => ({
      kind: "firstAscent",
      record,
    })),
  ]
    .filter(({record}) => record != null)
    .map(({kind, record}) => ({
      identityFingerprint: projectionIdentityFingerprint(record.data, kind),
      path: record.path,
      version: record.version ?? null,
    }))
    .sort((left, right) => left.path.localeCompare(right.path));
}

/**
 * Produces one bounded comparison token for the complete target state.
 * @param {object[]} targets Ordered target versions.
 * @return {string} SHA-256 target-state digest.
 */
function targetStateFingerprint(targets) {
  return createHash("sha256")
    .update(JSON.stringify(targets), "utf8")
    .digest("hex");
}

/**
 * Fingerprints every field that can change restoration planning without
 * retaining user-authored identity in the plan metadata.
 * @param {object} data Projection fields.
 * @param {string} kind Projection shape.
 * @return {string} SHA-256 identity-state digest.
 */
function projectionIdentityFingerprint(data, kind) {
  let fields;
  if (kind === "firstAscent") {
    fields = {
      avatarToken: data?.firstAscentAvatarToken,
      displayName: data?.firstAscentDisplayName,
      identityState: data?.firstAscentIdentityState,
      isSynthetic: data?.firstAscentIsSynthetic,
      photoURL: data?.firstAscentPhotoURL,
      seedPackId: data?.seedPackId,
      source: data?.source,
      userId: data?.firstAscentUserId,
    };
  } else {
    fields = {
      avatarToken: data?.avatarToken,
      displayName: data?.displayName,
      identityChangedAt: comparableValue(data?.identityChangedAt),
      identityPolicyVersion: data?.identityPolicyVersion,
      identityState: data?.identityState,
      isSynthetic: data?.isSynthetic,
      photoURL: data?.photoURL,
      source: data?.source,
    };
  }

  return createHash("sha256")
    .update(JSON.stringify(fields), "utf8")
    .digest("hex");
}

/**
 * Returns audit failures for a user plan and its completion marker.
 * @param {object} plan Current idempotent plan.
 * @param {object | undefined} marker Per-user migration marker data.
 * @return {string[]} Human-readable audit failures.
 */
export function auditUserIdentityRestoration(plan, marker) {
  if (plan.missingPublicProfile || plan.skipReason) {
    return [
      `${plan.userId} skipped: ${plan.skipReason ?? "unsafe source state"}`,
    ];
  }

  const failures = plan.writes.map(
    (write) => `${write.path} has stale public identity`
  );

  if (
    marker?.operationVersion !== RESTORATION_OPERATION_VERSION ||
    marker?.identityDigest !== plan.identityDigest ||
    marker?.sourceVersion !== plan.sourceVersion
  ) {
    failures.push(`${plan.userId} has no matching completion marker`);
  }

  return failures;
}

/**
 * Adds projection updates while preserving synthetic and deletion sentinels.
 * @param {object[]} writes Output writes.
 * @param {object[] | undefined} records Current projections.
 * @param {object} identity Restored identity.
 * @param {string} kind Projection shape.
 */
function appendProjectionWrites(
  writes,
  records,
  identity,
  kind
) {
  for (const record of records ?? []) {
    if (
      kind === "leaderboard" &&
      !isTrustedSyntheticProjection(record.data, kind) &&
      isPermanentAnonymousLeaderboard(record.data)
    ) {
      appendWriteIfChanged(
        writes,
        record,
        deletedLeaderboardIdentityFields()
      );
      continue;
    }
    if (isProtectedProjection(record.data, kind)) {
      continue;
    }
    appendWriteIfChanged(
      writes,
      record,
      identityFieldsForKind(identity, kind)
    );
  }
}

/**
 * Plans only safe permanent-anonymous normalization when no publishable source
 * mirror exists.
 * @param {object[]} writes Output writes.
 * @param {object[] | undefined} records Global leaderboard projections.
 */
function appendPermanentAnonymousLeaderboardWrites(writes, records) {
  for (const record of records ?? []) {
    if (
      !isTrustedSyntheticProjection(record.data, "leaderboard") &&
      isPermanentAnonymousLeaderboard(record.data)
    ) {
      appendWriteIfChanged(
        writes,
        record,
        deletedLeaderboardIdentityFields()
      );
    }
  }
}

/**
 * Keeps trusted fixtures and account-deletion identity unchanged.
 * @param {object} data Projection fields.
 * @param {string} kind Projection shape.
 * @return {boolean} Whether restoration must skip the record.
 */
function isProtectedProjection(data, kind) {
  if (isTrustedSyntheticProjection(data, kind)) {
    return true;
  }

  const nameField = kind === "firstAscent" ?
    "firstAscentDisplayName" :
    "displayName";
  const stateField = kind === "firstAscent" ?
    "firstAscentIdentityState" :
    "identityState";
  const state = data?.[stateField];
  if (state === PUBLIC_IDENTITY_STATE_DELETED) {
    return true;
  }
  if (
    isAnonymousClimberName(data?.[nameField]) &&
    state !== PUBLIC_IDENTITY_STATE_PENDING
  ) {
    return true;
  }

  return false;
}

/**
 * Identifies trusted seeded projections that restoration never mutates.
 * @param {object} data Projection fields.
 * @param {string} kind Projection shape.
 * @return {boolean} Whether the record is synthetic.
 */
function isTrustedSyntheticProjection(data, kind) {
  if (kind !== "firstAscent") {
    return data?.isSynthetic === true || data?.source === "synthetic";
  }
  if (data?.firstAscentIsSynthetic === true) {
    return true;
  }

  return data?.source === "seeded" &&
    typeof data?.seedPackId === "string" &&
    data.seedPackId.length > 0 &&
    typeof data?.firstAscentUserId === "string" &&
    data.firstAscentUserId.startsWith("seeded:");
}

/**
 * Keeps old deletion sentinels permanently anonymous while making them
 * readable by the lifecycle-aware client.
 * @param {object} data Global leaderboard fields.
 * @return {boolean} Whether the row must converge to deleted identity.
 */
function isPermanentAnonymousLeaderboard(data) {
  return data?.identityState === PUBLIC_IDENTITY_STATE_DELETED ||
    (
      isAnonymousClimberName(data?.displayName) &&
      data?.identityState !== PUBLIC_IDENTITY_STATE_PENDING
    );
}

/**
 * Returns the complete permanent-anonymous global identity shape.
 * @return {object} Identity-only merge fields.
 */
function deletedLeaderboardIdentityFields() {
  return {
    displayName: ANONYMOUS_CLIMBER_NAME,
    identityChangedAt: null,
    identityPolicyVersion: PUBLIC_IDENTITY_POLICY_VERSION,
    identityState: PUBLIC_IDENTITY_STATE_DELETED,
    photoURL: "",
  };
}

/**
 * Appends an exact merge write only when at least one field differs.
 * @param {object[]} writes Output writes.
 * @param {object} record Existing record with path and data.
 * @param {object} fields Desired identity fields.
 */
function appendWriteIfChanged(writes, record, fields) {
  const isCurrent = Object.entries(fields).every(
    ([field, value]) => valuesEqual(record.data?.[field], value)
  );
  if (!isCurrent) {
    writes.push({
      fields,
      path: record.path,
      targetVersion: record.version,
    });
  }
}

/**
 * Returns exact identity fields for one projection shape.
 * @param {object} identity Restored identity.
 * @param {string} kind Projection shape.
 * @return {object} Identity-only merge fields.
 */
function identityFieldsForKind(identity, kind) {
  if (kind === "leaderboard") {
    return {
      ...publicProfileIdentityFields(identity),
      identityState: PUBLIC_IDENTITY_STATE_PUBLISHED,
    };
  }
  if (kind === "firstAscent") {
    return {
      firstAscentAvatarToken: identity.avatarToken,
      firstAscentDisplayName: identity.displayName,
      firstAscentIdentityState: PUBLIC_IDENTITY_STATE_PUBLISHED,
      firstAscentIsSynthetic: false,
      firstAscentPhotoURL: identity.photoURL,
    };
  }
  return {
    avatarToken: identity.avatarToken,
    displayName: identity.displayName,
    identityState: PUBLIC_IDENTITY_STATE_PUBLISHED,
    isSynthetic: false,
    photoURL: identity.photoURL,
  };
}

/**
 * Returns public profile and leaderboard identity fields.
 * @param {object} identity Restored identity.
 * @return {object} Identity fields.
 */
function publicProfileIdentityFields(identity) {
  return {
    displayName: identity.displayName,
    identityChangedAt: identity.identityChangedAt,
    identityPolicyVersion: identity.identityPolicyVersion,
    photoURL: identity.photoURL,
  };
}

/**
 * Produces the marker digest for one source identity.
 * @param {string} userId Firebase Auth uid.
 * @param {object} identity Restored identity.
 * @return {string} SHA-256 digest.
 */
function identityDigest(userId, identity, sourceVersion) {
  return createHash("sha256")
    .update(
      JSON.stringify({
        userId,
        sourceVersion,
        ...identity,
        identityChangedAt: comparableValue(identity.identityChangedAt),
      }),
      "utf8"
    )
    .digest("hex");
}

/**
 * Screens account-authored names with the app and rules policy semantics.
 * @param {string} value Candidate display name.
 * @return {boolean} Whether the value is publishable.
 */
function isAllowedDisplayName(value) {
  const trimmed = value.trim();
  if (trimmed.length === 0 || Array.from(trimmed).length > 80) {
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
    const pattern = term.split("").join("[^a-z]*");
    return new RegExp(`(^|[^a-z])${pattern}([^a-z]|$)`, "u")
      .test(normalized);
  });
}

/**
 * Normalizes common separators, digits, and Unicode confusables.
 * @param {string} value Candidate display name.
 * @return {string} Screening representation.
 */
function normalizedForScreening(value) {
  const substitutions = {
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
  const substituted = Array.from(
    value
      .normalize("NFKD")
      .replace(/\p{Diacritic}/gu, "")
      .toLocaleLowerCase()
  ).map((character) => substitutions[character] ?? character)
    .join("");

  return substituted;
}

/**
 * Compares Firestore timestamps and primitive fields deterministically.
 * @param {unknown} lhs Existing field.
 * @param {unknown} rhs Desired field.
 * @return {boolean} Whether values are semantically equal.
 */
function valuesEqual(lhs, rhs) {
  return JSON.stringify(comparableValue(lhs)) ===
    JSON.stringify(comparableValue(rhs));
}

/**
 * Converts timestamp-like objects into a stable digest representation.
 * @param {unknown} value Candidate field.
 * @return {unknown} Stable comparable value.
 */
function comparableValue(value) {
  if (
    value &&
    typeof value === "object" &&
    typeof value.seconds === "number" &&
    typeof value.nanoseconds === "number"
  ) {
    return {
      nanoseconds: value.nanoseconds,
      seconds: value.seconds,
    };
  }
  if (
    value &&
    typeof value === "object" &&
    typeof value.toMillis === "function"
  ) {
    return value.toMillis();
  }
  return value;
}

/**
 * Identifies the reserved account-deletion sentinel.
 * @param {unknown} value Candidate stored name.
 * @return {boolean} Whether this is Anonymous Climber.
 */
function isAnonymousClimberName(value) {
  return typeof value === "string" &&
    normalizedForScreening(value)
      .replace(/[^a-z]/gu, "") === "anonymousclimber";
}

/**
 * Returns a bounded public HTTP(S) photo URL.
 * @param {unknown} value Candidate photo URL.
 * @return {string | null} Validated photo URL.
 */
function validPhotoURL(value) {
  const candidate = nonEmptyString(value);
  if (!candidate || candidate.length > 2048) {
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
 * Returns avatar initials for the resolved identity.
 * @param {string} displayName Resolved display name.
 * @return {string} Up to two initials.
 */
function avatarToken(displayName) {
  return displayName
    .trim()
    .split(/\s+/u)
    .slice(0, 2)
    .map((component) => Array.from(component)[0] ?? "")
    .join("")
    .toLocaleUpperCase();
}

/**
 * Returns a non-empty trimmed string.
 * @param {unknown} value Candidate value.
 * @return {string | null} Trimmed value.
 */
function nonEmptyString(value) {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

/**
 * Detects control scalars without a control-character RegExp.
 * @param {string} value Candidate uid.
 * @return {boolean} Whether the string contains a control scalar.
 */
function hasControlCharacter(value) {
  return Array.from(value).some((character) => {
    const codePoint = character.codePointAt(0) ?? 0;
    return codePoint <= 31 || codePoint === 127;
  });
}

/**
 * Requires a non-flag value after an argument.
 * @param {string[]} argv Process argv.
 * @param {number} index Value index.
 * @param {string} flag Argument name.
 * @return {string} Required argument value.
 */
function requiredValue(argv, index, flag) {
  const value = argv[index];
  if (!value || value.startsWith("--")) {
    throw new Error(`${flag} requires a value.`);
  }
  return value;
}
