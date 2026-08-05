import type {MixpanelServerConfig} from "./analyticsConfig";
import type {
  LifecycleAnalyticsClient,
  LifecycleAnalyticsEvent,
  RevenueCatAnalyticsEnvironment,
} from "./analyticsTypes";

const MIXPANEL_IMPORT_URL = "https://api.mixpanel.com/import";
const MIXPANEL_TIMEOUT_MS = 10_000;

export class MixpanelLifecycleAnalyticsClient
implements LifecycleAnalyticsClient {
  constructor(
    private readonly config: MixpanelServerConfig,
    private readonly environment: RevenueCatAnalyticsEnvironment,
    private readonly fetchImplementation: typeof fetch = fetch
  ) {}

  async send(event: LifecycleAnalyticsEvent): Promise<void> {
    if (event.firebaseProjectId !== this.environment.firebaseProjectId ||
      event.appEnvironment !== this.environment.appEnvironment) {
      throw new MixpanelDeliveryError("environment_mismatch", false);
    }

    const url = new URL(MIXPANEL_IMPORT_URL);
    url.searchParams.set("strict", "1");
    url.searchParams.set("project_id", this.environment.mixpanelProjectId);
    const credential = Buffer.from(
      `${this.config.serviceAccountUsername}:` +
      this.config.serviceAccountPassword,
      "utf8"
    ).toString("base64");
    let response: Response;
    try {
      response = await this.fetchImplementation(url, {
        method: "POST",
        headers: {
          "Authorization": `Basic ${credential}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify([mixpanelEvent(event)]),
        signal: AbortSignal.timeout(MIXPANEL_TIMEOUT_MS),
      });
    } catch {
      throw new MixpanelDeliveryError("network_failure", true);
    }

    if (!response.ok) {
      throw new MixpanelDeliveryError(
        response.status === 400 ? "validation_failed" :
          `http_${response.status}`,
        response.status !== 400,
        response.status
      );
    }

    let result: unknown;
    try {
      result = await response.json() as unknown;
    } catch {
      throw new MixpanelDeliveryError("invalid_response", true);
    }
    if (!isRecord(result) ||
      result.code !== 200 ||
      result.num_records_imported !== 1) {
      throw new MixpanelDeliveryError("import_not_confirmed", true);
    }
  }
}

export class MixpanelDeliveryError extends Error {
  constructor(
    readonly code: string,
    readonly retryable: boolean,
    readonly status: number | null = null
  ) {
    super(code);
    this.name = "MixpanelDeliveryError";
  }
}

function mixpanelEvent(event: LifecycleAnalyticsEvent): {
  event: string;
  properties: Record<string, string | number | boolean | null>;
} {
  return {
    event: event.eventName,
    properties: {
      "time": event.eventTimestampMs,
      "distinct_id": event.distinctId,
      "$insert_id": event.insertId,
      "ip": 0,
      "source": event.source,
      "event_version": event.eventVersion,
      "entitlement_id": event.entitlementId,
      "product_id": event.productId,
      "previous_product_id": event.previousProductId,
      "store": event.store,
      "period_type": event.periodType,
      "lifecycle_reason": event.lifecycleReason,
      "refund_attributed": event.refundAttributed,
      "entitlement_active": event.entitlementActive,
      "effective_expiration_at_ms": event.effectiveExpirationAtMs,
      "app_environment": event.appEnvironment,
      "build_config": event.buildConfig,
      "app_version": event.appVersion,
      "build_number": event.buildNumber,
    },
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}
