---
name: ascend-web-email
description: Use when working on the Ascend website or Cloud Functions - Firebase Hosting, transactional email via Resend, the feedback notification trigger, the lifecycle email automation, email job workers, the unsubscribe endpoint, or email copy and templates. Covers where secrets live and what the email queue is allowed to grow into.
paths:
  - functions/**
  - web/**
  - firebase.json
---

# Web + Email

Website source lives in `web/` (Astro) and is built to `web/dist/` before deploy. Load `firebase-hosting-basics` for hosting/rewrite/deploy work.

## No public unauthenticated endpoints
The waitlist signup endpoint, its Beehiiv integration, and the public IP rate limiter were removed in #330: a live `POST /api/join-waitlist` with no form anywhere behind it was attack surface for no benefit.
Cloud Functions now expose exactly one unauthenticated HTTP route, `/api/unsubscribe`, and it acts only on `POST` with a valid HMAC token.
Adding another public endpoint means re-introducing abuse controls that no longer exist in this repo - decide that deliberately rather than by reflex.

## Transactional email
- Transactional emails for feedback and product triggers must be sent server-side from Cloud Functions, never directly from the website or iOS client.
- Cloud Functions email provider config lives in the `TRANSACTIONAL_EMAIL_CONFIG` Secret Manager JSON secret, with `functions/.secret.local` used only for local emulator overrides.
- `TRANSACTIONAL_EMAIL_CONFIG.unsubscribeSigningKey` is **required** (min 32 chars) and signs unsubscribe tokens. A missing or short key makes `getTransactionalEmailConfig()` throw, which fails every transactional send, so add the key to each environment's secret *before* deploying functions. It fails loudly by design: mail must never go out without a working opt-out path. Rotating the key invalidates unsubscribe links in already-delivered mail, so treat it as long-lived.
- `TRANSACTIONAL_EMAIL_CONFIG.websiteUrl` is **required** and must be an https URL, and carries the same before-deploy secret-ordering requirement as `unsubscribeSigningKey`: set it in each environment's secret *before* deploying functions or every transactional send fails. It is required rather than defaulted because it is the host the unsubscribe link points at, and the token in that link is signed with the *current* environment's key. A silent fallback to the production host would make staging emails carry links that verify against the production key and never work.
- Queued transactional emails are delivered in the background by the scheduled `processEmailJobs` worker. `onLifecycleEventEmailAutomation` is its only producer, and it always stamps a `recipientUid`.
- A queued job outlives the build that wrote it, so `renderEmailContentForJob` names an unmapped type (`unsupported_email_type:<type>`) rather than faulting on an undefined catalog entry. Keep that guard when retiring an `EmailType`; `functions/test/emulator/emailQueue.test.ts` is the regression, and it also asserts a leftover job of a retired type does not stop the live job beside it in the same batch.
- In-app feedback submissions (`feedback` collection) trigger `onFeedbackCreated`, which sends an admin notification email directly via Resend (not queued). The recipient is `feedbackNotificationEmail` from the secret config (falls back to `replyTo` -> `fromEmail`). Reply-to is set to the submitting user's email. Notification delivery metadata is written back onto the feedback document.

## Unsubscribe & communication preferences
- Every user-addressed email carries RFC 8058 one-click `List-Unsubscribe` headers plus a footer unsubscribe link, both derived from the job's `recipientUid`. Admin feedback notifications have no `recipientUid` and intentionally get neither.
- The unsubscribe endpoint (`/api/unsubscribe` hosting rewrite to `unsubscribeFromEmails`) answers GET with a confirmation page and only acts on POST. Keep that split: link scanners and mail-client prefetchers follow GETs, and a GET that unsubscribes would opt users out without their knowledge.
- `users/{uid}/communication_preferences/current` has three writers: `recordLifecycleEvent` (email prefs), `updatePushNotificationPreferences` (push prefs), and `unsubscribeFromEmails` (the email unsubscribe endpoint). Any write to it must merge, or one feature silently clears the other's preference. `recordLifecycleEvent` and `unsubscribeFromEmails` merge by passing `{merge: true}` and building the document through the shared `buildNextCommunicationPreferences` helper; `updatePushNotificationPreferences` does not pass `{merge: true}` and is safe only because it does a transactional read-modify-write that spreads `...existing`. Route new writers through `buildNextCommunicationPreferences` rather than hand-rolling the document shape.
- **An absent preference is not consent.** `isLifecycleEmailAllowed` requires `lifecycleEmailsEnabled === true`; it used to return true unless the flag was explicitly `false`, which meant Ascend was sending on a permission nobody had given and could not evidence if beehiiv asked for it. The document is shared, so it exists for climbers who only ever changed a push preference - checking that it exists proves nothing. Never soften this back to `!== false`, and never add a second gate that treats undefined as allowed. The decision carries `lifecycleEmailsDecidedAt` (server time, stamped by `buildNextCommunicationPreferences` whenever the flag is written) and `lifecycleEmailsSource` (`onboarding` / `settings` from the app via the allowlist in `isAppLifecycleEmailConsentSource`, `email_link` from the unsubscribe endpoint). That trio is the consent record; a write that changes the flag without it is not.
- The lifecycle email preference is gated twice: once when the job is queued and again in `processEmailJobs` right before it sends. Both gates are required - a retrying job backs off up to ~14 hours, so a queue-time-only check would still deliver mail to someone who unsubscribed in that window. A job suppressed at send time gets the terminal `skipped` status, never `failed` - nothing went wrong and there is nothing to retry. The gate applies only to jobs carrying a `recipientUid`; admin feedback mail has no uid and always sends.

## Email copy
Email copy, templates, lifecycle automations, and subject lines must follow the Ascend Email Playbook. Codex has this as the `ascend-email-playbook` skill at `~/.codex/skills/ascend-email-playbook`; other agents should apply the same rule set: app-triggered emails go through Cloud Functions/Resend with deterministic dedupe, copy is competitive/stair-stepper-specific, and each email has one primary CTA.

## Cloud Functions emulator gotchas
- The Functions emulator proxies the `firebase-admin` namespace and strips its statics: inside it, `admin.firestore` is a function but `admin.firestore.Timestamp` and `.FieldValue` are `undefined`, so code using them throws only under the emulator and works in production. Import from the modular entry point instead (`import {Timestamp} from "firebase-admin/firestore"`) for anything that needs to run under `firebase emulators:start`.
- The Firestore emulator's REST API also enforces `firestore.rules`; seed fixtures with an `Authorization: Bearer owner` header to get the admin bypass.

## Build & test
```bash
cd functions && npm run lint && npm test   # Cloud Functions
cd web && npm run build                    # website -> web/dist/
```

## Related
- Load `vibe-security` for secrets and any auth/trust-boundary change, including any proposal to add a public endpoint.
- Environment-agnostic URLs: never hardcode Firebase project IDs (see the core project guide).
