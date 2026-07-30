import {onDocumentWritten} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import {
  ANONYMOUS_CLIMBER_NAME,
  PublicIdentity,
  PUBLIC_IDENTITY_POLICY_VERSION,
  PUBLIC_IDENTITY_STATE_DELETED,
  PUBLIC_IDENTITY_STATE_PENDING,
  PUBLIC_IDENTITY_STATE_PUBLISHED,
  PublicIdentityState,
  isAnonymousClimberName,
  publicIdentityFromData,
} from "./publicIdentity.js";

export type IdentityProjectionKind =
  "leaderboard" |
  "replayEntry" |
  "replayFinisher" |
  "firstAscent";

export const IDENTITY_PROPAGATION_PAGE_SIZE = 40;
const IDENTITY_PROPAGATION_JOB_COLLECTION =
  "_public_identity_propagation_jobs";
export const IDENTITY_PROJECTION_KINDS: IdentityProjectionKind[] = [
  "leaderboard",
  "replayEntry",
  "replayFinisher",
  "firstAscent",
];

export interface IdentityProjectionReference {
  kind: IdentityProjectionKind;
  path: string;
}

export interface IdentityPropagationJob {
  complete: boolean;
  cursor: string | null;
  kind: IdentityProjectionKind;
  sequence: number;
  sourceDeliveryId: string;
  sourceTransitionGeneration: string;
  sourceGeneration: string;
  userId: string;
}

export interface IdentityProjectionPage {
  hasMore: boolean;
  nextCursor: string | null;
  targets: IdentityProjectionReference[];
}

export interface IdentityPropagationJobSource {
  data: Record<string, unknown> | undefined;
  generation: string;
}

export interface IdentityPropagationJobTransaction {
  readJob(): Promise<IdentityPropagationJob | undefined>;
  readSource(): Promise<IdentityPropagationJobSource>;
  readTargets(
    targets: IdentityProjectionReference[]
  ): Promise<Map<string, Record<string, unknown> | undefined>>;
  updateJob(fields: Partial<IdentityPropagationJob>): void;
  updateTarget(
    target: IdentityProjectionReference,
    fields: Record<string, unknown>
  ): void;
}

export interface IdentityPropagationJobPort {
  listTargetPage(
    job: IdentityPropagationJob,
    pageSize: number
  ): Promise<IdentityProjectionPage>;
  runTransaction(
    operation: (
      transaction: IdentityPropagationJobTransaction
    ) => Promise<number>
  ): Promise<number>;
}

export interface IdentityPropagationTransaction {
  readSource(): Promise<Record<string, unknown> | undefined>;
  readTarget(
    target: IdentityProjectionReference
  ): Promise<Record<string, unknown> | undefined>;
  updateTarget(
    target: IdentityProjectionReference,
    fields: Record<string, unknown>
  ): void;
}

export interface IdentityPropagationPort {
  listTargets(userId: string): Promise<IdentityProjectionReference[]>;
  runTransaction(
    operation: (
      transaction: IdentityPropagationTransaction
    ) => Promise<boolean>
  ): Promise<boolean>;
}

interface CurrentPublicIdentity extends PublicIdentity {
  identityChangedAt: unknown;
  identityPolicyVersion: number;
  identityState: PublicIdentityState;
}

const PUBLIC_IDENTITY_SOURCE_FIELDS = [
  "displayName",
  "photoURL",
  "identityPolicyVersion",
  "identityChangedAt",
] as const;

export function publicIdentitySourceChanged(
  before: Record<string, unknown> | undefined,
  after: Record<string, unknown> | undefined
): boolean {
  if (before === undefined || after === undefined) {
    return before !== after;
  }
  return PUBLIC_IDENTITY_SOURCE_FIELDS.some((field) =>
    comparableIdentitySourceValue(before[field]) !==
      comparableIdentitySourceValue(after[field])
  );
}

/**
 * Reconciles every projection from the current source document.
 *
 * Event payloads gate demographic-only writes. A transaction rereads both the
 * source and target before each identity write, so an out-of-order event cannot
 * publish an older identity and a concurrent source edit forces a retry.
 */
export const onPublicProfileIdentityWritten = onDocumentWritten(
  {
    document: "users/{userId}/public_profile/current",
    retry: true,
  },
  async (event) => {
    if (
      !publicIdentitySourceChanged(
        event.data?.before.data(),
        event.data?.after.data()
      )
    ) {
      return;
    }
    await scheduleIdentityPropagationJobs(
      event.params.userId,
      event.id,
      sourceTransitionGeneration(
        event.data?.before,
        event.data?.after,
        event.id
      )
    );
  }
);

function comparableIdentitySourceValue(value: unknown): string {
  if (
    value !== null &&
    typeof value === "object" &&
    "seconds" in value &&
    "nanoseconds" in value &&
    typeof value.seconds === "number" &&
    typeof value.nanoseconds === "number"
  ) {
    return `${value.seconds}:${value.nanoseconds}`;
  }
  return JSON.stringify(value) ?? "undefined";
}

/**
 * Processes one bounded page for one projection kind.
 *
 * Each kind owns an independent checkpoint document. Updating its checkpoint
 * schedules the next page, so an account with many replay rows cannot starve
 * global rows, finishers, or First Ascents.
 */
export const onPublicIdentityPropagationJobWritten = onDocumentWritten(
  {
    document:
      `${IDENTITY_PROPAGATION_JOB_COLLECTION}/{userId}/kinds/{kind}`,
    retry: true,
  },
  async (event) => {
    const data = event.data?.after.data();
    const job = identityPropagationJobFromData(data);
    if (
      job === undefined ||
      job.complete ||
      job.userId !== event.params.userId ||
      job.kind !== event.params.kind
    ) {
      return;
    }

    await processIdentityPropagationJob(
      job,
      firestoreIdentityPropagationJobPort(job)
    );
  }
);

/**
 * Applies one bounded target page and advances only its kind checkpoint.
 * @param {IdentityPropagationJob} eventJob Trigger snapshot job.
 * @param {IdentityPropagationJobPort} port Persistence boundary.
 * @param {number} pageSize Maximum targets in this invocation.
 * @return {Promise<number>} Identity projections updated.
 */
export async function processIdentityPropagationJob(
  eventJob: IdentityPropagationJob,
  port: IdentityPropagationJobPort,
  pageSize = IDENTITY_PROPAGATION_PAGE_SIZE
): Promise<number> {
  const page = await port.listTargetPage(eventJob, pageSize);

  return port.runTransaction(async (transaction) => {
    const liveJob = await transaction.readJob();
    if (!isSamePendingJob(liveJob, eventJob)) {
      return 0;
    }

    const source = await transaction.readSource();
    if (source.generation !== eventJob.sourceGeneration) {
      transaction.updateJob({
        complete: false,
        cursor: null,
        sequence: eventJob.sequence + 1,
        sourceGeneration: source.generation,
      });
      return 0;
    }

    const targetData = await transaction.readTargets(page.targets);
    const identity = currentPublicIdentity(eventJob.userId, source.data);
    let writes = 0;

    for (const target of page.targets) {
      const data = targetData.get(target.path);
      if (
        data === undefined ||
        projectionOwner(target.kind, data) !== eventJob.userId
      ) {
        continue;
      }

      const fields = identityFieldsForProjection(
        target.kind,
        data,
        identity
      );
      if (fields !== null) {
        transaction.updateTarget(target, fields);
        writes += 1;
      }
    }

    transaction.updateJob({
      complete: !page.hasMore,
      cursor: page.nextCursor,
      sequence: eventJob.sequence + 1,
    });
    return writes;
  });
}

/**
 * Reconciles the target set supplied by a bounded adapter.
 *
 * Production uses the checkpointed job path above. This helper keeps the
 * transaction race behavior independently testable without a Firestore
 * trigger runtime.
 * @param {string} userId Firebase Auth uid.
 * @param {IdentityPropagationPort} port Transactional persistence boundary.
 * @return {Promise<number>} Number of projection writes committed.
 */
export async function propagateCurrentPublicIdentity(
  userId: string,
  port: IdentityPropagationPort
): Promise<number> {
  const targets = await port.listTargets(userId);
  if (targets.length > IDENTITY_PROPAGATION_PAGE_SIZE) {
    throw new Error(
      "Identity propagation adapters must provide one bounded target page."
    );
  }
  const results = await Promise.all(
    targets.map((target) => port.runTransaction(async (transaction) => {
      const [sourceData, targetData] = await Promise.all([
        transaction.readSource(),
        transaction.readTarget(target),
      ]);
      const source = currentPublicIdentity(userId, sourceData);
      if (
        targetData === undefined ||
        projectionOwner(target.kind, targetData) !== userId
      ) {
        return false;
      }

      const fields = identityFieldsForProjection(
        target.kind,
        targetData,
        source
      );
      if (fields === null) {
        return false;
      }

      transaction.updateTarget(target, fields);
      return true;
    }))
  );

  return results.filter(Boolean).length;
}

/**
 * Builds an update only when a real projection is stale.
 * @param {IdentityProjectionKind} kind Projection shape.
 * @param {Record<string, unknown>} data Existing document data.
 * @param {CurrentPublicIdentity} identity Validated current identity.
 * @return {Record<string, unknown> | null} Identity-only update or null.
 */
export function identityFieldsForProjection(
  kind: IdentityProjectionKind,
  data: Record<string, unknown>,
  identity: CurrentPublicIdentity
): Record<string, unknown> | null {
  if (isTrustedSyntheticProjection(kind, data)) {
    return null;
  }

  const displayNameField = kind === "firstAscent" ?
    "firstAscentDisplayName" :
    "displayName";
  const identityStateField = kind === "firstAscent" ?
    "firstAscentIdentityState" :
    "identityState";
  const targetState = data[identityStateField];

  if (targetState === PUBLIC_IDENTITY_STATE_DELETED) {
    return null;
  }

  if (isAnonymousClimberName(data[displayNameField])) {
    if (targetState !== PUBLIC_IDENTITY_STATE_PENDING) {
      return null;
    }
  }

  const desired = desiredIdentityFields(kind, identity);
  const isUnchanged = Object.entries(desired).every(
    ([field, value]) => data[field] === value
  );
  return isUnchanged ? null : desired;
}

/**
 * Resolves a policy-protected source document.
 * @param {string} userId Firebase Auth uid.
 * @param {Record<string, unknown> | undefined} data Current source fields.
 * @return {CurrentPublicIdentity | null} Current identity or a safe skip.
 */
function currentPublicIdentity(
  userId: string,
  data: Record<string, unknown> | undefined
): CurrentPublicIdentity {
  if (data === undefined) {
    return anonymousIdentity(PUBLIC_IDENTITY_STATE_PENDING);
  }

  if (isAnonymousClimberName(data.displayName)) {
    return anonymousIdentity(PUBLIC_IDENTITY_STATE_DELETED);
  }

  if (
    data.identityPolicyVersion !== PUBLIC_IDENTITY_POLICY_VERSION ||
    data.identityChangedAt === undefined ||
    data.identityChangedAt === null
  ) {
    return anonymousIdentity(PUBLIC_IDENTITY_STATE_PENDING);
  }

  return {
    ...publicIdentityFromData(userId, data),
    identityChangedAt: data.identityChangedAt,
    identityPolicyVersion: PUBLIC_IDENTITY_POLICY_VERSION,
    identityState: PUBLIC_IDENTITY_STATE_PUBLISHED,
  };
}

/**
 * Builds a non-publishable source identity with explicit lifecycle state.
 * @param {PublicIdentityState} identityState Pending or deleted state.
 * @return {CurrentPublicIdentity} Anonymous source identity.
 */
function anonymousIdentity(
  identityState: PublicIdentityState
): CurrentPublicIdentity {
  return {
    avatarToken: "",
    displayName: ANONYMOUS_CLIMBER_NAME,
    identityChangedAt: null,
    identityPolicyVersion: PUBLIC_IDENTITY_POLICY_VERSION,
    identityState,
    photoURL: null,
  };
}

/**
 * Returns the fields owned by identity propagation for a projection shape.
 * @param {IdentityProjectionKind} kind Projection shape.
 * @param {CurrentPublicIdentity} identity Validated current identity.
 * @return {Record<string, unknown>} Exact identity fields.
 */
function desiredIdentityFields(
  kind: IdentityProjectionKind,
  identity: CurrentPublicIdentity
): Record<string, unknown> {
  const photoURL = identity.photoURL ?? "";
  if (kind === "leaderboard") {
    return {
      displayName: identity.displayName,
      identityChangedAt: identity.identityChangedAt,
      identityPolicyVersion: identity.identityPolicyVersion,
      identityState: identity.identityState,
      photoURL,
    };
  }

  if (kind === "firstAscent") {
    return {
      firstAscentAvatarToken: identity.avatarToken,
      firstAscentDisplayName: identity.displayName,
      firstAscentIdentityState: identity.identityState,
      firstAscentIsSynthetic: false,
      firstAscentPhotoURL: photoURL,
    };
  }

  return {
    avatarToken: identity.avatarToken,
    displayName: identity.displayName,
    identityState: identity.identityState,
    isSynthetic: false,
    photoURL,
  };
}

/**
 * Returns the uid field owned by each projection shape.
 * @param {IdentityProjectionKind} kind Projection shape.
 * @param {Record<string, unknown>} data Current target fields.
 * @return {unknown} Stored projection owner.
 */
function projectionOwner(
  kind: IdentityProjectionKind,
  data: Record<string, unknown>
): unknown {
  return kind === "firstAscent" ? data.firstAscentUserId : data.userId;
}

/**
 * Preserves seeded competitors and deletion-anonymized projections verbatim.
 * @param {IdentityProjectionKind} kind Projection shape.
 * @param {Record<string, unknown>} data Existing document data.
 * @return {boolean} Whether the record is trusted synthetic content.
 */
function isTrustedSyntheticProjection(
  kind: IdentityProjectionKind,
  data: Record<string, unknown>
): boolean {
  if (kind !== "firstAscent") {
    return data.isSynthetic === true || data.source === "synthetic";
  }

  if (data.firstAscentIsSynthetic === true) {
    return true;
  }

  return data.source === "seeded" &&
    typeof data.seedPackId === "string" &&
    data.seedPackId.length > 0 &&
    typeof data.firstAscentUserId === "string" &&
    data.firstAscentUserId.startsWith("seeded:");
}

/**
 * Starts or resets one independent checkpoint per projection kind.
 * @param {string} userId Firebase Auth uid.
 * @param {string} sourceDeliveryId Unique Firestore trigger delivery id.
 * @param {string} transitionGeneration Version changed by this source event.
 */
async function scheduleIdentityPropagationJobs(
  userId: string,
  sourceDeliveryId: string,
  transitionGeneration: string
): Promise<void> {
  const firestore = admin.firestore();
  const userReference = firestore.collection("users").doc(userId);
  const sourceReference = publicProfileReference(firestore, userId);
  const jobReferences = IDENTITY_PROJECTION_KINDS.map((kind) =>
    identityPropagationJobReference(firestore, userId, kind)
  );

  await firestore.runTransaction(async (transaction) => {
    const [user, source, ...jobs] = await Promise.all([
      transaction.get(userReference),
      transaction.get(sourceReference),
      ...jobReferences.map((reference) => transaction.get(reference)),
    ]);

    // A delayed public-profile deletion can arrive after account cleanup. It
    // must remove leftover checkpoints, never recreate server-owned work for
    // an account whose root no longer exists.
    if (!shouldScheduleIdentityPropagationJobs(user.exists)) {
      for (const jobReference of jobReferences) {
        transaction.delete(jobReference);
      }
      return;
    }

    const sourceGeneration = snapshotGeneration(source);

    for (let index = 0; index < jobReferences.length; index += 1) {
      const kind = IDENTITY_PROJECTION_KINDS[index];
      const existing = identityPropagationJobFromData(jobs[index].data());
      const nextJob = scheduledIdentityPropagationJob(
        existing,
        userId,
        kind,
        sourceDeliveryId,
        transitionGeneration,
        sourceGeneration
      );
      if (nextJob === null) {
        continue;
      }

      transaction.set(jobReferences[index], {
        ...nextJob,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  });
}

/**
 * Keeps delayed source events from recreating work after account deletion.
 * @param {boolean} userRootExists Whether users/{uid} still exists.
 * @return {boolean} Whether the scheduler may create or reset checkpoints.
 */
export function shouldScheduleIdentityPropagationJobs(
  userRootExists: boolean
): boolean {
  return userRootExists;
}

/**
 * Resets a kind checkpoint for every unique source-trigger delivery.
 *
 * Source generations alone cannot identify a delete-create-delete ABA: both
 * deletion snapshots read as "missing". The delivery id makes trigger retries
 * idempotent while ensuring every distinct transition starts a fresh sweep.
 * @param {IdentityPropagationJob | undefined} existing Current checkpoint.
 * @param {string} userId Firebase Auth uid.
 * @param {IdentityProjectionKind} kind Projection kind.
 * @param {string} sourceDeliveryId Unique Firestore trigger delivery id.
 * @param {string} transitionGeneration Version changed by this source event.
 * @param {string} sourceGeneration Full-precision source version.
 * @return {IdentityPropagationJob | null} Reset job or idempotent no-op.
 */
export function scheduledIdentityPropagationJob(
  existing: IdentityPropagationJob | undefined,
  userId: string,
  kind: IdentityProjectionKind,
  sourceDeliveryId: string,
  transitionGeneration: string,
  sourceGeneration: string
): IdentityPropagationJob | null {
  if (existing?.sourceDeliveryId === sourceDeliveryId) {
    return null;
  }
  if (
    existing !== undefined &&
    !isNewerSourceTransition(
      transitionGeneration,
      existing.sourceTransitionGeneration
    )
  ) {
    return null;
  }

  return {
    complete: false,
    cursor: null,
    kind,
    sequence: (existing?.sequence ?? 0) + 1,
    sourceDeliveryId,
    sourceTransitionGeneration: transitionGeneration,
    sourceGeneration,
    userId,
  };
}

/**
 * Constructs the bounded Firestore job adapter.
 * @param {IdentityPropagationJob} job Current checkpoint.
 * @return {IdentityPropagationJobPort} Firestore persistence boundary.
 */
function firestoreIdentityPropagationJobPort(
  job: IdentityPropagationJob
): IdentityPropagationJobPort {
  const firestore = admin.firestore();
  const sourceReference = publicProfileReference(firestore, job.userId);
  const jobReference = identityPropagationJobReference(
    firestore,
    job.userId,
    job.kind
  );

  return {
    listTargetPage: (currentJob, pageSize) =>
      readIdentityProjectionPage(firestore, currentJob, pageSize),
    runTransaction: (operation) => firestore.runTransaction(
      async (transaction) => operation({
        readJob: async () => {
          const snapshot = await transaction.get(jobReference);
          return identityPropagationJobFromData(snapshot.data());
        },
        readSource: async () => {
          const snapshot = await transaction.get(sourceReference);
          return {
            data: snapshot.exists ? snapshot.data() : undefined,
            generation: snapshotGeneration(snapshot),
          };
        },
        readTargets: async (targets) => {
          const snapshots = await Promise.all(
            targets.map((target) =>
              transaction.get(firestore.doc(target.path))
            )
          );
          return new Map(snapshots.map((snapshot, index) => [
            targets[index].path,
            snapshot.exists ? snapshot.data() : undefined,
          ]));
        },
        updateJob: (fields) => {
          transaction.update(jobReference, {
            ...fields,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        },
        updateTarget: (target, fields) => {
          transaction.update(firestore.doc(target.path), fields);
        },
      })
    ),
  };
}

/**
 * Queries one deterministic page for a single projection kind.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {IdentityPropagationJob} job Current checkpoint.
 * @param {number} pageSize Maximum targets to process.
 * @return {Promise<IdentityProjectionPage>} Bounded target page.
 */
async function readIdentityProjectionPage(
  firestore: FirebaseFirestore.Firestore,
  job: IdentityPropagationJob,
  pageSize: number
): Promise<IdentityProjectionPage> {
  let query = identityProjectionQuery(firestore, job)
    .orderBy(admin.firestore.FieldPath.documentId())
    .limit(pageSize + 1);
  if (job.cursor !== null) {
    query = query.startAfter(job.cursor);
  }

  const snapshot = await query.get();
  const documents = snapshot.docs.slice(0, pageSize);
  const lastDocument = documents[documents.length - 1];

  return {
    hasMore: snapshot.docs.length > pageSize,
    nextCursor: lastDocument === undefined ?
      job.cursor :
      identityProjectionCursor(job.kind, lastDocument),
    targets: documents.map((document) => ({
      kind: job.kind,
      path: document.ref.path,
    })),
  };
}

/**
 * Returns the user-scoped query for one projection kind.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {IdentityPropagationJob} job Current checkpoint.
 * @return {FirebaseFirestore.Query} Projection query.
 */
function identityProjectionQuery(
  firestore: FirebaseFirestore.Firestore,
  job: IdentityPropagationJob
): FirebaseFirestore.Query {
  switch (job.kind) {
  case "leaderboard":
    return firestore
      .collection("leaderboard_stats")
      .where("userId", "==", job.userId);
  case "replayEntry":
    return firestore
      .collectionGroup("entries")
      .where("userId", "==", job.userId);
  case "replayFinisher":
    return firestore
      .collectionGroup("finishers")
      .where("userId", "==", job.userId);
  case "firstAscent":
    return firestore
      .collection("live_replay_leaderboards")
      .where("firstAscentUserId", "==", job.userId);
  }
}

/**
 * Returns the persisted cursor accepted by a document-ID ordered query.
 * @param {IdentityProjectionKind} kind Projection shape.
 * @param {FirebaseFirestore.QueryDocumentSnapshot} document Last document.
 * @return {string} Next-page cursor.
 */
function identityProjectionCursor(
  kind: IdentityProjectionKind,
  document: FirebaseFirestore.QueryDocumentSnapshot
): string {
  return kind === "replayEntry" || kind === "replayFinisher" ?
    document.ref.path :
    document.id;
}

/**
 * Parses an untrusted checkpoint document.
 * @param {Record<string, unknown> | undefined} data Stored fields.
 * @return {IdentityPropagationJob | undefined} Valid job.
 */
function identityPropagationJobFromData(
  data: Record<string, unknown> | undefined
): IdentityPropagationJob | undefined {
  if (
    data === undefined ||
    typeof data.complete !== "boolean" ||
    !(data.cursor === null || typeof data.cursor === "string") ||
    !isIdentityProjectionKind(data.kind) ||
    typeof data.sequence !== "number" ||
    !Number.isSafeInteger(data.sequence) ||
    data.sequence < 1 ||
    typeof data.sourceDeliveryId !== "string" ||
    data.sourceDeliveryId.length === 0 ||
    typeof data.sourceTransitionGeneration !== "string" ||
    data.sourceTransitionGeneration.length === 0 ||
    typeof data.sourceGeneration !== "string" ||
    typeof data.userId !== "string"
  ) {
    return undefined;
  }

  return {
    complete: data.complete,
    cursor: data.cursor,
    kind: data.kind,
    sequence: data.sequence,
    sourceDeliveryId: data.sourceDeliveryId,
    sourceTransitionGeneration: data.sourceTransitionGeneration,
    sourceGeneration: data.sourceGeneration,
    userId: data.userId,
  };
}

/**
 * Validates a projection-kind checkpoint discriminator.
 * @param {unknown} value Candidate kind.
 * @return {value is IdentityProjectionKind} Whether the kind is valid.
 */
function isIdentityProjectionKind(
  value: unknown
): value is IdentityProjectionKind {
  return typeof value === "string" &&
    IDENTITY_PROJECTION_KINDS.includes(value as IdentityProjectionKind);
}

/**
 * Prevents delayed job events from advancing a newer checkpoint.
 * @param {IdentityPropagationJob | undefined} live Current stored job.
 * @param {IdentityPropagationJob} eventJob Trigger snapshot job.
 * @return {boolean} Whether this event still owns the checkpoint.
 */
function isSamePendingJob(
  live: IdentityPropagationJob | undefined,
  eventJob: IdentityPropagationJob
): boolean {
  return live !== undefined &&
    !live.complete &&
    live.userId === eventJob.userId &&
    live.kind === eventJob.kind &&
    live.sequence === eventJob.sequence &&
    live.sourceDeliveryId === eventJob.sourceDeliveryId &&
    live.sourceTransitionGeneration ===
      eventJob.sourceTransitionGeneration &&
    live.sourceGeneration === eventJob.sourceGeneration &&
    live.cursor === eventJob.cursor;
}

/**
 * Uses source update time as a monotonic generation token.
 * @param {FirebaseFirestore.DocumentSnapshot} snapshot Source snapshot.
 * @return {string} Stable current-source generation.
 */
function snapshotGeneration(
  snapshot: FirebaseFirestore.DocumentSnapshot
): string {
  return snapshot.exists ?
    identitySourceGeneration(snapshot.updateTime) :
    identitySourceGeneration(undefined);
}

/**
 * Preserves Firestore nanosecond precision in checkpoint generation tokens.
 * @param {{seconds: number, nanoseconds: number} | undefined} updateTime
 *   Firestore source update time.
 * @return {string} Full-precision source generation.
 */
export function identitySourceGeneration(
  updateTime: {
    seconds: number;
    nanoseconds: number;
  } | undefined
): string {
  return updateTime === undefined ?
    "missing" :
    `present:${updateTime.seconds}:${updateTime.nanoseconds}`;
}

/**
 * Uses the version changed by the event, including a deletion's before image.
 *
 * Current source state alone cannot distinguish delete-create-delete because
 * both deletion deliveries reread a missing source.
 * @param {FirebaseFirestore.DocumentSnapshot | undefined} before Before image.
 * @param {FirebaseFirestore.DocumentSnapshot | undefined} after After image.
 * @param {string} deliveryId Fallback token for an impossible empty event.
 * @return {string} Monotonic transition generation.
 */
function sourceTransitionGeneration(
  before: FirebaseFirestore.DocumentSnapshot | undefined,
  after: FirebaseFirestore.DocumentSnapshot | undefined,
  deliveryId: string
): string {
  if (after?.exists) {
    return `${snapshotGeneration(after)}:write`;
  }
  if (before?.exists) {
    return `${snapshotGeneration(before)}:delete`;
  }
  return `delivery:${deliveryId}`;
}

/**
 * Rejects delayed source events while accepting every newer transition.
 * @param {string} candidate Incoming transition token.
 * @param {string} current Persisted transition token.
 * @return {boolean} Whether the incoming event can represent newer state.
 */
function isNewerSourceTransition(
  candidate: string,
  current: string
): boolean {
  const candidateVersion = parsePresentGeneration(candidate);
  const currentVersion = parsePresentGeneration(current);
  if (candidateVersion === null || currentVersion === null) {
    return candidate !== current;
  }
  if (candidateVersion.seconds !== currentVersion.seconds) {
    return candidateVersion.seconds > currentVersion.seconds;
  }
  if (candidateVersion.nanoseconds !== currentVersion.nanoseconds) {
    return candidateVersion.nanoseconds > currentVersion.nanoseconds;
  }
  return candidateVersion.phase > currentVersion.phase;
}

/**
 * Parses a full-precision present generation.
 * @param {string} value Generation token.
 * @return {{seconds: number, nanoseconds: number, phase: number} | null}
 *   Parsed timestamp and transition phase.
 */
function parsePresentGeneration(
  value: string
): {seconds: number; nanoseconds: number; phase: number} | null {
  const match = /^present:(\d+):(\d+):(write|delete)$/u.exec(value);
  if (match === null) {
    return null;
  }
  return {
    nanoseconds: Number(match[2]),
    phase: match[3] === "delete" ? 1 : 0,
    seconds: Number(match[1]),
  };
}

/**
 * Returns one server-only checkpoint document.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {string} userId Firebase Auth uid.
 * @param {IdentityProjectionKind} kind Projection shape.
 * @return {FirebaseFirestore.DocumentReference} Job document.
 */
function identityPropagationJobReference(
  firestore: FirebaseFirestore.Firestore,
  userId: string,
  kind: IdentityProjectionKind
): FirebaseFirestore.DocumentReference {
  return firestore
    .collection(IDENTITY_PROPAGATION_JOB_COLLECTION)
    .doc(userId)
    .collection("kinds")
    .doc(kind);
}

/**
 * Returns the single source-of-truth public mirror.
 * @param {FirebaseFirestore.Firestore} firestore Firestore instance.
 * @param {string} userId Firebase Auth uid.
 * @return {FirebaseFirestore.DocumentReference} Source reference.
 */
function publicProfileReference(
  firestore: FirebaseFirestore.Firestore,
  userId: string
): FirebaseFirestore.DocumentReference {
  return firestore
    .collection("users")
    .doc(userId)
    .collection("public_profile")
    .doc("current");
}
