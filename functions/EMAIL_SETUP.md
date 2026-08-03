# Transactional Email Setup

Ascend's Cloud Functions use the `TRANSACTIONAL_EMAIL_CONFIG` JSON secret for background transactional email delivery.

## Secret shape

```json
{
  "provider": "resend",
  "apiKey": "re_xxxxxxxxx",
  "feedbackNotificationEmail": "tyler@ascendstepper.com",
  "fromEmail": "hello@updates.ascendstepper.com",
  "fromName": "Ascend",
  "replyTo": "support@ascendstepper.com",
  "unsubscribeSigningKey": "a-long-random-secret-of-at-least-32-chars",
  "websiteUrl": "https://ascendstepper.com"
}
```

## Resend prerequisites

- Verify the sending domain in Resend before deploying.
- Use a sender address from that verified domain for `fromEmail`.
- Keep the API key only in Secret Manager or local emulator secret overrides.
- `feedbackNotificationEmail` is optional. Admin email for feedback notifications. Falls back to `replyTo`, then `fromEmail`.
- Unknown keys are ignored, so a deployed secret still carrying the retired `betaInviteUrl` is harmless and can be dropped on the next rotation.

### Required fields

`provider`, `apiKey`, `fromEmail`, and `fromName` are required, plus the two below.
`getTransactionalEmailConfig()` throws when any is missing or invalid, which fails every transactional send, so set them in each environment's secret *before* deploying functions.
See CLAUDE.md, Firebase Hosting, for why these two fail loudly rather than defaulting.

- `unsubscribeSigningKey` is **required** and must be at least 32 characters. It signs the HMAC unsubscribe tokens in outgoing email. Rotating it invalidates the unsubscribe links in already-delivered mail, so treat it as long-lived.
- `websiteUrl` is **required** and must be an https URL. It is the host the unsubscribe link points at, and the trailing slash and fragment are normalized away.

## Local emulator

Firebase's Cloud Functions emulator can override secret values with `functions/.secret.local`.

```dotenv
TRANSACTIONAL_EMAIL_CONFIG={"provider":"resend","apiKey":"re_xxxxxxxxx","fromEmail":"hello@updates.ascendstepper.com","fromName":"Ascend","replyTo":"support@ascendstepper.com","unsubscribeSigningKey":"a-long-random-secret-of-at-least-32-chars","websiteUrl":"https://ascendstepper.com"}
```

## Deploying the secret

Create a local JSON file with the secret payload above, then load it into Secret Manager.
The CLI version is pinned repo-wide; see `docs/dependency-security.md` before changing it.

```bash
npx -y firebase-tools@15.22.1 functions:secrets:set TRANSACTIONAL_EMAIL_CONFIG --data-file /absolute/path/to/transactional-email-config.json --format=json
```

Deploy the Firestore rules, indexes, and Cloud Functions after setting or rotating the secret:

```bash
npx -y firebase-tools@15.22.1 deploy --only firestore:rules,firestore:indexes,functions
```

## Current behavior

- The scheduled `processEmailJobs` worker sends queued transactional app emails. It asserts the secret config once per invocation before claiming any job, so a mis-ordered deploy fails the whole run loudly instead of per message.
- `email_jobs` stores queue state, attempts, retry timing, and provider metadata.
- Retryable provider failures are requeued automatically; permanent failures are marked on the job.

## Unsubscribe

- Every email addressed to a user carries RFC 8058 one-click `List-Unsubscribe` headers and a footer unsubscribe link, both derived from the job's `recipientUid`.
- Admin feedback notifications carry neither. They have no `recipientUid`, so there is no per-recipient preference an unsubscribe could flip.
- Links point at `/api/unsubscribe`, a Hosting rewrite to the `unsubscribeFromEmails` function, and carry an HMAC token signed with `unsubscribeSigningKey`. Tokens do not expire, so links outlive the message.
- `GET` renders a confirmation page and does not act; `POST` performs the opt-out and sets `lifecycleEmailsEnabled: false`. See CLAUDE.md, Firebase Hosting, for why that split is load-bearing.
- The write merges into `users/{uid}/communication_preferences/current`, so the push notification preference survives.
- The in-app toggle at Settings, Notifications writes the same preference.

## Lifecycle email automation

- `recordLifecycleEvent` writes validated app lifecycle events under `users/{uid}/lifecycle_events`.
- `onLifecycleEventEmailAutomation` listens for `rating_prompt_answered_v1`.
- If the user answered `yes`, it queues `rating_positive_followup`.
- If the user answered `no`, it queues `rating_negative_feedback`.
- The job ID is deterministic from `rating-prompt-answer-email:{uid}`, so the prompt can only enqueue one follow-up email per user.
- The automation skips the queue when `users/{uid}/communication_preferences/current.lifecycleEmailsEnabled` is explicitly `false`.
- The scheduled `processEmailJobs` worker re-reads that same preference right before it sends, and sends the queued email through Resend only if it still passes. Both gates are required: a retrying job can be hours old, so the user may have unsubscribed since it was queued.
- A job suppressed at send time gets the terminal `skipped` status, never `failed`. Nothing went wrong and there is nothing to retry.
- The gate applies only to jobs carrying a `recipientUid`.

## Feedback notifications

- `onFeedbackCreated` fires on `feedback/{feedbackId}` document creation.
- Sends an admin notification email directly via Resend (not queued).
- Recipient is `feedbackNotificationEmail` from the secret (falls back to `replyTo`, then `fromEmail`).
- `replyTo` on the notification email is set to the submitting user's email when present and valid, so replying goes directly to the user.
- Notification delivery metadata is written back onto the feedback document:
  - `adminNotificationStatus`: `"sent"` or `"failed"`
  - `adminNotificationSentAt`: timestamp (on success)
  - `adminNotificationLastAttemptAt`: timestamp
  - `adminNotificationErrorCode`: error code string or `null`
- Delivery failures are logged but do not throw — the feedback data is already persisted in Firestore.
