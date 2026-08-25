/**
 * Fan-out primitives for work that touches one Firestore document per item.
 *
 * An unbounded `Promise.all` over a page of devices invites the very
 * RESOURCE_EXHAUSTED it then cannot survive, and it rejects on the first
 * failure while its siblings keep running - so the caller learns nothing about
 * which of them landed. Both properties matter wherever a partially applied
 * batch is worse than a slower one.
 */

/**
 * Runs one worker over many items with a bounded number in flight.
 *
 * Never rejects: a worker that throws costs its own item and nothing else, and
 * the failures come back so the caller can count or log them. Order of
 * completion is not the order of `items`.
 * @param {T[]} items Work items.
 * @param {number} limit Maximum workers in flight.
 * @param {Function} worker Work to run per item.
 * @return {Promise<Array>} One entry per item whose worker threw.
 */
export async function runWithBoundedConcurrency<T>(
  items: T[],
  limit: number,
  worker: (item: T) => Promise<void>
): Promise<Array<{error: unknown; item: T}>> {
  const failures: Array<{error: unknown; item: T}> = [];
  let next = 0;

  const lanes = Array.from(
    {length: Math.max(1, Math.min(limit, items.length))},
    async () => {
      while (next < items.length) {
        const item = items[next];
        next += 1;
        try {
          await worker(item);
        } catch (error) {
          failures.push({error, item});
        }
      }
    }
  );
  await Promise.all(lanes);

  return failures;
}

/**
 * Waits for a duration.
 * @param {number} milliseconds Delay duration.
 * @return {Promise<void>} Resolves after the delay.
 */
export function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
