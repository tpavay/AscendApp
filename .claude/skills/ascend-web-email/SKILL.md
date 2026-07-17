---
name: ascend-web-email
description: Use when working on the Ascend website or Cloud Functions - Firebase Hosting, the waitlist signup endpoint, Beehiiv subscription, transactional email via Resend, the feedback notification trigger, email job workers, or email copy and templates. Covers where secrets live and which emails go through Functions vs Beehiiv.
paths:
  - functions/**
  - web/**
  - firebase.json
---

# Web + Email

Website source lives in `web/` (Astro) and is built to `web/dist/` before deploy. Load `firebase-hosting-basics` for hosting/rewrite/deploy work.

## Waitlist
- Waitlist form submissions must use `POST /api/join-waitlist` (Hosting rewrite to the `joinWaitlist` Cloud Function), not direct Firestore client writes.
- Waitlist submissions are subscribed server-side to Beehiiv. The Beehiiv API key and publication ID live in the `BEEHIIV_CONFIG` Secret Manager JSON secret; never expose them in website or iOS client code.
- `joinWaitlist` rate limits public submissions using hashed requester IPs stored in `email_rate_limits`, calls Beehiiv, and mirrors normalized email hash + Beehiiv subscription metadata in the `waitlist` collection for dedupe/debugging.

## Transactional email
- Transactional emails for feedback and future non-Beehiiv product triggers must be sent server-side from Cloud Functions, never directly from the website or iOS client.
- Cloud Functions email provider config lives in the `TRANSACTIONAL_EMAIL_CONFIG` Secret Manager JSON secret, with `functions/.secret.local` used only for local emulator overrides.
- Legacy queued transactional emails are delivered in the background by the scheduled `processEmailJobs` worker. Do not reintroduce waitlist welcome emails through `email_jobs` unless product explicitly moves off Beehiiv.
- In-app feedback submissions (`feedback` collection) trigger `onFeedbackCreated`, which sends an admin notification email directly via Resend (not queued). The recipient is `feedbackNotificationEmail` from the secret config (falls back to `replyTo` -> `fromEmail`). Reply-to is set to the submitting user's email. Notification delivery metadata is written back onto the feedback document.

## Email copy
Email copy, templates, lifecycle automations, Beehiiv campaigns, and subject lines must follow the Ascend Email Playbook. Codex has this as the `ascend-email-playbook` skill at `~/.codex/skills/ascend-email-playbook`; other agents should apply the same rule set: app-triggered emails go through Cloud Functions/Resend with deterministic dedupe, broadcasts go through Beehiiv, copy is competitive/stair-stepper-specific, and each email has one primary CTA.

## Build & test
```bash
cd functions && npm run lint && npm test   # Cloud Functions
cd web && npm run build                    # website -> web/dist/
```

## Related
- Load `vibe-security` for the waitlist/signup endpoint, secrets, and any auth/trust-boundary change.
- Environment-agnostic URLs: never hardcode Firebase project IDs (see the core project guide).
