# Transactional Email Setup

Ascend's Cloud Functions use the `TRANSACTIONAL_EMAIL_CONFIG` JSON secret for background transactional email delivery.

## Secret shape

```json
{
  "provider": "resend",
  "apiKey": "re_xxxxxxxxx",
  "betaInviteUrl": "https://testflight.apple.com/join/ZZ1zUmBf",
  "feedbackNotificationEmail": "tyler@ascendstepper.com",
  "fromEmail": "hello@updates.ascendstepper.com",
  "fromName": "Ascend",
  "replyTo": "support@ascendstepper.com",
  "websiteUrl": "https://ascendstepper.com"
}
```

## Resend prerequisites

- Verify the sending domain in Resend before deploying.
- Use a sender address from that verified domain for `fromEmail`.
- Keep the API key only in Secret Manager or local emulator secret overrides.
- `betaInviteUrl` is optional. If set, waitlist emails show a primary TestFlight CTA.
- `feedbackNotificationEmail` is optional. Admin email for feedback notifications. Falls back to `replyTo`, then `fromEmail`.
- `websiteUrl` is optional. If omitted, waitlist emails fall back to `https://ascendstepper.com`.

## Local emulator

Firebase's Cloud Functions emulator can override secret values with `functions/.secret.local`.

```dotenv
TRANSACTIONAL_EMAIL_CONFIG={"provider":"resend","apiKey":"re_xxxxxxxxx","betaInviteUrl":"https://testflight.apple.com/join/ZZ1zUmBf","fromEmail":"hello@updates.ascendstepper.com","fromName":"Ascend","replyTo":"support@ascendstepper.com","websiteUrl":"https://ascendstepper.com"}
```

## Deploying the secret

Create a local JSON file with the secret payload above, then load it into Secret Manager:

```bash
npx firebase-tools functions:secrets:set TRANSACTIONAL_EMAIL_CONFIG --data-file /absolute/path/to/transactional-email-config.json --format=json
```

Deploy the Firestore rules, indexes, and Cloud Functions after setting or rotating the secret:

```bash
npx firebase-tools deploy --only firestore:rules,firestore:indexes,functions
```

## Current behavior

- `joinWaitlist` validates email input, rate limits by hashed requester IP, and enqueues a deterministic `waitlist_welcome` job.
- The welcome email is sent in the background by the scheduled `processEmailJobs` worker.
- `email_jobs` stores queue state, attempts, retry timing, and provider metadata.
- Retryable provider failures are requeued automatically; permanent failures are marked on the job.
- Existing waitlist rows created before this system are not backfilled automatically.

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
