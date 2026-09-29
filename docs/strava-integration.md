# Strava integration

A connected climber's finished climbs are sent to their Strava account as Stair-Stepper activities.
Ascend only ever writes to Strava: it asks for the `activity:write` scope alone and reads nothing back.
This page is the operator's guide: how the pieces fit, how to turn it on, and what Strava's terms require.

## What Strava allows, and why there is an allowlist

Strava gives every API application a fixed athlete capacity.
A new app holds 1 athlete, the owner can self-upgrade to 10 from the Strava API dashboard, and anything beyond 10 needs Strava's Developer Program review, which is free, has no guaranteed turnaround, and can be refused.
Strava refuses to authorize an athlete past the capacity, so offering "Connect" to everyone would break the button for the eleventh climber.
Since 2026-06-01 the Strava account that owns the API app must also hold a paid Strava subscription for any app below 10,000 athletes.

One Strava account may own only one API application, so a single app serves dev, staging and production, and its capacity is shared across all three.

Sources, all read on 2026-09-29: <https://developers.strava.com/docs/rate-limits/>, <https://www.strava.com/legal/api_policy> (effective 2026-06-01), <https://www.strava.com/legal/api>, <https://developers.strava.com/guidelines/>, and Strava's API FAQ at <https://communityhub.strava.com/developers-knowledge-base-14/strava-api-faq-12906>.

## How it works

Everything that touches a Strava credential runs in Cloud Functions (`functions/src/strava/`).
The app only starts and ends a connection.

1. **Status.** The Integrations screen calls `stravaGetStatus`.
   The Strava card appears only when the climber may connect or is already connected; for everyone else there is nothing on screen.
2. **Connect.** `stravaBeginConnect` refuses anyone the access settings do not name, then stores a single-use state in `_strava_oauth_states` and returns Strava's mobile consent URL.
   The app opens it in an `ASWebAuthenticationSession`, Strava redirects to `ascendapp://<callback domain>/...`, and the session hands the URL back to the app.
   `stravaCompleteConnect` consumes the state (it must belong to the caller and be under ten minutes old), re-checks access, exchanges the code with the client secret, requires `activity:write` among the granted scopes, and stores the tokens in `_strava_connections/{uid}`.
3. **Queue.** `onWorkoutWrittenStravaUpload` watches `users/{uid}/workouts/{workoutId}`.
   A connected climber's climb is queued once in `_strava_upload_jobs` when it was recorded in Ascend (`source == headphone_motion`), has steps and a duration, started after the connection was made, and started within the last 48 hours.
   Legacy manual and Apple Health rows are never sent, and connecting never back-fills history.
4. **Upload.** `processStravaUploads` runs every five minutes.
   A queued climb waits ten minutes first, because Apple Health heart rate arrives after the workout does and Strava refuses a second upload of the same climb.
   The worker builds a TCX file on the server from the canonical workout document and its heart-rate sidecar, never from anything the app sends, and posts it to `POST /uploads` as `sport_type=StairStepper`, `trainer=1`, with `external_id=ascend-<workoutId>`.
   Distance is zero on purpose: a stair stepper covers no ground.
   The worker polls the upload briefly, rechecks later if Strava is still processing, treats a duplicate as success, backs off on network and 5xx failures for up to eight attempts, refunds the attempt and waits for the next quarter hour on a 429, and disconnects the climber on a 401.
5. **Disconnect.** `stravaDisconnect` revokes Ascend at Strava through `POST /oauth/revoke`, then deletes the token, pending states and every queue row for that climber.
   A Strava outage never blocks it.
6. **Revoked on Strava.** `stravaWebhook` receives Strava's athlete deauthorization event.
   Strava does not sign webhook events, so the handler proves the revoke by refreshing the stored token: a live grant answers and the event is ignored, a revoked one is refused and the connection is deleted.
   A 401 during an upload deletes the connection too, which covers any environment the webhook does not point at.
7. **Account deletion.** `cleanupDeletedUserData` revokes and deletes the Strava connection along with everything else.

Completed queue rows hold a Strava activity id, which Strava's API Policy lets Ascend keep for at most seven days.
Every row carries `retainUntil` five days after its last transition, and the Firestore TTL policy on it deletes the row.

## The switch and the allowlist

`_strava_access/settings` decides who may use Strava:

```json
{"enabled": true, "allowedUserIds": ["<uid>", "<uid>"]}
```

`enabled` is the kill switch and ships off: a missing document, a missing field, or anything but a literal `true` keeps every Strava call dark.
While it is off no new connection can start and the upload worker does not run, so queued climbs stay exactly where they are and drain when it comes back on.
A connected climber can still see and end their connection.
It lives in Firestore rather than Remote Config because every Strava decision is made in a Cloud Function, and because the app's Remote Config switches all ship on - the automatic publisher refuses to run while any of them is off.

`allowedUserIds` is who may start a connection.
Removing somebody stops them starting a new one; a connection they already made stays until they disconnect.

Manage both with the script, which dry-runs unless given `--apply` and refuses to allowlist more climbers than the capacity Strava has granted (10 unless `--capacity` says otherwise):

```bash
cd scripts && npm install
node strava-access.mjs show --env dev
node strava-access.mjs allow --env dev --email climber@example.com --apply
node strava-access.mjs enable --env dev --apply
node strava-access.mjs disable --env prod --confirm-production --apply
```

`show` also lists who is connected, which is what Strava counts against the capacity.

## Configuration

### The secret

`STRAVA_SERVER_CONFIG` is a JSON Functions secret:

```json
{
  "clientId": "123456",
  "clientSecret": "<from the Strava API dashboard>",
  "redirectUri": "ascendapp://<Authorization Callback Domain>/strava",
  "webhookVerifyToken": "<at least 16 random characters>"
}
```

The `redirectUri` host must equal the "Authorization Callback Domain" set on the Strava API app, and its scheme must be the app's registered `ascendapp` scheme.
A project that must stay inert holds `{"configured": false}`: every Strava surface then reports unavailable instead of failing.
It is pinned in `functions/secret-versions.json` like every other secret, so staging and production need a version created and pinned before the first deploy that carries these functions - follow `docs/functions-secret-versions.md`, and create the inert value there until the integration is meant to be live in that project.
Never type the client secret into a command argument or a file; read it with `read -rs` and pipe it into `gcloud secrets versions add`.

### The Strava API app

At <https://www.strava.com/settings/api>, on the account that holds the Strava subscription:

- Upgrade the capacity to 10 athletes.
- Set the Authorization Callback Domain to the host in `redirectUri`.
- Copy the Client ID and Client Secret into the secret above.

### The webhook

Strava allows one webhook subscription per API app, so it can point at only one project.
Point it at production once the integration is live there; until then, point it at whichever project is being tested.
The other projects still notice a revoke on their next upload attempt, through the 401.

```bash
# Create. Strava calls stravaWebhook with hub.challenge before answering.
curl -X POST https://www.strava.com/api/v3/push_subscriptions \
  -F client_id=<clientId> -F client_secret=<clientSecret> \
  -F callback_url=https://us-central1-<projectId>.cloudfunctions.net/stravaWebhook \
  -F verify_token=<webhookVerifyToken>

# View and delete.
curl -G https://www.strava.com/api/v3/push_subscriptions -d client_id=<clientId> -d client_secret=<clientSecret>
curl -X DELETE "https://www.strava.com/api/v3/push_subscriptions/<id>?client_id=<clientId>&client_secret=<clientSecret>"
```

## Rate limits

The self-upgraded tier allows 400 requests per 15 minutes and 4,000 per day overall, of which 200 and 2,000 may be non-upload requests.
One climb costs one upload plus one to three status reads, and a token refresh at most every six hours per climber.
The worker claims at most 20 climbs per run, stops the rest of the batch after a 429, and resumes at the next quarter hour.

## Scheduled changes at Strava

- The REST base moves from `https://www.strava.com/api/v3` to `https://www.api-v3.strava.com`, available from 2027-01-04; the old host stops answering on 2027-06-01.
  `STRAVA_API_BASE` in `functions/src/strava/api.ts` has to move before then.
- `oauth/deauthorize` is retired on 2027-06-01; Ascend already uses `oauth/revoke`.
- Tokens must travel in headers from 2027-06-01; Ascend already sends them that way.

## What Strava's terms require of Ascend

- Consent before connecting that says what is sent, how, and how to stop and delete it - the Strava card's description, the manage sheet, and the privacy policy.
- A clear route to the athlete's Strava account - "View on Strava" in the manage sheet.
- Deletion of Strava data within 30 days of a revoke or account deletion - disconnect, the webhook and the account sweep all delete at once.
- The official "Connect with Strava" button, unmodified, linking to Strava's authorize endpoint; Strava's marks never used as Ascend's icon.
- No Strava data in analytics, advertising, AI tooling or any other user's view.
- A privacy policy statement that Strava may collect usage data about Ascend's API use.
- No press announcement mentioning Strava without Strava's written consent.

## Scaling past 10 climbers

Submit the Developer Program form linked from <https://developers.strava.com/docs/rate-limits/> once the integration runs for real climbers, with screenshots of the Strava card, the manage sheet, and the Connect button.
When Strava approves a capacity, pass it to the script as `--capacity`.
