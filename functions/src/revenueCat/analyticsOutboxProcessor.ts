import {MixpanelDeliveryError} from "./analyticsMixpanelClient";
import type {
  AnalyticsOutboxClaim,
  AnalyticsOutboxProcessingSummary,
  AnalyticsOutboxStore,
  LifecycleAnalyticsClient,
  RevenueCatAnalyticsEnvironment,
} from "./analyticsTypes";

const DEFAULT_BATCH_SIZE = 25;
// The scheduled worker is killed at 120 seconds and one Mixpanel request may
// take its full 10-second timeout, so deliveries stop early enough to release
// every claim this run will not attempt. A claim left in `processing` is
// otherwise invisible until the 15-minute stale sweep, which turns provider
// latency into a growing backlog instead of a draining one.
const DEFAULT_RUN_BUDGET_MS = 75 * 1000;
const INITIAL_RETRY_DELAY_MS = 60 * 1000;
const MAX_RETRY_DELAY_MS = 60 * 60 * 1000;

interface AnalyticsOutboxDependencies {
  store: AnalyticsOutboxStore;
  client: LifecycleAnalyticsClient;
  environment: RevenueCatAnalyticsEnvironment;
  now: () => Date;
  batchSize?: number;
  runBudgetMs?: number;
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
  const deadlineMs = startedAt.getTime() +
    (dependencies.runBudgetMs ?? DEFAULT_RUN_BUDGET_MS);
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
    deferredCount: 0,
  };

  for (const claim of claims) {
    const now = dependencies.now();
    if (now.getTime() >= deadlineMs) {
      await dependencies.store.requeue(
        claim,
        now,
        "run_deadline_reached",
        now
      );
      summary.deferredCount += 1;
      continue;
    }

    if (claim.event.firebaseProjectId !==
        dependencies.environment.firebaseProjectId ||
      claim.event.appEnvironment !==
        dependencies.environment.appEnvironment) {
      await dependencies.store.markFailed(
        claim,
        "environment_mismatch",
        dependencies.now()
      );
      reportPermanentFailure(claim, "environment_mismatch");
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
        reportPermanentFailure(claim, deliveryError.code);
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

function reportPermanentFailure(
  claim: AnalyticsOutboxClaim,
  errorCode: string
): void {
  console.error("RevenueCat analytics event was permanently discarded", {
    outboxId: claim.outboxId,
    eventName: claim.event.eventName,
    attemptCount: claim.attemptCount,
    lastErrorCode: errorCode,
  });
}

export function retryDelayMs(attemptCount: number): number {
  const exponent = Math.max(0, Math.min(attemptCount - 1, 6));
  return Math.min(
    INITIAL_RETRY_DELAY_MS * (2 ** exponent),
    MAX_RETRY_DELAY_MS
  );
}
