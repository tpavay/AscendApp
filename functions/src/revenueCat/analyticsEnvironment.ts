import type {RevenueCatAnalyticsEnvironment} from "./analyticsTypes";

const PROJECT_DESTINATIONS = {
  "ascend-f2e4f": {
    appEnvironment: "dev",
    mixpanelProjectId: "4032860",
  },
  "ascend-staging-fa7d5": {
    appEnvironment: "staging",
    mixpanelProjectId: "4051102",
  },
  "ascend-prod-9c8f2": {
    appEnvironment: "production",
    mixpanelProjectId: "4051100",
  },
} as const;

const BUILD_NUMBER_PATTERN = /^[A-Za-z0-9._-]{1,100}$/;

/**
 * Resolves the only permitted Firebase-to-Mixpanel destination mapping.
 * @param {string} firebaseProjectId - Deployed Firebase project identifier
 * @param {string} revision - Cloud Run revision for producer attribution
 * @return {RevenueCatAnalyticsEnvironment} Required server envelope
 */
export function analyticsEnvironmentForFirebaseProject(
  firebaseProjectId: string,
  revision: string
): RevenueCatAnalyticsEnvironment {
  if (!isKnownFirebaseProject(firebaseProjectId)) {
    throw new Error("Unsupported Firebase project for analytics export");
  }
  const destination = PROJECT_DESTINATIONS[firebaseProjectId];
  return {
    firebaseProjectId,
    mixpanelProjectId: destination.mixpanelProjectId,
    appEnvironment: destination.appEnvironment,
    buildConfig: "server",
    appVersion: "cloud_functions",
    buildNumber: BUILD_NUMBER_PATTERN.test(revision) ? revision : "unknown",
  };
}

/**
 * Resolves the analytics destination for a caller that must not fail on it.
 *
 * Entitlement ingress owns paid access, so an unresolvable analytics
 * destination degrades the lifecycle export rather than rejecting the webhook
 * that projects the grant.
 * @param {string | undefined} firebaseProjectId - Deployed project, if known
 * @param {string} revision - Cloud Run revision for producer attribution
 * @return {RevenueCatAnalyticsEnvironment | null} Envelope, or null
 */
export function optionalAnalyticsEnvironment(
  firebaseProjectId: string | undefined,
  revision: string
): RevenueCatAnalyticsEnvironment | null {
  if (!firebaseProjectId || !isKnownFirebaseProject(firebaseProjectId)) {
    console.error("RevenueCat analytics destination is unresolved", {
      firebaseProjectId: firebaseProjectId ?? "unknown",
    });
    return null;
  }
  return analyticsEnvironmentForFirebaseProject(firebaseProjectId, revision);
}

function isKnownFirebaseProject(
  projectId: string
): projectId is keyof typeof PROJECT_DESTINATIONS {
  return Object.prototype.hasOwnProperty.call(PROJECT_DESTINATIONS, projectId);
}
