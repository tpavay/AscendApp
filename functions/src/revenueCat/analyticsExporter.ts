import * as admin from "firebase-admin";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {
  getMixpanelServerConfig,
  mixpanelServerConfig,
} from "./analyticsConfig";
import {
  analyticsEnvironmentForFirebaseProject,
} from "./analyticsEnvironment";
import {FirestoreAnalyticsOutboxStore} from "./analyticsFirestoreOutbox";
import {
  MixpanelLifecycleAnalyticsClient,
} from "./analyticsMixpanelClient";
import {processAnalyticsOutbox} from "./analyticsOutboxProcessor";

/**
 * Retries durable RevenueCat lifecycle analytics independently of the webhook.
 */
export const processRevenueCatAnalyticsOutbox = onSchedule(
  {
    schedule: "* * * * *",
    secrets: [mixpanelServerConfig],
    timeZone: "Etc/UTC",
    timeoutSeconds: 120,
  },
  async () => {
    const firebaseProjectId = admin.app().options.projectId;
    if (!firebaseProjectId) {
      throw new Error("Firebase project is unavailable to analytics exporter");
    }
    const environment = analyticsEnvironmentForFirebaseProject(
      firebaseProjectId,
      process.env.K_REVISION ?? "unknown"
    );
    const config = getMixpanelServerConfig();
    const summary = await processAnalyticsOutbox({
      store: new FirestoreAnalyticsOutboxStore(admin.firestore()),
      client: new MixpanelLifecycleAnalyticsClient(config, environment),
      environment,
      now: () => new Date(),
    });
    console.log("RevenueCat analytics outbox run completed", summary);
  }
);
