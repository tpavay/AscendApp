import type {
  AppAccessProjection,
  RevenueCatProcessingOutcome,
  RevenueCatWebhookDependencies,
  RevenueCatWebhookEvent,
} from "./types";
import {buildAppAccessProjection} from "./subscriber";

/**
 * Claims, reconciles, and atomically completes one at-least-once event.
 * @param {RevenueCatWebhookEvent} event - Validated RevenueCat event
 * @param {string} payloadSha256 - Authenticated payload digest
 * @param {RevenueCatWebhookDependencies} dependencies - Trusted ports
 * @return {Promise<RevenueCatProcessingOutcome>} Processing disposition
 */
export async function processRevenueCatWebhookEvent(
  event: RevenueCatWebhookEvent,
  payloadSha256: string,
  dependencies: RevenueCatWebhookDependencies
): Promise<RevenueCatProcessingOutcome> {
  const startedAt = dependencies.now();
  const claim = await dependencies.store.claimEvent(
    event,
    payloadSha256,
    startedAt
  );
  if (claim !== "claimed") {
    return claim;
  }

  try {
    const verifiedUserIds = await verifiedFirebaseUserIds(
      event.appUserIds,
      dependencies
    );
    const projections = await Promise.all(verifiedUserIds.map(async (uid) => {
      const subscriber = await dependencies.subscriberClient.fetchSubscriber(
        uid
      );
      return buildAppAccessProjection(
        uid,
        subscriber,
        dependencies.config,
        event,
        dependencies.now()
      );
    }));
    await dependencies.store.completeEvent(
      event,
      payloadSha256,
      projections,
      dependencies.now()
    );
    return "processed";
  } catch (error) {
    await dependencies.store.failEvent(
      event.id,
      payloadSha256,
      errorCode(error),
      dependencies.now()
    );
    throw error;
  }
}

async function verifiedFirebaseUserIds(
  candidates: string[],
  dependencies: RevenueCatWebhookDependencies
): Promise<string[]> {
  const results = await Promise.all(candidates.map(async (uid) => ({
    uid,
    exists: await dependencies.userVerifier.isFirebaseUser(uid),
  })));
  return results.filter((result) => result.exists).map((result) => result.uid);
}

function errorCode(error: unknown): string {
  if (error instanceof Error) {
    if (error.name === "AbortError" || error.name === "TimeoutError") {
      return "subscriber_timeout";
    }
    if (error.name === "RevenueCatSubscriberFetchError") {
      return "subscriber_fetch_failed";
    }
  }
  return "processing_failed";
}

export function shouldReplaceProjection(
  existing: AppAccessProjection | undefined,
  candidate: AppAccessProjection
): boolean {
  return !existing ||
    candidate.revenueCatRequestDateMs >= existing.revenueCatRequestDateMs;
}
