import {MixpanelDeliveryError} from "./analyticsMixpanelClient";
import type {
  AnalyticsOutboxProcessingSummary,
  AnalyticsOutboxStore,
  LifecycleAnalyticsClient,
  RevenueCatAnalyticsEnvironment,
} from "./analyticsTypes";

const DEFAULT_BATCH_SIZE = 25;
const INITIAL_RETRY_DELAY_MS = 60 * 1000;
const MAX_RETRY_DELAY_MS = 60 * 60 * 1000;

interface AnalyticsOutboxDependencies {
  store: AnalyticsOutboxStore;
  client: LifecycleAnalyticsClient;
  environment: RevenueCatAnalyticsEnvironment;
  now: () => Date;
  batchSize?: number;
}

/**
 * Delivers due analytics rows independently of RevenueCat webhook responses.
 * @param {AnalyticsOutboxDependencies} dependencies - Delivery ports
 * @return {Promise<AnalyticsOutboxProcessingSummary>} Bounded run summary
 */
export async function processAnalyticsOutbox(
  dependencies: AnalyticsOutboxDependencies
): Promise<AnalyticsOutboxProcessingSummary> {
  const startedAt = dependencies.now();
  const batchSize = dependencies.batchSize ?? DEFAULT_BATCH_SIZE;
  const reclaimedCount = await dependencies.store.reclaimStale(
    startedAt,
    batchSize
  );
  const claims = await dependencies.store.claimDue(startedAt, batchSize);
  const summary: AnalyticsOutboxProcessingSummary = {
    reclaimedCount,
    claimedCount: claims.length,
    deliveredCount: 0,
    retriedCount: 0,
    failedCount: 0,
  };

  for (const claim of claims) {
    if (claim.event.firebaseProjectId !==
        dependencies.environment.firebaseProjectId ||
      claim.event.appEnvironment !==
        dependencies.environment.appEnvironment) {
      await dependencies.store.markFailed(
        claim,
        "environment_mismatch",
        dependencies.now()
      );
      summary.failedCount += 1;
      continue;
    }

    try {
      await dependencies.client.send(claim.event);
    } catch (error) {
      const deliveryError = error instanceof MixpanelDeliveryError ?
        error : new MixpanelDeliveryError(
          "unexpected_delivery_error",
          true
        );
      if (deliveryError.retryable) {
        await dependencies.store.requeue(
          claim,
          new Date(
            startedAt.getTime() + retryDelayMs(claim.attemptCount)
          ),
          deliveryError.code,
          dependencies.now()
        );
        summary.retriedCount += 1;
      } else {
        await dependencies.store.markFailed(
          claim,
          deliveryError.code,
          dependencies.now()
        );
        summary.failedCount += 1;
      }
      continue;
    }

    await dependencies.store.markDelivered(
      claim,
      dependencies.now()
    );
    summary.deliveredCount += 1;
  }

  return summary;
}

export function retryDelayMs(attemptCount: number): number {
  const exponent = Math.max(0, Math.min(attemptCount - 1, 6));
  return Math.min(
    INITIAL_RETRY_DELAY_MS * (2 ** exponent),
    MAX_RETRY_DELAY_MS
  );
}
