/**
 * Bounded, observable Firestore bulk reads and writes.
 *
 * This module exists because the Live Replay seed could not be told apart from a
 * dead process. Two separate defects produced the same symptom:
 *
 * 1. `db.bulkWriter()` strands its last few writes under load. Reproduced 6/6
 *    against staging: six processes each queued 20,000 writes, each settled
 *    ~19,985 of them, and every one of the six `close()` promises was still
 *    pending 90 seconds later - parked in the microtask queue at 0% CPU with no
 *    open connection. There is no deadline inside BulkWriter to reject them, so
 *    a seed that awaited `close()` waited forever.
 * 2. Nothing printed while any of it ran, so "working" and "wedged" looked
 *    identical from outside.
 *
 * So every network call here carries a deadline, every phase reports progress on
 * a clock, and a phase that stops making progress fails loudly instead of
 * hanging. A caller that never sees a line for longer than `stallMs` gets an
 * error naming the phase, not silence.
 *
 * It is also four times faster. `db.batch()` commits driven through a fixed
 * worker pool measured 20,030 docs/s against staging where an unthrottled
 * BulkWriter measured 2,952 docs/s, because BulkWriter serializes retries behind
 * its own rate limiter while a pool just keeps every slot busy.
 */

/** Firestore's hard cap on writes in one `db.batch()` commit. */
export const MAX_BATCH_WRITES = 500;

/** Deadline for any single Firestore call. Above this, the backend is not coming back. */
export const DEFAULT_TIMEOUT_MS = 30_000;

/**
 * How long a phase may make no progress at all before it is called wedged.
 *
 * Generous on purpose: a single commit may legitimately take most of
 * `DEFAULT_TIMEOUT_MS` and then be retried. What this catches is the failure
 * mode above - nothing settling, ever.
 */
export const DEFAULT_STALL_MS = 120_000;

/** How often a running phase prints where it has got to. */
export const DEFAULT_PROGRESS_INTERVAL_MS = 2_000;

/** Commits and reads in flight at once. Measured plateau; past this the backend, not the client, is the limit. */
export const DEFAULT_WRITE_CONCURRENCY = Number(process.env.ASCEND_SEED_WRITE_CONCURRENCY) || 96;

/** Parallel `listDocuments()` / `listCollections()` calls during enumeration. */
export const DEFAULT_READ_CONCURRENCY = 64;

/** Attempts per call before a phase gives up and says which document it gave up on. */
export const DEFAULT_ATTEMPTS = 6;

/**
 * gRPC codes worth trying again.
 *
 * ABORTED (10) is the common one under a fast seed - "Too much contention on
 * these documents" - and it is the backend asking for a moment, not a refusal.
 * A code that is not here is a refusal on the merits and will be refused just as
 * firmly on the sixth attempt.
 */
const RETRYABLE_CODES = new Set([
  1, // CANCELLED
  2, // UNKNOWN
  4, // DEADLINE_EXCEEDED
  8, // RESOURCE_EXHAUSTED
  10, // ABORTED
  13, // INTERNAL
  14, // UNAVAILABLE
  15, // DATA_LOSS
]);

/** Thrown when one Firestore call passes its deadline. */
export class FirestoreCallTimeoutError extends Error {
  /**
   * @param {string} description What the call was doing.
   * @param {number} timeoutMs The deadline it passed.
   */
  constructor(description, timeoutMs) {
    super(`${description} did not answer within ${timeoutMs}ms`);
    this.name = "FirestoreCallTimeoutError";
    this.description = description;
    this.timeoutMs = timeoutMs;
  }
}

/** Thrown when a whole phase stops making progress. */
export class PhaseStalledError extends Error {
  /**
   * @param {string} label The phase that stalled.
   * @param {number} stallMs How long it made no progress.
   * @param {string} detail What it had got to.
   */
  constructor(label, stallMs, detail) {
    super(
      `${label} made no progress for ${Math.round(stallMs / 1000)}s and was ` +
      `abandoned. Last known state: ${detail}`
    );
    this.name = "PhaseStalledError";
    this.label = label;
  }
}

/**
 * Runs one Firestore call under a deadline.
 *
 * Takes a factory rather than a promise so each retry starts a fresh call; the
 * timer is always cleared, so a resolved call never holds the event loop open.
 * @param {() => Promise<T>} start Starts the call.
 * @param {{timeoutMs?: number, description: string}} options Deadline and label.
 * @return {Promise<T>} The call's result.
 * @template T
 */
export async function withTimeout(start, {timeoutMs = DEFAULT_TIMEOUT_MS, description}) {
  let timer;
  try {
    return await Promise.race([
      start(),
      new Promise((_resolve, reject) => {
        timer = setTimeout(
          () => reject(new FirestoreCallTimeoutError(description, timeoutMs)),
          timeoutMs
        );
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Runs one Firestore call under a deadline, retrying what is worth retrying.
 * @param {() => Promise<T>} start Starts the call.
 * @param {object} options Retry and deadline settings.
 * @param {string} options.description What the call is doing, used in every message.
 * @param {number} [options.timeoutMs] Per-attempt deadline.
 * @param {number} [options.attempts] Attempts before giving up.
 * @param {() => void} [options.onRetry] Called once per retry.
 * @return {Promise<T>} The call's result.
 * @template T
 */
export async function withRetry(start, {
  description,
  timeoutMs = DEFAULT_TIMEOUT_MS,
  attempts = DEFAULT_ATTEMPTS,
  onRetry,
}) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      return await withTimeout(start, {timeoutMs, description});
    } catch (error) {
      const retryable = error instanceof FirestoreCallTimeoutError ||
        RETRYABLE_CODES.has(error?.code);
      if (!retryable || attempt >= attempts) {
        error.message = `${description} failed after ${attempt} attempt(s): ${error.message}`;
        throw error;
      }

      onRetry?.();
      await delay(Math.min(4_000, 100 * 2 ** attempt));
    }
  }
}

/**
 * Appends every item of `items` to `target`, whatever its length.
 *
 * `target.push(...items)` spreads the array into arguments, and a clear that
 * enumerated 300,000 documents crashed with `Maximum call stack size exceeded`
 * on exactly that line. There is no length at which this one stops working.
 * @param {T[]} target Array to append to.
 * @param {Iterable<T>} items Items to append.
 * @return {T[]} `target`.
 * @template T
 */
export function appendAll(target, items) {
  for (const item of items) {
    target.push(item);
  }
  return target;
}

/**
 * Runs `worker` over `items` with a fixed number of slots busy at once.
 *
 * A worker pool rather than `Promise.all` over everything: half a million
 * queued promises is how the previous implementation lost track of which ones
 * were outstanding.
 * @param {T[]} items Work items.
 * @param {number} concurrency Slots.
 * @param {(item: T, index: number) => Promise<void>} worker Per-item work.
 * @return {Promise<void>} Resolves when every item is done.
 * @template T
 */
export async function runPool(items, concurrency, worker) {
  let next = 0;
  const slots = Array.from({length: Math.max(1, Math.min(concurrency, items.length))}, async () => {
    for (;;) {
      const index = next;
      next += 1;
      if (index >= items.length) return;
      await worker(items[index], index);
    }
  });

  await Promise.all(slots);
}

/**
 * A progress line on a clock, and a deadline for making no progress at all.
 *
 * The captain could not tell a working seed from a dead one, so every phase gets
 * one of these. `advance` is what proves liveness: a phase that never calls it
 * is the one being watched for.
 * @param {object} options Reporter settings.
 * @param {string} options.label Phase name, printed on every line.
 * @param {number} [options.total] Expected unit count, for a percentage and an ETA.
 * @param {string} [options.unit] What is being counted.
 * @param {number} [options.stallMs] No-progress deadline.
 * @param {number} [options.intervalMs] How often to print.
 * @param {boolean} [options.quiet] Suppress the periodic line but keep the watchdog.
 * @return {object} Reporter handle.
 */
export function createProgressReporter({
  label,
  total = null,
  unit = "docs",
  stallMs = DEFAULT_STALL_MS,
  intervalMs = DEFAULT_PROGRESS_INTERVAL_MS,
  quiet = false,
} = {}) {
  const startedAt = Date.now();
  let done = 0;
  let retries = 0;
  let lastProgressAt = startedAt;
  let stalled = null;
  let note = "";

  const render = () => {
    const seconds = (Date.now() - startedAt) / 1000;
    const rate = seconds > 0 ? done / seconds : 0;
    const parts = [
      `${label}:`,
      total === null ?
        `${done.toLocaleString()} ${unit}` :
        `${done.toLocaleString()}/${total.toLocaleString()} ${unit} (${total > 0 ? Math.floor((done / total) * 100) : 100}%)`,
      `${Math.round(rate).toLocaleString()}/s`,
      `${seconds.toFixed(1)}s elapsed`,
    ];
    if (total !== null && rate > 0 && done < total) {
      parts.push(`eta ${Math.ceil((total - done) / rate)}s`);
    }
    if (retries > 0) parts.push(`${retries} retried`);
    if (note) parts.push(note);
    return parts.join(" ");
  };

  const timer = setInterval(() => {
    if (!quiet) console.log(`  ${render()}`);
    if (Date.now() - lastProgressAt > stallMs && stalled === null) {
      stalled = new PhaseStalledError(label, Date.now() - lastProgressAt, render());
      console.error(`  ${stalled.message}`);
    }
  }, intervalMs);
  timer.unref?.();

  return {
    /**
     * Records progress. Calling this is what proves the phase is alive.
     * @param {number} [count] Units completed since the last call.
     */
    advance(count = 1) {
      done += count;
      lastProgressAt = Date.now();
    },
    /** Records a retried call, so the printed line shows a struggling backend. */
    retried() {
      retries += 1;
      lastProgressAt = Date.now();
    },
    /**
     * Sets a suffix on the printed line.
     * @param {string} value Free text.
     */
    note(value) {
      note = value;
    },
    /** @return {Error | null} The stall, once the watchdog has seen one. */
    stall() {
      return stalled;
    },
    /** Throws if this phase has stalled. Called before every unit of work. */
    assertAlive() {
      if (stalled) throw stalled;
    },
    /** @return {number} Units completed. */
    count() {
      return done;
    },
    /** @return {number} Seconds since the phase started. */
    seconds() {
      return (Date.now() - startedAt) / 1000;
    },
    /**
     * Stops the clock and prints the phase's one summary line.
     * @param {string} [summary] Replaces the rendered line.
     * @return {number} Units completed.
     */
    finish(summary) {
      clearInterval(timer);
      const seconds = (Date.now() - startedAt) / 1000;
      const rate = seconds > 0 ? Math.round(done / seconds) : 0;
      console.log(
        `  ${label}: ${summary ?? `${done.toLocaleString()} ${unit}`} in ` +
        `${seconds.toFixed(1)}s (${rate.toLocaleString()}/s${retries > 0 ? `, ${retries} retried` : ""})`
      );
      return done;
    },
  };
}

/**
 * A write queue that commits `db.batch()` chunks through a worker pool.
 *
 * Deliberately not `db.bulkWriter()` - see this module's header. Operations are
 * buffered and flushed as full batches, so the caller enqueues half a million
 * writes without holding half a million promises.
 * @param {object} db Firestore instance.
 * @param {object} [options] Queue settings.
 * @param {number} [options.concurrency] Commits in flight.
 * @param {number} [options.batchSize] Writes per commit.
 * @param {number} [options.timeoutMs] Per-commit deadline.
 * @param {number} [options.attempts] Attempts per commit.
 * @param {object} [options.progress] Progress reporter to advance.
 * @return {object} Queue handle.
 */
export function createBatchWriter(db, {
  concurrency = DEFAULT_WRITE_CONCURRENCY,
  batchSize = MAX_BATCH_WRITES,
  timeoutMs = DEFAULT_TIMEOUT_MS,
  attempts = DEFAULT_ATTEMPTS,
  progress = null,
} = {}) {
  const size = Math.max(1, Math.min(batchSize, MAX_BATCH_WRITES));
  let pending = [];
  let inFlight = [];
  let queued = 0;

  const commit = async (operations) => {
    progress?.assertAlive();
    await withRetry(() => {
      const batch = db.batch();
      for (const operation of operations) {
        if (operation.kind === "set") {
          batch.set(operation.ref, operation.data, operation.options ?? {});
        } else if (operation.kind === "update") {
          batch.update(operation.ref, operation.data);
        } else {
          batch.delete(operation.ref);
        }
      }
      return batch.commit();
    }, {
      description: `commit of ${operations.length} write(s) starting at ${operations[0].ref.path}`,
      timeoutMs,
      attempts,
      onRetry: () => progress?.retried(),
    });
    progress?.advance(operations.length);
  };

  const drainInFlight = async () => {
    const chunks = inFlight;
    inFlight = [];
    await runPool(chunks, concurrency, commit);
  };

  const enqueue = (operation) => {
    queued += 1;
    pending.push(operation);
    if (pending.length >= size) {
      inFlight.push(pending);
      pending = [];
    }
  };

  return {
    /**
     * @param {object} ref Document reference.
     * @param {object} data Document data.
     * @param {object} [options] `set` options, e.g. `{merge: true}`.
     */
    set(ref, data, options) {
      enqueue({kind: "set", ref, data, options});
    },
    /**
     * @param {object} ref Document reference.
     * @param {object} data Fields to update.
     */
    update(ref, data) {
      enqueue({kind: "update", ref, data});
    },
    /** @param {object} ref Document reference to delete. */
    delete(ref) {
      enqueue({kind: "delete", ref});
    },
    /** @return {number} Operations enqueued so far. */
    queued() {
      return queued;
    },
    /**
     * Commits everything buffered so far without ending the queue.
     *
     * Called between phases so memory does not grow with the whole plan, and so
     * progress reflects work that has actually landed.
     * @return {Promise<void>} Resolves once every buffered write has committed.
     */
    async flush() {
      if (pending.length > 0) {
        inFlight.push(pending);
        pending = [];
      }
      await drainInFlight();
    },
    /**
     * Commits everything and returns the total.
     * @return {Promise<number>} Operations committed.
     */
    async drain() {
      await this.flush();
      return queued;
    },
  };
}

/**
 * Lists the documents under a set of collections, in parallel and under deadlines.
 *
 * The serial version of this is what made a clear take longer than the seed:
 * one `listDocuments()` per split bucket, awaited in a loop, is thousands of
 * round trips end to end.
 * @param {object[]} collections Collection references.
 * @param {object} [options] Read settings.
 * @param {number} [options.concurrency] Parallel listings.
 * @param {number} [options.timeoutMs] Per-listing deadline.
 * @param {object} [options.progress] Progress reporter to advance per collection.
 * @return {Promise<object[]>} Every document reference found.
 */
export async function listDocumentsAcross(collections, {
  concurrency = DEFAULT_READ_CONCURRENCY,
  timeoutMs = DEFAULT_TIMEOUT_MS,
  progress = null,
} = {}) {
  const found = [];
  await runPool(collections, concurrency, async (collection) => {
    progress?.assertAlive();
    const refs = await withRetry(() => collection.listDocuments(), {
      description: `listDocuments(${collection.path})`,
      timeoutMs,
      onRetry: () => progress?.retried(),
    });
    appendAll(found, refs);
    progress?.advance(1);
  });

  return found;
}

/**
 * Lists the subcollections of a set of documents, in parallel and under deadlines.
 * @param {object[]} documents Document references.
 * @param {object} [options] Read settings.
 * @param {number} [options.concurrency] Parallel listings.
 * @param {number} [options.timeoutMs] Per-listing deadline.
 * @param {object} [options.progress] Progress reporter to advance per document.
 * @return {Promise<object[]>} Every collection reference found.
 */
export async function listCollectionsAcross(documents, {
  concurrency = DEFAULT_READ_CONCURRENCY,
  timeoutMs = DEFAULT_TIMEOUT_MS,
  progress = null,
} = {}) {
  const found = [];
  await runPool(documents, concurrency, async (document) => {
    progress?.assertAlive();
    const refs = await withRetry(() => document.listCollections(), {
      description: `listCollections(${document.path})`,
      timeoutMs,
      onRetry: () => progress?.retried(),
    });
    appendAll(found, refs);
    progress?.advance(1);
  });

  return found;
}

/**
 * @param {number} ms Milliseconds to wait.
 * @return {Promise<void>} Resolves after the wait.
 */
function delay(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}
