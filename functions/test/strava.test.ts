import test from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {
  mayConnectStrava,
  parseStravaAccessSettings,
} from "../src/strava/access.js";
import {
  APPLE_REFERENCE_DATE_OFFSET_SECONDS,
  buildStravaDescription,
  buildStravaTitle,
  buildTcx,
  parseHeartRateSidecar,
  stravaExternalId,
  type StravaActivityWorkout,
} from "../src/strava/activityFile.js";
import {
  failureKindForStatus,
  HttpStravaClient,
  isDuplicateUploadError,
  parseScopes,
  parseUploadStatus,
  StravaApiError,
  type StravaClient,
  type StravaUploadStatus,
} from "../src/strava/api.js";
import {
  parseStravaServerConfig,
  stravaCallbackScheme,
} from "../src/strava/config.js";
import {athleteDisplayName, needsRefresh} from "../src/strava/connections.js";
import {
  buildStravaAuthorizeUrl,
  checkStravaOAuthState,
  newStravaOAuthState,
} from "../src/strava/oauth.js";
import {
  isStravaUploadEligible,
  nextRateLimitWindow,
  processStravaUploadQueue,
  retryDelayMs,
  STRAVA_UPLOAD_MAX_ATTEMPTS,
  type StravaUploadClaim,
  type StravaUploadJobStore,
  type StravaUploadRetry,
} from "../src/strava/uploadProcessor.js";
import {
  parseStravaDeauthorization,
  stravaWebhookChallenge,
} from "../src/strava/webhook.js";

const CONFIG = {
  clientId: "12345",
  clientSecret: "shh-secret",
  redirectUri: "ascendapp://ascendstepper.com/strava",
  webhookVerifyToken: "verify-token-0123456789",
};

const WORKOUT: StravaActivityWorkout = {
  workoutId: "0f8a1c3e-1111-4222-8333-944455556666",
  name: "Empire State Building",
  startedAtMillis: Date.UTC(2026, 8, 29, 12, 0, 0),
  durationSeconds: 600,
  steps: 1576,
  floors: 86,
  notes: "",
  caloriesBurned: 142.6,
  avgHeartRateBpm: 151,
  maxHeartRateBpm: 178,
};

// MARK: config

test("an inert Strava config parses to null rather than throwing", () => {
  assert.equal(parseStravaServerConfig("{\"configured\": false}"), null);
});

test("a complete Strava config parses", () => {
  assert.deepEqual(parseStravaServerConfig(JSON.stringify(CONFIG)), CONFIG);
});

test("a half-filled Strava config fails loudly", () => {
  assert.throws(() => parseStravaServerConfig("{}"), /clientId/);
  assert.throws(() => parseStravaServerConfig("not json"), /valid JSON/);
  assert.throws(
    () => parseStravaServerConfig(JSON.stringify({
      ...CONFIG,
      redirectUri: "https://ascendstepper.com/strava",
    })),
    /redirectUri/
  );
  assert.throws(
    () => parseStravaServerConfig(JSON.stringify({
      ...CONFIG,
      webhookVerifyToken: "short",
    })),
    /webhookVerifyToken/
  );
});

test("each build's redirect hands the code back to that build", () => {
  for (const scheme of ["ascendapp", "ascendapp-stg", "ascendapp-dev"]) {
    const redirectUri = `${scheme}://ascendstepper.com/strava`;
    assert.deepEqual(
      parseStravaServerConfig(JSON.stringify({...CONFIG, redirectUri})),
      {...CONFIG, redirectUri}
    );
    assert.equal(stravaCallbackScheme(redirectUri), scheme);
  }
  assert.equal(stravaCallbackScheme("ascendapp-qa://ascendstepper.com/x"), null);
  assert.equal(stravaCallbackScheme("ascendapp:///strava"), null);
  assert.throws(
    () => parseStravaServerConfig(JSON.stringify({
      ...CONFIG,
      redirectUri: "someoneelse://ascendstepper.com/strava",
    })),
    /redirectUri/
  );
});

// MARK: access

test("Strava stays dark unless the switch is literally true", () => {
  for (const data of [undefined, null, {}, {enabled: "true"}, {enabled: 1}]) {
    const settings = parseStravaAccessSettings(data);
    assert.equal(settings.enabled, false);
  }
});

test("only allowlisted climbers may connect, and only while enabled", () => {
  const on = parseStravaAccessSettings({
    enabled: true,
    allowedUserIds: ["user-a", 7, "", null],
  });
  assert.equal(mayConnectStrava(on, "user-a"), true);
  assert.equal(mayConnectStrava(on, "user-b"), false);
  assert.deepEqual([...on.allowedUserIds], ["user-a"]);

  const off = parseStravaAccessSettings({
    enabled: false,
    allowedUserIds: ["user-a"],
  });
  assert.equal(mayConnectStrava(off, "user-a"), false);
});

// MARK: api parsing

test("upload ids survive past JavaScript's safe integer range", () => {
  const status = parseUploadStatus(
    "{\"id\": 90071992547409931, \"id_str\": \"90071992547409931\", " +
    "\"error\": null, \"status\": \"ready\", " +
    "\"activity_id\": 90071992547409933}"
  );
  assert.deepEqual(status, {
    uploadId: "90071992547409931",
    activityId: "90071992547409933",
    error: null,
  });
});

test("a still-processing upload has no activity id", () => {
  const status = parseUploadStatus(
    "{\"id\": 5, \"id_str\": \"5\", \"error\": null, \"activity_id\": null}"
  );
  assert.equal(status.activityId, null);
  assert.equal(status.uploadId, "5");
});

test("duplicate uploads are recognised", () => {
  assert.equal(
    isDuplicateUploadError("ascend-x.tcx duplicate of activity 21234316"),
    true
  );
  assert.equal(isDuplicateUploadError("Malformed TCX"), false);
});

test("Strava's scope string splits on commas and spaces", () => {
  assert.deepEqual(parseScopes("read,activity:write"),
    ["read", "activity:write"]);
  assert.deepEqual(parseScopes("read activity:write"),
    ["read", "activity:write"]);
  assert.deepEqual(parseScopes(undefined), []);
});

test("statuses map onto retry decisions", () => {
  assert.equal(failureKindForStatus(401), "unauthorized");
  assert.equal(failureKindForStatus(403), "unauthorized");
  assert.equal(failureKindForStatus(429), "rate_limited");
  assert.equal(failureKindForStatus(503), "transient");
  assert.equal(failureKindForStatus(422), "rejected");
});

// MARK: http client

interface RecordedRequest {
  url: string;
  init: RequestInit;
}

/**
 * A fetch that answers from a queue and records every request.
 * @param {Array<Response | Error>} responses Answers, in order.
 * @return {object} The fetch and its recorded requests.
 */
function fakeFetch(responses: Array<Response | Error>): {
  fetch: typeof fetch;
  requests: RecordedRequest[];
} {
  const requests: RecordedRequest[] = [];
  const fetchImpl = (async (url: string, init: RequestInit) => {
    requests.push({url, init});
    const next = responses.shift();
    if (!next) {
      throw new Error("no more responses");
    }
    if (next instanceof Error) {
      throw next;
    }
    return next;
  }) as unknown as typeof fetch;
  return {fetch: fetchImpl, requests};
}

test("the code exchange sends the secret and reads the athlete", async () => {
  const {fetch, requests} = fakeFetch([new Response(JSON.stringify({
    access_token: "access",
    refresh_token: "refresh",
    expires_at: 1_900_000_000,
    scope: "read,activity:write",
    athlete: {id: 987, firstname: "Elias", lastname: "Moreno"},
  }))]);
  const client = new HttpStravaClient(CONFIG, fetch);

  const authorization = await client.exchangeCode("abc123");

  assert.equal(requests[0].url, "https://www.strava.com/oauth/token");
  const body = new URLSearchParams(String(requests[0].init.body));
  assert.equal(body.get("client_secret"), "shh-secret");
  assert.equal(body.get("grant_type"), "authorization_code");
  assert.equal(body.get("code"), "abc123");
  assert.deepEqual(authorization, {
    accessToken: "access",
    refreshToken: "refresh",
    expiresAtMillis: 1_900_000_000_000,
    athleteId: "987",
    athleteFirstName: "Elias",
    athleteLastName: "Moreno",
    grantedScopes: ["read", "activity:write"],
  });
});

/**
 * A Strava fault body blaming one resource.
 * @param {string} resource The blamed resource.
 * @param {string} field The blamed field.
 * @param {number} status HTTP status.
 * @return {Response} The response.
 */
function fault(resource: string, field: string, status = 400): Response {
  return new Response(JSON.stringify({
    message: "Bad Request",
    errors: [{resource, field, code: "invalid"}],
  }), {status});
}

test("a refused refresh token reads as a revoked grant", async () => {
  const {fetch} = fakeFetch([
    fault("RefreshToken", "refresh_token"),
    fault("AuthorizationCode", "code"),
  ]);
  const client = new HttpStravaClient(CONFIG, fetch);

  await assert.rejects(client.refresh("dead"), (error: unknown) =>
    error instanceof StravaApiError && error.kind === "unauthorized");
  await assert.rejects(client.exchangeCode("spent"), (error: unknown) =>
    error instanceof StravaApiError && error.kind === "unauthorized");
});

test("a refused client secret never reads as a revoked grant", async () => {
  const {fetch} = fakeFetch([
    fault("Application", "client_secret"),
    fault("Application", "client_id", 401),
    new Response("{\"message\":\"Bad Request\"}", {status: 400}),
  ]);
  const client = new HttpStravaClient(CONFIG, fetch);

  for (let call = 0; call < 3; call += 1) {
    await assert.rejects(client.refresh("live"), (error: unknown) =>
      error instanceof StravaApiError && error.kind === "misconfigured");
  }
});

test("an upload refused for the app's credentials is not a revoke",
  async () => {
    const {fetch} = fakeFetch([
      fault("Application", "client_id", 401),
      fault("Athlete", "access_token", 401),
    ]);
    const client = new HttpStravaClient(CONFIG, fetch);

    await assert.rejects(client.getUpload("t", "1"), (error: unknown) =>
      error instanceof StravaApiError && error.kind === "misconfigured");
    await assert.rejects(client.getUpload("t", "1"), (error: unknown) =>
      error instanceof StravaApiError && error.kind === "unauthorized");
  });

test("revoke uses the new endpoint with Basic client credentials", async () => {
  const {fetch, requests} = fakeFetch([new Response("", {status: 200})]);
  const client = new HttpStravaClient(CONFIG, fetch);

  await client.revoke("refresh-token");

  assert.equal(requests[0].url, "https://www.strava.com/oauth/revoke");
  const headers = requests[0].init.headers as Record<string, string>;
  assert.equal(
    headers.Authorization,
    `Basic ${Buffer.from("12345:shh-secret").toString("base64")}`
  );
  assert.equal(String(requests[0].init.body), "token=refresh-token");
});

test("an upload is a StairStepper TCX with a stable external id", async () => {
  const {fetch, requests} = fakeFetch([new Response(
    "{\"id\": 11, \"id_str\": \"11\", \"error\": null, \"activity_id\": null}",
    {status: 201}
  )]);
  const client = new HttpStravaClient(CONFIG, fetch);

  const status = await client.createUpload("token", {
    name: "Empire State Building",
    description: "desc",
    externalId: "ascend-w1",
    tcx: "<xml/>",
  });

  assert.equal(status.uploadId, "11");
  assert.equal(requests[0].url, "https://www.strava.com/api/v3/uploads");
  const headers = requests[0].init.headers as Record<string, string>;
  assert.equal(headers.Authorization, "Bearer token");
  const form = requests[0].init.body as FormData;
  assert.equal(form.get("sport_type"), "StairStepper");
  assert.equal(form.get("trainer"), "1");
  assert.equal(form.get("data_type"), "tcx");
  assert.equal(form.get("external_id"), "ascend-w1");
  const file = form.get("file") as File;
  assert.equal(await file.text(), "<xml/>");
});

test("network failures and rate limits keep their meaning", async () => {
  const {fetch} = fakeFetch([
    new Error("socket hang up"),
    new Response("{}", {status: 429}),
  ]);
  const client = new HttpStravaClient(CONFIG, fetch);

  await assert.rejects(client.getUpload("t", "1"), (error: unknown) =>
    error instanceof StravaApiError && error.kind === "transient");
  await assert.rejects(client.getUpload("t", "1"), (error: unknown) =>
    error instanceof StravaApiError && error.kind === "rate_limited");
});

// MARK: activity file

test("the TCX carries heart rate and zero distance", () => {
  const tcx = buildTcx(WORKOUT, [
    {timestampMillis: WORKOUT.startedAtMillis, bpm: 120},
    {timestampMillis: WORKOUT.startedAtMillis + 60_000, bpm: 150},
  ]);
  assert.match(tcx, /<Activity Sport="Other">/);
  assert.match(tcx, /<Id>2026-09-29T12:00:00Z<\/Id>/);
  assert.match(tcx, /<TotalTimeSeconds>600<\/TotalTimeSeconds>/);
  assert.match(tcx, /<DistanceMeters>0<\/DistanceMeters>/);
  assert.match(tcx, /<Calories>143<\/Calories>/);
  assert.match(tcx,
    /<Trackpoint><Time>2026-09-29T12:01:00Z<\/Time><HeartRateBpm><Value>150/);
  // The TCX schema fixes the lap summary order.
  const order = ["TotalTimeSeconds", "DistanceMeters", "Calories",
    "AverageHeartRateBpm", "MaximumHeartRateBpm", "Intensity",
    "TriggerMethod", "Track"].map((tag) => tcx.indexOf(`<${tag}>`));
  assert.deepEqual(order, [...order].sort((a, b) => a - b));
});

test("a strap that connects late and drops early still spans the climb",
  () => {
    const start = WORKOUT.startedAtMillis;
    const tcx = buildTcx(WORKOUT, [
      {timestampMillis: start - 30_000, bpm: 95},
      {timestampMillis: start + 180_000, bpm: 130},
      {timestampMillis: start + 300_000, bpm: 150},
      {timestampMillis: start + 480_000, bpm: 160},
      {timestampMillis: start + 600_000 + 45_000, bpm: 110},
    ]);
    const points = [...tcx.matchAll(
      /<Trackpoint><Time>([^<]+)<\/Time>(?:<HeartRateBpm><Value>(\d+))?/g
    )].map((match) => [match[1], match[2]]);
    assert.deepEqual(points, [
      ["2026-09-29T12:00:00Z", "95"],
      ["2026-09-29T12:03:00Z", "130"],
      ["2026-09-29T12:05:00Z", "150"],
      ["2026-09-29T12:08:00Z", "160"],
      ["2026-09-29T12:10:00Z", "110"],
    ]);
  });

test("the track anchors carry the heart rate nearest each end", () => {
  const start = WORKOUT.startedAtMillis;
  const tcx = buildTcx(WORKOUT, [
    {timestampMillis: start + 180_000, bpm: 130},
    {timestampMillis: start + 480_000, bpm: 160},
  ]);
  const points = [...tcx.matchAll(
    /<Trackpoint><Time>([^<]+)<\/Time><HeartRateBpm><Value>(\d+)/g
  )].map((match) => [match[1], match[2]]);
  assert.deepEqual(points, [
    ["2026-09-29T12:00:00Z", "130"],
    ["2026-09-29T12:03:00Z", "130"],
    ["2026-09-29T12:08:00Z", "160"],
    ["2026-09-29T12:10:00Z", "160"],
  ]);
});

test("a climb with no heart rate still has a start and an end", () => {
  const tcx = buildTcx({...WORKOUT, avgHeartRateBpm: null,
    maxHeartRateBpm: null, caloriesBurned: null}, []);
  const points = tcx.match(/<Trackpoint>/g) ?? [];
  assert.equal(points.length, 2);
  assert.match(tcx, /2026-09-29T12:10:00Z/);
  assert.doesNotMatch(tcx, /HeartRateBpm/);
  assert.match(tcx, /<Calories>0<\/Calories>/);
});

test("the sidecar's Swift reference-date timestamps land inside the climb",
  () => {
    const referenceSeconds = WORKOUT.startedAtMillis / 1000 -
      APPLE_REFERENCE_DATE_OFFSET_SECONDS;
    const samples = parseHeartRateSidecar(JSON.stringify({
      schemaVersion: 1,
      workoutId: WORKOUT.workoutId,
      samples: [
        {timestamp: referenceSeconds + 30, heartRate: 140},
        {timestamp: referenceSeconds + 10, heartRate: 130},
        {timestamp: referenceSeconds - 3600, heartRate: 90},
        {timestamp: referenceSeconds + 20, heartRate: 400},
        {timestamp: "soon", heartRate: 120},
      ],
    }), WORKOUT);
    assert.deepEqual(samples, [
      {timestampMillis: WORKOUT.startedAtMillis + 10_000, bpm: 130},
      {timestampMillis: WORKOUT.startedAtMillis + 30_000, bpm: 140},
    ]);
  });

test("an unreadable sidecar yields no samples", () => {
  assert.deepEqual(parseHeartRateSidecar("{", WORKOUT), []);
  assert.deepEqual(parseHeartRateSidecar("{\"samples\": 3}", WORKOUT), []);
});

test("title and description come from the climb", () => {
  assert.equal(buildStravaTitle(WORKOUT), "Empire State Building");
  assert.equal(buildStravaTitle({...WORKOUT, name: "  "}), "Stair climb");
  assert.equal(
    buildStravaDescription({...WORKOUT, notes: "Legs gone."}),
    "1,576 steps · 86 floors\n158 steps/min\n\nLegs gone.\n\nClimbed in Ascend"
  );
  assert.equal(stravaExternalId("w1"), "ascend-w1");
});

// MARK: eligibility

const NOW = Date.UTC(2026, 8, 29, 13, 0, 0);
const ELIGIBLE = {
  source: "headphone_motion",
  steps: 1500,
  durationSeconds: 600,
  startedAtMillis: NOW - 30 * 60 * 1000,
  connectedAtMillis: NOW - 24 * 60 * 60 * 1000,
  nowMillis: NOW,
};

test("a fresh in-app climb after connecting is queued", () => {
  assert.equal(isStravaUploadEligible(ELIGIBLE), true);
});

test("legacy, empty, old and pre-connection climbs are not queued", () => {
  assert.equal(isStravaUploadEligible({...ELIGIBLE, source: "manual"}), false);
  assert.equal(
    isStravaUploadEligible({...ELIGIBLE, source: "apple_health"}),
    false
  );
  assert.equal(isStravaUploadEligible({...ELIGIBLE, steps: 0}), false);
  assert.equal(isStravaUploadEligible({...ELIGIBLE, durationSeconds: 0}),
    false);
  assert.equal(isStravaUploadEligible({...ELIGIBLE, startedAtMillis: null}),
    false);
  assert.equal(isStravaUploadEligible({
    ...ELIGIBLE,
    startedAtMillis: NOW - 3 * 24 * 60 * 60 * 1000,
    connectedAtMillis: NOW - 30 * 24 * 60 * 60 * 1000,
  }), false);
  assert.equal(isStravaUploadEligible({
    ...ELIGIBLE,
    connectedAtMillis: NOW - 5 * 60 * 1000,
  }), false);
});

// MARK: oauth

test("the consent URL asks only for activity:write on the mobile endpoint",
  () => {
    const url = new URL(buildStravaAuthorizeUrl(CONFIG, "state-token"));
    assert.equal(url.origin + url.pathname,
      "https://www.strava.com/oauth/mobile/authorize");
    assert.equal(url.searchParams.get("client_id"), "12345");
    assert.equal(url.searchParams.get("scope"), "activity:write");
    assert.equal(url.searchParams.get("redirect_uri"), CONFIG.redirectUri);
    assert.equal(url.searchParams.get("state"), "state-token");
    assert.equal(url.searchParams.get("response_type"), "code");
  });

test("state tokens are long and URL safe", () => {
  const state = newStravaOAuthState();
  assert.match(state, /^[A-Za-z0-9_-]{43}$/);
  assert.notEqual(state, newStravaOAuthState());
});

test("a state is honoured only for its own climber, before it expires", () => {
  const now = new Date(NOW);
  const fresh = {
    userId: "user-a",
    expiresAt: admin.firestore.Timestamp.fromMillis(NOW + 60_000),
  };
  assert.equal(checkStravaOAuthState(fresh, "user-a", now), "valid");
  assert.equal(checkStravaOAuthState(fresh, "user-b", now), "wrong_user");
  assert.equal(checkStravaOAuthState({
    ...fresh,
    expiresAt: admin.firestore.Timestamp.fromMillis(NOW - 1),
  }, "user-a", now), "expired");
  assert.equal(checkStravaOAuthState(undefined, "user-a", now), "missing");
});

// MARK: connections

test("the athlete is shown as first name and last initial", () => {
  assert.equal(athleteDisplayName("Elias", "Moreno"), "Elias M.");
  assert.equal(athleteDisplayName("Elias", ""), "Elias");
  assert.equal(athleteDisplayName("", ""), "");
});

test("a token is refreshed inside its last hour", () => {
  assert.equal(needsRefresh(NOW + 2 * 60 * 60 * 1000, NOW), false);
  assert.equal(needsRefresh(NOW + 30 * 60 * 1000, NOW), true);
});

// MARK: webhook

test("the webhook handshake echoes the challenge for the right token", () => {
  assert.deepEqual(stravaWebhookChallenge({
    "hub.mode": "subscribe",
    "hub.verify_token": CONFIG.webhookVerifyToken,
    "hub.challenge": "15f7d1a91c1f40f8a748fd134752feb3",
  }, CONFIG.webhookVerifyToken), {
    status: 200,
    body: {"hub.challenge": "15f7d1a91c1f40f8a748fd134752feb3"},
  });
  assert.equal(stravaWebhookChallenge({
    "hub.mode": "subscribe",
    "hub.verify_token": "wrong-token-000000000",
    "hub.challenge": "x",
  }, CONFIG.webhookVerifyToken).status, 403);
});

test("only an athlete deauthorization is acted on", () => {
  assert.equal(parseStravaDeauthorization({
    aspect_type: "update",
    object_type: "athlete",
    object_id: 134815,
    owner_id: 134815,
    subscription_id: 120475,
    updates: {authorized: "false"},
  }), "134815");
  assert.equal(parseStravaDeauthorization({
    aspect_type: "create",
    object_type: "activity",
    owner_id: 134815,
  }), null);
  assert.equal(parseStravaDeauthorization({
    aspect_type: "update",
    object_type: "athlete",
    owner_id: 134815,
    updates: {title: "x"},
  }), null);
  assert.equal(parseStravaDeauthorization("nonsense"), null);
});

// MARK: queue processor

interface FakeJob {
  claim: StravaUploadClaim;
  state: string;
  retry?: StravaUploadRetry;
  activityId?: string | null;
  duplicate?: boolean;
  errorCode?: string;
}

/**
 * An in-memory queue that hands out the given claims.
 * @param {Array<StravaUploadClaim>} claims Claims to hand out.
 * @return {object} The store and a per-job record of what happened.
 */
function fakeStore(claims: StravaUploadClaim[]): {
  store: StravaUploadJobStore;
  jobs: Map<string, FakeJob>;
} {
  const jobs = new Map<string, FakeJob>(claims.map((claim) =>
    [claim.jobId, {claim, state: "processing"}]));
  const store: StravaUploadJobStore = {
    reclaimStale: async () => 0,
    claimDue: async () => claims,
    release: async (claim) => {
      jobs.get(claim.jobId)!.state = "released";
    },
    requeue: async (claim, retry) => {
      Object.assign(jobs.get(claim.jobId)!, {state: "queued", retry});
    },
    markUploaded: async (claim, activityId, duplicate) => {
      Object.assign(jobs.get(claim.jobId)!,
        {state: "uploaded", activityId, duplicate});
    },
    markFailed: async (claim, errorCode) => {
      Object.assign(jobs.get(claim.jobId)!, {state: "failed", errorCode});
    },
  };
  return {store, jobs};
}

/**
 * A Strava client scripted per call.
 * @param {object} script Responses for uploads and status polls.
 * @return {object} The client and the uploads it received.
 */
function fakeClient(script: {
  create?: Array<StravaUploadStatus | Error>;
  get?: Array<StravaUploadStatus | Error>;
}): {client: StravaClient; created: string[]} {
  const created: string[] = [];
  const next = (queue: Array<StravaUploadStatus | Error> | undefined) => {
    const value = queue?.shift();
    if (!value) {
      throw new Error("unexpected Strava call");
    }
    if (value instanceof Error) {
      throw value;
    }
    return value;
  };
  return {
    created,
    client: {
      exchangeCode: async () => {
        throw new Error("unused");
      },
      refresh: async () => {
        throw new Error("unused");
      },
      revoke: async () => undefined,
      createUpload: async (_token, upload) => {
        created.push(upload.externalId);
        return next(script.create);
      },
      getUpload: async () => next(script.get),
    },
  };
}

/**
 * A claim for one climb.
 * @param {string} id Suffix for the ids.
 * @param {Partial<StravaUploadClaim>} overrides Field overrides.
 * @return {StravaUploadClaim} The claim.
 */
function claim(
  id: string,
  overrides: Partial<StravaUploadClaim> = {}
): StravaUploadClaim {
  return {
    jobId: `user-a__${id}`,
    claimId: `claim-${id}`,
    userId: "user-a",
    workoutId: id,
    attemptCount: 1,
    uploadId: null,
    ...overrides,
  };
}

/**
 * Runs the processor with fakes.
 * @param {object} options Claims, client script, and connection behaviour.
 * @return {Promise<object>} Summary, jobs, created uploads, disconnects.
 */
async function runQueue(options: {
  claims: StravaUploadClaim[];
  create?: Array<StravaUploadStatus | Error>;
  get?: Array<StravaUploadStatus | Error>;
  token?: string | null | Error;
  deletedWorkouts?: string[];
}) {
  const {store, jobs} = fakeStore(options.claims);
  const {client, created} = fakeClient({create: options.create,
    get: options.get});
  const disconnected: string[] = [];
  const summary = await processStravaUploadQueue({
    store,
    client,
    workouts: {
      read: async (_userId, workoutId) =>
        options.deletedWorkouts?.includes(workoutId) ?
          null :
          {workout: {...WORKOUT, workoutId}, heartRate: []},
    },
    connections: {
      accessToken: async () => {
        if (options.token instanceof Error) {
          throw options.token;
        }
        return options.token === undefined ? "token" : options.token;
      },
      disconnectRevoked: async (userId) => {
        disconnected.push(userId);
      },
    },
    now: () => new Date(NOW),
    sleep: async () => undefined,
  });
  return {summary, jobs, created, disconnected};
}

const READY = (id: string): StravaUploadStatus =>
  ({uploadId: `u-${id}`, activityId: `a-${id}`, error: null});
const PENDING = (id: string): StravaUploadStatus =>
  ({uploadId: `u-${id}`, activityId: null, error: null});

test("a climb Strava accepts is marked uploaded with its activity", async () => {
  const {summary, jobs, created} = await runQueue({
    claims: [claim("w1")],
    create: [PENDING("w1")],
    get: [READY("w1")],
  });
  assert.equal(summary.uploaded, 1);
  assert.deepEqual(created, ["ascend-w1"]);
  assert.equal(jobs.get("user-a__w1")?.state, "uploaded");
  assert.equal(jobs.get("user-a__w1")?.activityId, "a-w1");
});

test("a duplicate counts as uploaded, never as a failure", async () => {
  const {jobs} = await runQueue({
    claims: [claim("w1")],
    create: [{uploadId: "u", activityId: null,
      error: "ascend-w1.tcx duplicate of activity 99"}],
  });
  assert.equal(jobs.get("user-a__w1")?.state, "uploaded");
  assert.equal(jobs.get("user-a__w1")?.duplicate, true);
});

test("an upload still processing is rechecked, not re-posted", async () => {
  const {jobs} = await runQueue({
    claims: [claim("w1")],
    create: [PENDING("w1")],
    get: [PENDING("w1"), PENDING("w1"), PENDING("w1")],
  });
  const job = jobs.get("user-a__w1");
  assert.equal(job?.state, "queued");
  assert.equal(job?.retry?.uploadId, "u-w1");
  assert.equal(job?.retry?.refundAttempt, false);

  const {created, jobs: after} = await runQueue({
    claims: [claim("w1", {uploadId: "u-w1", attemptCount: 2})],
    get: [READY("w1")],
  });
  assert.deepEqual(created, []);
  assert.equal(after.get("user-a__w1")?.state, "uploaded");
});

test("a revoked grant disconnects the climber and stops the climb",
  async () => {
    const {jobs, disconnected} = await runQueue({
      claims: [claim("w1")],
      create: [new StravaApiError("unauthorized", 401, "revoked")],
    });
    assert.deepEqual(disconnected, ["user-a"]);
    assert.equal(jobs.get("user-a__w1")?.errorCode, "not_authorized");
  });

test("a refusal of the app's credentials retries and keeps the connection",
  async () => {
    const {jobs, disconnected} = await runQueue({
      claims: [claim("w1")],
      token: new StravaApiError("misconfigured", 400, "bad client secret"),
    });
    assert.deepEqual(disconnected, []);
    const job = jobs.get("user-a__w1");
    assert.equal(job?.state, "queued");
    assert.equal(job?.retry?.errorCode, "misconfigured");
    assert.equal(job?.retry?.readyAt.getTime(), NOW + retryDelayMs(1));
  });

test("a 429 refunds the attempt and holds the rest of the batch",
  async () => {
    const {summary, jobs} = await runQueue({
      claims: [claim("w1"), claim("w2")],
      create: [new StravaApiError("rate_limited", 429, "slow down")],
    });
    assert.equal(summary.rateLimited, true);
    const first = jobs.get("user-a__w1");
    assert.equal(first?.retry?.refundAttempt, true);
    assert.equal(first?.retry?.readyAt.getTime(),
      nextRateLimitWindow(new Date(NOW)).getTime());
    assert.equal(jobs.get("user-a__w2")?.state, "released");
    assert.equal(summary.deferred, 1);
  });

test("transient failures back off, then give up", async () => {
  const {jobs} = await runQueue({
    claims: [claim("w1")],
    create: [new StravaApiError("transient", 503, "down")],
  });
  assert.equal(jobs.get("user-a__w1")?.retry?.readyAt.getTime(),
    NOW + retryDelayMs(1));

  const {jobs: last} = await runQueue({
    claims: [claim("w1", {attemptCount: STRAVA_UPLOAD_MAX_ATTEMPTS})],
    create: [new StravaApiError("transient", 503, "down")],
  });
  assert.equal(last.get("user-a__w1")?.state, "failed");
  assert.equal(last.get("user-a__w1")?.errorCode, "transient");
});

test("a rejected file fails without retrying", async () => {
  const {jobs} = await runQueue({
    claims: [claim("w1")],
    create: [new StravaApiError("rejected", 400, "bad file")],
  });
  assert.equal(jobs.get("user-a__w1")?.errorCode, "rejected");
});

test("deleted climbs and disconnected climbers are dropped", async () => {
  const {jobs} = await runQueue({
    claims: [claim("w1")],
    deletedWorkouts: ["w1"],
  });
  assert.equal(jobs.get("user-a__w1")?.errorCode, "workout_deleted");

  const {jobs: gone} = await runQueue({claims: [claim("w2")], token: null});
  assert.equal(gone.get("user-a__w2")?.errorCode, "not_connected");
});

test("backoff grows and caps", () => {
  assert.equal(retryDelayMs(1), 60 * 1000);
  assert.equal(retryDelayMs(3), 15 * 60 * 1000);
  assert.equal(retryDelayMs(99), 6 * 60 * 60 * 1000);
  assert.equal(
    nextRateLimitWindow(new Date(Date.UTC(2026, 8, 29, 12, 7))).toISOString(),
    "2026-09-29T12:15:00.000Z"
  );
});
