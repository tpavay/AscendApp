import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

/**
 * Flags headphone sessions whose heartbeat went silent.
 *
 * Every running Live Climb, Just Climb and Routine writes
 * `users/{uid}/attempt_heartbeats/{sessionID}` every sixty seconds
 * (`HeadphoneSessionCheckpointer`) and closes it with `state: ended` when the
 * climber saves or discards. A process iOS kills in the background writes
 * nothing more, so a heartbeat still `open` with a `lastSeenAt` more than five
 * minutes old is a session the phone stopped counting while the climber may
 * still be on the machine (2026-10-23: the Empire State climb that lost twenty
 * minutes would have been flagged at 11:27, nineteen minutes before the
 * climber found out herself). Each such session gets one row in
 * `attempt_heartbeat_flags/{uid}__{sessionID}` for the captain to query, and
 * its heartbeat is marked `stalled` so it is not flagged twice. A flagged
 * session that resumes or ends is resolved on the next run, so the flag also
 * records how the story finished.
 *
 * Reads go through a collection-group query (`firestore.indexes.json` holds its
 * `state`/`lastSeenAt` index); writes use the Admin SDK, since
 * `firestore.rules` lets no client claim `stalled` or touch the flags.
 */

export const ATTEMPT_HEARTBEATS_COLLECTION = "attempt_heartbeats";
export const ATTEMPT_HEARTBEAT_FLAGS_COLLECTION = "attempt_heartbeat_flags";

/** How long a heartbeat may be silent before its session is flagged. */
export const STALL_THRESHOLD_MS = 5 * 60 * 1_000;

/** How many stalled heartbeats one run flags, to bound the run. */
export const MAX_FLAGS_PER_RUN = 200;

/** How many unresolved flags one run re-examines. */
export const MAX_RESOLUTIONS_PER_RUN = 200;

export type HeartbeatState = "open" | "ended" | "stalled";

export interface HeartbeatDocument {
  schemaVersion?: number;
  sessionID?: string;
  mode?: string;
  steps?: number;
  durationSeconds?: number;
  startedAt?: admin.firestore.Timestamp;
  lastSeenAt?: admin.firestore.Timestamp;
  state?: HeartbeatState;
  endedAt?: admin.firestore.Timestamp | null;
  outcome?: string | null;
  climbId?: string | null;
  appVersion?: string | null;
  flaggedAt?: admin.firestore.Timestamp;
}

export interface StalledHeartbeat {
  userId: string;
  sessionID: string;
  document: HeartbeatDocument;
}

export interface FlagDocument {
  userId: string;
  sessionID: string;
  mode: string;
  steps: number;
  durationSeconds: number;
  startedAt: admin.firestore.Timestamp | null;
  lastSeenAt: admin.firestore.Timestamp | null;
  climbId: string | null;
  appVersion: string | null;
  stalledForSeconds: number;
  flaggedAt: admin.firestore.Timestamp;
  resolvedAt: admin.firestore.Timestamp | null;
  resolution: "resumed" | "ended" | null;
  outcome: string | null;
  resumedSteps: number | null;
  resumedDurationSeconds: number | null;
}

/**
 * Whether a heartbeat has been silent long enough to count as a stall.
 * @param {HeartbeatDocument} document The heartbeat.
 * @param {Date} now The run instant.
 * @return {boolean} True for an open heartbeat past the threshold.
 */
export function isStalled(document: HeartbeatDocument, now: Date): boolean {
  if (document.state !== "open") {
    return false;
  }
  const lastSeenAt = document.lastSeenAt?.toMillis();
  if (lastSeenAt === undefined) {
    return false;
  }
  return now.getTime() - lastSeenAt >= STALL_THRESHOLD_MS;
}

/**
 * The flag id for a session, unique across climbers.
 * @param {string} userId Owner uid.
 * @param {string} sessionID The session's id.
 * @return {string} `uid__sessionID`.
 */
export function flagId(userId: string, sessionID: string): string {
  return `${userId}__${sessionID}`;
}

/**
 * Builds the flag row for a stalled heartbeat.
 * @param {StalledHeartbeat} stalled The heartbeat and its owner.
 * @param {Date} now The run instant.
 * @return {FlagDocument} The row to write.
 */
export function buildFlag(
  stalled: StalledHeartbeat,
  now: Date
): FlagDocument {
  const {document} = stalled;
  const lastSeenMillis = document.lastSeenAt?.toMillis() ?? now.getTime();
  return {
    userId: stalled.userId,
    sessionID: stalled.sessionID,
    mode: document.mode ?? "unknown",
    steps: typeof document.steps === "number" ? document.steps : 0,
    durationSeconds:
      typeof document.durationSeconds === "number" ?
        document.durationSeconds :
        0,
    startedAt: document.startedAt ?? null,
    lastSeenAt: document.lastSeenAt ?? null,
    climbId: document.climbId ?? null,
    appVersion: document.appVersion ?? null,
    stalledForSeconds: Math.max(
      0,
      Math.round((now.getTime() - lastSeenMillis) / 1_000)
    ),
    flaggedAt: admin.firestore.Timestamp.fromDate(now),
    resolvedAt: null,
    resolution: null,
    outcome: null,
    resumedSteps: null,
    resumedDurationSeconds: null,
  };
}

/**
 * How a flagged session's heartbeat reads now, if it has moved on.
 *
 * A heartbeat the phone re-opened (the climber came back and the session
 * resumed) resolves as `resumed`; one the phone closed resolves as `ended`
 * with the climber's outcome. One still `stalled` stays unresolved.
 * @param {HeartbeatDocument | undefined} current The heartbeat now.
 * @return {object | null} The resolution patch, or null to leave it open.
 */
export function resolutionPatch(
  current: HeartbeatDocument | undefined
): Partial<FlagDocument> | null {
  if (!current) {
    // The heartbeat was swept with the account, or never re-written: nothing
    // to learn from it, so the flag stays as the last word.
    return null;
  }
  if (current.state === "open") {
    return {
      resolution: "resumed",
      resumedSteps: typeof current.steps === "number" ? current.steps : null,
      resumedDurationSeconds:
        typeof current.durationSeconds === "number" ?
          current.durationSeconds :
          null,
    };
  }
  if (current.state === "ended") {
    return {
      resolution: "ended",
      outcome: current.outcome ?? null,
      resumedSteps: typeof current.steps === "number" ? current.steps : null,
      resumedDurationSeconds:
        typeof current.durationSeconds === "number" ?
          current.durationSeconds :
          null,
    };
  }
  return null;
}

/** The Firestore operations the job needs, so the logic runs without one. */
export interface AttemptHeartbeatPort {
  listStalledHeartbeats(
    cutoff: Date,
    limit: number
  ): Promise<StalledHeartbeat[]>;
  writeFlag(flag: FlagDocument, markStalledAt: Date): Promise<void>;
  listUnresolvedFlags(
    limit: number
  ): Promise<Array<{id: string; flag: FlagDocument}>>;
  readHeartbeat(
    userId: string,
    sessionID: string
  ): Promise<HeartbeatDocument | undefined>;
  resolveFlag(
    id: string,
    patch: Partial<FlagDocument>,
    resolvedAt: Date
  ): Promise<void>;
}

export interface AttemptHeartbeatRunSummary {
  flagged: number;
  resolved: number;
  failures: string[];
}

/**
 * One run: flag every newly stalled heartbeat, then resolve the flags whose
 * sessions have since resumed or ended. Each item is isolated; one failure
 * costs that item and the run still reports it.
 * @param {Date} now The run instant.
 * @param {AttemptHeartbeatPort} port Firestore operations.
 * @return {Promise<AttemptHeartbeatRunSummary>} What the run did.
 */
export async function flagStalledHeartbeats(
  now: Date,
  port: AttemptHeartbeatPort
): Promise<AttemptHeartbeatRunSummary> {
  const summary: AttemptHeartbeatRunSummary = {
    flagged: 0,
    resolved: 0,
    failures: [],
  };
  const cutoff = new Date(now.getTime() - STALL_THRESHOLD_MS);

  let stalled: StalledHeartbeat[] = [];
  try {
    stalled = await port.listStalledHeartbeats(cutoff, MAX_FLAGS_PER_RUN);
  } catch (error) {
    summary.failures.push(`list: ${errorMessage(error)}`);
  }

  for (const heartbeat of stalled) {
    if (!isStalled(heartbeat.document, now)) {
      continue;
    }
    try {
      await port.writeFlag(buildFlag(heartbeat, now), now);
      summary.flagged += 1;
    } catch (error) {
      summary.failures.push(
        `flag ${flagId(heartbeat.userId, heartbeat.sessionID)}: ` +
          errorMessage(error)
      );
    }
  }

  let unresolved: Array<{id: string; flag: FlagDocument}> = [];
  try {
    unresolved = await port.listUnresolvedFlags(MAX_RESOLUTIONS_PER_RUN);
  } catch (error) {
    summary.failures.push(`list_unresolved: ${errorMessage(error)}`);
  }

  for (const {id, flag} of unresolved) {
    try {
      const current = await port.readHeartbeat(flag.userId, flag.sessionID);
      const patch = resolutionPatch(current);
      if (!patch) {
        continue;
      }
      await port.resolveFlag(id, patch, now);
      summary.resolved += 1;
    } catch (error) {
      summary.failures.push(`resolve ${id}: ${errorMessage(error)}`);
    }
  }

  return summary;
}

/**
 * Builds the Admin SDK backed port.
 * @param {admin.firestore.Firestore} firestore Handle to read and write.
 * @return {AttemptHeartbeatPort} Production port.
 */
export function makeAdminPort(
  firestore: admin.firestore.Firestore = admin.firestore()
): AttemptHeartbeatPort {
  return {
    async listStalledHeartbeats(cutoff, limit) {
      const snapshot = await firestore
        .collectionGroup(ATTEMPT_HEARTBEATS_COLLECTION)
        .where("state", "==", "open")
        .where(
          "lastSeenAt",
          "<",
          admin.firestore.Timestamp.fromDate(cutoff)
        )
        .limit(limit)
        .get();

      return snapshot.docs.flatMap((document) => {
        const userId = document.ref.parent.parent?.id;
        if (!userId) {
          return [];
        }
        return [{
          userId,
          sessionID: document.id,
          document: document.data() as HeartbeatDocument,
        }];
      });
    },

    async writeFlag(flag, markStalledAt) {
      const batch = firestore.batch();
      batch.set(
        firestore
          .collection(ATTEMPT_HEARTBEAT_FLAGS_COLLECTION)
          .doc(flagId(flag.userId, flag.sessionID)),
        flag,
        {merge: true}
      );
      batch.set(
        firestore
          .collection("users")
          .doc(flag.userId)
          .collection(ATTEMPT_HEARTBEATS_COLLECTION)
          .doc(flag.sessionID),
        {
          state: "stalled",
          flaggedAt: admin.firestore.Timestamp.fromDate(markStalledAt),
        },
        {merge: true}
      );
      await batch.commit();
    },

    async listUnresolvedFlags(limit) {
      const snapshot = await firestore
        .collection(ATTEMPT_HEARTBEAT_FLAGS_COLLECTION)
        .where("resolvedAt", "==", null)
        .limit(limit)
        .get();
      return snapshot.docs.map((document) => ({
        id: document.id,
        flag: document.data() as FlagDocument,
      }));
    },

    async readHeartbeat(userId, sessionID) {
      const snapshot = await firestore
        .collection("users")
        .doc(userId)
        .collection(ATTEMPT_HEARTBEATS_COLLECTION)
        .doc(sessionID)
        .get();
      return snapshot.exists ?
        (snapshot.data() as HeartbeatDocument) :
        undefined;
    },

    async resolveFlag(id, patch, resolvedAt) {
      await firestore
        .collection(ATTEMPT_HEARTBEAT_FLAGS_COLLECTION)
        .doc(id)
        .set(
          {
            ...patch,
            resolvedAt: admin.firestore.Timestamp.fromDate(resolvedAt),
          },
          {merge: true}
        );
    },
  };
}

/**
 * The scheduled entry point: every five minutes, which is also the stall
 * threshold, so a session is flagged five to ten minutes after its last
 * heartbeat.
 */
export const flagStalledAttemptHeartbeats = onSchedule(
  {
    schedule: "*/5 * * * *",
    timeZone: "Etc/UTC",
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async () => {
    const summary = await flagStalledHeartbeats(new Date(), makeAdminPort());
    if (summary.flagged > 0 || summary.failures.length > 0) {
      logger.warn("attemptHeartbeats.run", summary);
    } else {
      logger.info("attemptHeartbeats.run", summary);
    }
    if (summary.failures.length > 0) {
      throw new Error(
        `attempt heartbeat run had ${summary.failures.length} failure(s)`
      );
    }
  }
);

/**
 * A readable error message.
 * @param {unknown} error Whatever was thrown.
 * @return {string} Its message.
 */
function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export const attemptHeartbeatTestHooks = {
  buildFlag,
  flagId,
  flagStalledHeartbeats,
  isStalled,
  resolutionPatch,
};
