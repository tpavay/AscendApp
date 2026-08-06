# RevenueCat Server Entitlement Enforcement

Today the paid gate is a screen the app chooses to show, and without this system the backend has no idea whether anyone paid.
Issue #387 closes that failure by projecting RevenueCat truth into Firebase and requiring an active server-owned grant at the backend data boundaries.

The existing device-side `app_access` check, hard paywall, startup refresh, foreground refresh, identity refresh, and restore paths remain in place for responsive UX.
They no longer carry the server trust boundary by themselves.

## Captain actions required before deployment

These actions change vendor or cloud configuration and cannot be completed by repository code.
Do not deploy the paid Firestore or Storage rules until every staging prerequisite below is complete.

### RevenueCat dashboard

1. In RevenueCat project `project-NnEDGL1m`, create separate least-privilege secret API keys for the Ascend Staging and Ascend server integrations.
Each key must be able to read current subscriber state through `GET /v1/subscribers/{app_user_id}`.
Restrict each key to its app if the current RevenueCat key form offers that restriction.
2. Copy the internal RevenueCat app ID for `Ascend Staging` and for `Ascend`.
These are the `event.app_id` values, not bundle IDs and not project ID `project-NnEDGL1m`.
3. Create one webhook integration filtered to `Ascend Staging` and one filtered to `Ascend`.
Use both sandbox and production events for each app.
Select Dashboard Test, Subscription Lifecycle Purchases, Transfer, Temporary Entitlement Grant, and Subscriber Alias events.
Do not enable Paywall UI or virtual-currency events because they create subscriber API traffic without changing paid access.
4. Set the staging destination to `https://us-central1-ascend-staging-fa7d5.cloudfunctions.net/revenueCatWebhook`.
Set the production destination to `https://us-central1-ascend-prod-9c8f2.cloudfunctions.net/revenueCatWebhook`.
5. Configure a different high-entropy `Authorization` header value for each destination.
HMAC signing is offered only on a saved integration's detail page, never on the New Webhook form, so the ordering is fixed: create the integration with its URL, `Authorization` value, environment, and app filter, save it, then reopen its detail page.
On that detail page, toggle **HMAC webhook signing** and copy the signing secret immediately, because RevenueCat shows it only at creation or rotation and cannot retrieve it later.
Only then assemble that destination's complete `REVENUECAT_SERVER_CONFIG` JSON, write the whole secret to Firebase, and deploy Functions.
All six configuration fields below are required and the parser refuses a partial value, so there is never a valid intermediate write that carries the new signing secret alone.
If the one-time value is lost, use **Rotate secret** on that detail page to mint a new one.
Rotation invalidates the old secret immediately, and RevenueCat, not the captain, decides when the next delivery arrives.
Every genuine lifecycle event between the rotation click and the deployed replacement is therefore rejected with HTTP 401.
That window is unavoidable; only its length is controllable.
Rotate only when the current value is genuinely lost, and follow the same ordering without pausing: click **Rotate secret**, copy the new secret, write the complete Firebase secret with it, deploy Functions, then send the dashboard test webhook and require HTTP 200 before considering the rotation done.
[RevenueCat's current webhook documentation](https://www.revenuecat.com/docs/integrations/webhooks#webhook-signature-verification-hmac) specifies enabling the toggle on an existing webhook integration, the secret shown only once at creation or rotation, the immediate invalidation of the old secret on rotation, and the `X-RevenueCat-Webhook-Signature: t=<unix_timestamp>,v1=<hmac_sha256_hex>` delivery header.
That the toggle is absent from the New Webhook form is an observation of the current dashboard rather than a documented claim.
The same page states that the server should return a 200 status code, that any other status code is considered a failure by RevenueCat's backend, that RevenueCat then retries up to five times with increasing delays of 5, 10, 20, 40, and 80 minutes, and that it stops sending after five retries.
It does not state whether those delays are intervals between attempts or offsets from the first attempt, so the total retry span, and with it any guaranteed self-healing window for the rotation gap, is unverified and must not be planned against.
Deliveries rejected during the gap enter that documented retry process, so restore HTTP 200 promptly, then inspect the integration's failed and retrying events and resend whatever still needs it with the **Retry** action the same page documents.
The function requires both credentials on every request.
6. After the matching Firebase function is deployed, send RevenueCat's test webhook to each destination and require HTTP 200.
A test event with no real Firebase UID is expected to complete with zero affected users.
7. For every Firebase UID that already has paid access before rules are enabled, cause a fresh RevenueCat lifecycle delivery after the webhook exists and verify that `users/{uid}/entitlements/app_access` exists.
Staging sandbox purchases and the App Review promotional entitlement must be reconciled before their accounts can pass backend rules.
8. If the App Review account uses a RevenueCat promotional entitlement, inspect its subscriber response and add its exact `product_identifier` to production `allowedProductIds`.
Do not allow every promotional identifier as a class.

RevenueCat supports multiple webhook integrations in one project, which is required because production and staging share a project but write to different Firebase projects.
The code rejects an unexpected non-null `app_id` and ignores products outside the configured environment, so a dashboard filter mistake does not silently cross the environments.
RevenueCat omits `app_id` for promotional and other app-less events, so an authenticated missing value is accepted and remains constrained by the destination's product allowlist.

### Firebase and Google Cloud configuration

Create `REVENUECAT_SERVER_CONFIG` as a Firebase Functions secret separately in staging and production.
Enter it at the secret prompt so no value reaches shell history, logs, Git, or chat.

The JSON shape is:

```json
{
  "apiKey": "<environment secret API key>",
  "webhookAuthorization": "<exact Authorization header value>",
  "webhookSigningSecret": "<environment HMAC signing secret>",
  "appId": "<RevenueCat event.app_id for this app>",
  "entitlementId": "app_access",
  "allowedProductIds": ["<annual product>", "<monthly product>"]
}
```

Staging must allow `ascend_staging_yearly` and `ascend_staging_monthly`.
Production must allow `ascend_yearly` and `ascend_monthly`.
Add a promotional product identifier only when the App Review subscriber response proves its exact value.

Create `MIXPANEL_SERVER_CONFIG` as a Firebase Functions secret separately in staging and production.
Enter it at the secret prompt so no value reaches shell history, logs, Git, chat, or the iOS bundle.

The JSON shape is:

```json
{
  "serviceAccountUsername": "<environment Mixpanel service-account username>",
  "serviceAccountPassword": "<environment Mixpanel service-account password>"
}
```

Create a separate project-scoped Mixpanel service account for Staging project `4051102` and Production project `4051100`.
Grant only the Mixpanel project role required by `/import`; Mixpanel currently requires an Admin service account for that endpoint, so keep each account scoped to its one project and out of organization-wide membership.
The server derives the destination from its deployed Firebase project and refuses every project outside this fixed map: Development `ascend-f2e4f` -> `4032860`, Staging `ascend-staging-fa7d5` -> `4051102`, Production `ascend-prod-9c8f2` -> `4051100`.
Server-side subscription lifecycle analytics exists in staging and production only, which is why no dev credential is listed above.
No repository workflow deploys Cloud Functions to `ascend-f2e4f`, and dev has no RevenueCat webhook endpoint, so dev deliberately has no server analytics credential and its closed-app lifecycle stream stays empty.
Client analytics is untouched by this: the dev app still reports client events to `4032860` from the device.
If a dev Functions deployment is ever added, provision a dev-project-scoped Mixpanel service account and its own `MIXPANEL_SERVER_CONFIG` before that deployment, because a bound secret that does not exist fails the whole Functions deploy exactly as it would in staging.

Set both `REVENUECAT_SERVER_CONFIG` and `MIXPANEL_SERVER_CONFIG` before deploying Functions.
The webhook binds only the RevenueCat secret, while the independent outbox worker binds only the Mixpanel secret, so a Mixpanel outage or credential failure can never decide RevenueCat's webhook response.

Before the first Storage rules deployment in each Firebase project, enable cross-service Cloud Storage Security Rules access to Cloud Firestore.
Firebase prompts for this permission when the rules are saved from the Firebase CLI or Firebase console.
Verify in Google Cloud IAM, with Google-provided grants visible, that the Firebase Storage service account ending in `@gcp-sa-firebasestorage.iam.gserviceaccount.com` holds the `Firebase Rules Firestore Service Agent` role.
The non-interactive CI deployment cannot answer this first-use prompt.

The deployment workflows publish and wait for indexes, then deploy Functions, then Firestore rules, then Storage rules.
A missing Firebase secret therefore stops the deployment before paid rules can lock everyone out.
Production remains behind its existing approval gate.

### App Store Connect

In production app `6757202987`, open App Information, then App Store Server Notifications.
Copy the existing RevenueCat Version 2 production URL into the Sandbox Server URL field and keep Version 2 selected.

In staging app `6759919365`, open the same section.
Copy the Ascend Staging RevenueCat Apple notification URL into both Production Server URL and Sandbox Server URL and select Version 2 for both.
RevenueCat's `Apply in App Store Connect` action may set both fields, but verify both fields after it completes.

These Apple URLs deliver renewals, expirations, billing-retry changes, and refunds to RevenueCat while Ascend is closed.
The RevenueCat webhook then delivers the resulting subscriber change to Firebase.

Leave RevenueCat's optional setting to track new purchases directly from App Store Server Notifications off unless the identity contract changes.
RevenueCat only supplies `appAccountToken` automatically when its custom app user ID is a UUID, while Ascend identifies RevenueCat customers with a Firebase UID that is not guaranteed to be a UUID.
Enabling that option can associate an early notification with a RevenueCat anonymous identity before the SDK posts the receipt under the Firebase UID.

### Superwall

No Superwall dashboard change is required.
Superwall remains the paywall presentation and conversion layer, while RevenueCat remains subscription truth.

## Server flow

1. After HMAC is enabled on the saved integration, RevenueCat sends a POST request with the configured `Authorization` header and an `X-RevenueCat-Webhook-Signature` HMAC header.
2. `revenueCatWebhook` verifies method, raw-body size, content type, Authorization, signature, five-minute timestamp tolerance, JSON shape, event ID, event timestamp, and expected RevenueCat app ID.
3. `_revenuecat_webhook_events/{event.id}` is transactionally claimed with a two-minute processing lease.
First delivery wins: the ledger keeps the digest and event metadata of the delivery that created it, and a redelivery whose bytes differ never overwrites either.
A conflicting redelivery of a completed event returns duplicate, while a conflicting retry of a failed or lease-expired event is allowed to re-fetch current subscriber truth and complete against the canonical claim.
Only `conflictingPayloadCount` records that it happened.
This is deliberate: the request is already Authorization- and HMAC-authenticated, and access is derived from a fresh subscriber fetch rather than from the payload, so refusing the retry forever would strand a real subscriber for a byte difference that changes nothing.
4. The function extracts bounded Firebase UID candidates from `app_user_id`, `original_app_user_id`, both sides of a transfer, and then aliases.
RevenueCat anonymous IDs are ignored and every candidate must exist in Firebase Authentication before any subscriber lookup.
A subscriber who accumulated more than twenty distinct identities is truncated in that order rather than rejected, because a rejected delivery is not retried and would discard the real identities with the surplus aliases.
Only the overflow count is logged.
5. The function re-fetches current RevenueCat subscriber state for each verified Firebase UID.
It does not award access from webhook event fields.
6. One transaction writes `users/{uid}/entitlement_status/app_access` for audit and ordering.
It creates `users/{uid}/entitlements/app_access` only while the configured `app_access` entitlement is active for an allowed environment product.
It deletes that active grant when current RevenueCat state is inactive.
7. A projection only replaces one derived from an older RevenueCat `request_date_ms`.
The triggering event's order therefore cannot move subscriber state backward.
8. For each verified Firebase uid and reportable subscription transition, the event-completion transaction creates one `_revenuecat_analytics_outbox` row whose stable idempotency key is derived from the RevenueCat event ID and uid.
Exactly-once therefore means one analytics event per RevenueCat event ID plus uid; two distinct event IDs are two real transitions and each exports once.
One Apple refund is two such transitions: the `CANCELLATION` exports `subscription_cancelled`, which may still hold access to the end of the paid period, and the later `EXPIRATION` that fresh RevenueCat truth shows removed access exports `subscription_refunded`.
Both carry `refund_attributed`, so a refund is queryable end to end without either transition being suppressed or relabelled as the other.
The row contains only the normalized lifecycle event, server environment envelope, product and entitlement classification, event time, and delivery state.
It never contains the raw webhook, receipt, transaction ID, API credential, authorization value, HMAC secret, or vendor response.
9. The event is marked complete in that same transaction as the projection changes and outbox writes.
A duplicate completed event returns HTTP 200 without a second RevenueCat lookup.
10. `processRevenueCatAnalyticsOutbox` independently retries due rows into the Mixpanel project mapped from the deployed Firebase project.
It uses Mixpanel `/import` with `strict=1` and a stable `$insert_id`, so a provider retry or a crash after Mixpanel accepts the event cannot surface a second event.
Only a confirmed import marks the row delivered; transient network, rate-limit, authentication, and provider failures return it to the queue with bounded exponential backoff.
11. `expireRevenueCatEntitlements` removes a still-present active grant within five minutes after its last verified expiration or grace-period timestamp.
This fails closed if an expiration webhook is delayed and a concurrent renewal wins through Firestore transaction retry.
The sweep pages past documents from any other `entitlements` subcollection until it has spent its budget on real `users/{uid}/entitlements/app_access` grants, because the query is ordered by `accessUntil` and a single foreign document with an ancient timestamp would otherwise sit at the head of a fixed window and starve every real expiry behind it.

Webhook failures return a non-2xx response so RevenueCat retries them, on the five-retry ladder the dashboard setup step above records.
The processor is safe after a crash because a failed attempt is reclaimable and an abandoned processing lease expires within two minutes, inside the documented five-minute delay before RevenueCat's first retry.
Mixpanel delivery failures do not fail or delay the webhook response because delivery starts only from the separately scheduled outbox worker.
An unresolvable analytics destination is degraded rather than fatal: the webhook logs it, skips outbox enqueueing, and still authenticates, deduplicates, and projects the entitlement, because analytics may never decide paid access.
Each worker run stops claiming deliveries before its function timeout and immediately returns every unattempted claim to the queue, so provider latency drains instead of stranding rows until the fifteen-minute stale sweep.
A claim released that way was never sent, so it keeps the delivery attempt count and last delivery error it already had; only a real send moves either, and the backoff ladder is unaffected by how busy a run was.
A permanently discarded row is logged at error level with its outbox id, event name, and error code, so a dead lifecycle stream is visible rather than silent.
A row that keeps failing retryably past its tenth attempt - a rotated Mixpanel credential answers 401, which is retryable - is logged at error level on every further attempt, so retrying forever is never the same as failing quietly.

No raw webhook body, transaction identifier, API key, Authorization value, HMAC secret, or subscriber response is stored or logged.
The event ledger stores only event metadata, a payload digest, processing state, and counts, with no Firebase UID.
The analytics outbox stores the affected Firebase UID only as the Mixpanel `distinct_id`; account deletion removes every outbox row that still carries it.

Each ledger entry carries `retainUntil`, an explicit thirty-day future timestamp, and a Firestore TTL field override deletes the entry when it passes.
The dedupe evidence only has to outlive RevenueCat's five documented retries, whose longest documented delay is 80 minutes and whose total span is unverified, so thirty days is generous while still bounding the collection.
`receivedAt` cannot carry the policy: it is already in the past when it is written, so every entry would be eligible for deletion the moment it was created.
Each analytics outbox row carries the same thirty-day `retainUntil` stamp and its own Firestore TTL field override, because a row holds a Firebase UID as its Mixpanel `distinct_id` and may not outlive the delivery it exists to prove.
Every state change restamps it, so the thirty days run from the row's last movement rather than from its creation: a row still retrying cannot be deleted out from under the retry-until-delivery guarantee, and a delivered or terminally failed row gets exactly one bounded window after it settled.

## Recovering access the webhook never delivered

The webhook is at-least-once, not exactly-once.
A delivery that never arrived or exhausted RevenueCat's five retries would otherwise leave a paying subscriber locked out of every paid boundary with no in-app remedy, and a brand-new purchase races its very first delivery.

`reconcileAppAccess` is an authenticated callable that re-derives one user's projection from the same RevenueCat subscriber API the webhook uses.
It acts only on `request.auth.uid`, never reads `request.data`, and accepts no entitlement state, product, expiry, or identity from the caller, so it does not move the trust boundary.
A server-owned per-user cooldown in `users/{uid}/entitlement_reconciliations/current` keeps a modified client from turning recovery into an unbounded subscriber-API amplifier; a throttled call returns `{"status": "throttled"}` without work and without an error.
An attempt that never reached RevenueCat shortens its own reservation to a fifteen-second retry window rather than clearing it: a cooldown that outlived an outage would refuse the recovery a subscriber asks for by tapping Restore, but no cooldown at all would let every foreground during that outage issue another subscriber fetch, which is the amplification the cooldown exists to stop.
The shortening only applies to the reservation that attempt made, so a newer claim that already replaced it is untouched.
Ordering is the shared `request_date_ms` rule, so a slow reconciliation cannot move access backward.
Because a recovery check is polled rather than event-driven, it also skips the write entirely when `isActive`, `productId`, and `accessUntil` already match and the active grant document's presence agrees with them; a missing grant under a current status still rewrites, since that is exactly the state this path exists to repair.

The client treats `throttled` as a refusal rather than an answer, so a refused call never satisfies its own five-minute spacing.
Every outcome still sets its own next-attempt time - five minutes after an answer, sixty seconds after a refusal, thirty seconds after a failure - because launch, foreground, identity change, the entitlement flip, purchase, and restore all trigger this, and an outcome that recorded nothing would let a backgrounding user issue one call per trigger.
An explicit restore bypasses that client spacing entirely and lets the server's own policy decide.

The app invokes it wherever an active device entitlement can outlive or race webhook delivery: after every entitlement refresh (launch, foreground, identity change), when access flips active mid-session from RevenueCat's customer-info stream, on the entitlement refresh a completed purchase forces before its verdict, and unconditionally after every restore.
All three restore surfaces - account settings, the Superwall paywall's Restore button, and the app-access gate placeholder - run the single `AppAccessRestoreService`, which restores through `MonetizationManager`, so none can drift back to calling RevenueCat directly and skipping reconciliation.
`restorePurchases()` returns the state RevenueCat resolved for that restore, and the Superwall status, the forced reconciliation, and the restore's analytics terminal all read that return value rather than the stored `entitlementState`, which a pending identity transition can still be holding at `.unknown`.
The device entitlement check, the hard paywall, and the restore surfaces are otherwise unchanged.

## Backend choke points

The paid check belongs where a modified client reaches durable paid data, paid shared content, or paid media.

Firestore requires an active grant for:

- Private workouts, user routines, and routine folders on read, create, and update.
- Live Climb publish status and completed-landmark projections.
- Profile statistics, public workout summaries, and achievements.
- Global leaderboards, published routine templates, Live Replay indexes, and global Live Climb community statistics.
- The remote share-card template manifest.

Storage requires an active grant for:

- Workout photos, videos, and heart-rate sidecars on read, list, create, and update.
- Share-card template assets and Live Replay avatars.

`climb-images/` deliberately stays readable to any signed-in caller.
The `firstClimb` onboarding stage is the last stage before the paywall and shows the recommended landmark's artwork, so gating that prefix would break the conversion path itself.
Like the Hosting climb catalog, it is immutable product content with no user data, mutable state, or compute authority.

Owner deletes stay available after lapse so paid enforcement never traps user data.
Account documents, authentication routing, public identity publication, profile-picture management, lifecycle state, communication preferences, notification devices, blocks, reports, feedback, and rate-limit records stay ungated because onboarding, restore, account management, support, and safety must work before purchase and after lapse.
Public profile identity is moderated public identity rather than paid fitness data.

The existing callable Functions are not paid compute choke points.
Lifecycle and push calls support onboarding and account operation, while paid leaderboard and replay computation is triggered only after a rules-authorized paid data write.
`reconcileAppAccess` is deliberately available to any signed-in caller, because refusing it to an unpaid caller would refuse it to exactly the subscriber whose grant is missing.
Static Hosting climb catalog files remain public immutable product content and contain no user data, mutable state, or compute authority.

Firestore's most expensive valid workout already reaches the 1,000-expression evaluation ceiling.
The paid owner predicate therefore uses the same two-part shape as the former owner predicate, replacing the signed-in check with one server-owned grant existence check.
The full Firebase rules emulator suite proves a maximal valid workout still succeeds.
Each paid Firestore request costs one rules document access, and each paid Storage request costs one billable cross-service Firestore document access.

## Privacy alignment

No new SDK, device data source, or App Privacy category is introduced.
`PrivacyInfo.xcprivacy` already declares linked Purchase History and linked User ID for app functionality, and the published privacy policy already describes subscription status, entitlements, and purchase history processed through Apple and RevenueCat.
The server stores a minimal entitlement projection and bounded analytics outbox, with no raw purchase receipt or transaction identifier, so no privacy manifest or policy change is required for this implementation.

## UNKNOWN

- The internal RevenueCat `event.app_id` values for Ascend and Ascend Staging remain unknown because `secret list` has no `revenuecat` credential as of 2026-08-05.
- RevenueCat restore and transfer behavior remains unverified and is project-scoped across both apps.
The processor handles transfer events by re-fetching both sides, but the captain must still confirm the intended restore policy in RevenueCat.
- The App Review promotional entitlement's exact `product_identifier` remains unknown.
It must be explicitly allowlisted if it is not one of the production subscription product IDs.
- Live webhook destinations and HMAC settings remain unknown until the captain configures and tests them in RevenueCat.
- RevenueCat documents five retries with increasing delays of 5, 10, 20, 40, and 80 minutes but never says whether those are intervals between attempts or offsets from the first attempt.
The total retry span is therefore unverified, and no HMAC rotation gap of any particular length can be promised to self-heal.

## IRREDUCIBLE

- A cancellation normally leaves access active through the paid period.
The backend should remove access at RevenueCat's effective expiration, not at the moment the user turns off renewal.
- Apple, RevenueCat, Cloud Functions, and Firestore are distributed systems, so a state change is not instantaneous.
The normal path is near-real-time webhook delivery, and the known-expiry sweep bounds stale access after an already-verified expiration to five minutes plus scheduler delay.
- RevenueCat's subscriber API is the authorization source.
If it is unavailable, the webhook returns a retry response and preserves the last verified grant instead of guessing from an event payload.
- Vendor secrets, webhook destinations, App Store Server Notification URLs, and the first cross-service IAM grant cannot be expressed safely as repository defaults.

## RISKS

- Enabling paid rules before secrets, webhooks, IAM, and existing-subscriber reconciliation creates a backend-wide lockout for legitimate subscribers.
- A new purchase can pass the device check before its server webhook finishes, causing a brief paid-data denial until the verified projection lands.
`reconcileAppAccess` closes that window on the app's next refresh, but the two systems are still distributed and the first seconds after a purchase can deny paid data.
- A refund or revocation before the stored expiration depends on Apple and RevenueCat webhook delivery.
RevenueCat retries non-2xx deliveries, but a vendor outage can extend the last verified grant until the known expiration sweep removes it.
- A wrong RevenueCat app filter can send an event to the wrong Firebase project.
The expected app ID and environment product allowlist limit that failure, but the integration still needs correct dashboard ownership.
- Shared RevenueCat project settings can affect both production and staging.
Use separate webhook integrations, separate credentials, separate Firebase secrets, and explicit app filters.
- Storage authorization now performs a billable Firestore read and depends on the cross-service IAM role.
Removing that role fails Storage requests closed.
- Promotional access is denied unless its exact product identifier is allowlisted.
This is intentional, but it can block the App Review account if the dashboard step is missed.
