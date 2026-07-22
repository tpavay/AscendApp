# Public Identity Sanitization Runbook

Captain-only runbook for `scripts/sanitize-public-identities.mjs`, the migration behind the Guideline 1.2 launch change that removes account-authored public identity.
Agents never run this migration against production; every production command below is executed by the captain.

## What the migration does

- Rewrites every real-user public projection (public profiles, leaderboard stats, live replay entries, finishers, and First Ascents) to the system identity: `displayName: "Climber"`, empty `photoURL`, empty avatar token.
- Preserves developer-owned synthetic identities only where the trusted server-owned marker exists, and backfills `firstAscentIsSynthetic` on legacy seeded First Ascents.
- Sweeps every object under `users/{uid}/profile_pictures/` in the environment's default bucket and rotates its Firebase download token, so previously exposed URLs stop resolving even when no current public document references them.
- Updates the owner-private `users/{uid}.profilePictureURL` only when it references a rotated object, then verifies every old tokenized URL no longer resolves.
- Moves legacy root `profile_pictures/` objects under their owner's user-scoped path and deletes the root objects.

## Idempotency and reruns

- Each rotated object receives a `publicIdentitySanitizedVersion` custom-metadata marker, written only after its owner documents reference the fresh token.
- A rerun (`--apply --rerun`) skips marked objects, rotates any newly discovered unmarked object, and resumes any work a partial run left behind.
- Objects created after the operation's first successful run were never publicly exposed and are exempt from the sweep, so routine profile-photo uploads do not churn on later reruns or audits.
- Every apply is recorded in the `_migrations` Firestore ledger; a second apply without `--rerun` is refused.

## Captain-run order and commands

Run environments strictly in this order, and complete each environment's full sequence (dry-run, apply, audit) before starting the next.
The app release containing the sanitized client and the updated `firestore.rules` / `storage.rules` must be deployed to the environment before its migration runs.

1. Dev:

   ```bash
   node scripts/sanitize-public-identities.mjs --env dev --dry-run
   node scripts/sanitize-public-identities.mjs --env dev --apply
   node scripts/sanitize-public-identities.mjs --env dev --audit
   ```

2. Staging:

   ```bash
   node scripts/sanitize-public-identities.mjs --env staging --dry-run
   node scripts/sanitize-public-identities.mjs --env staging --apply
   node scripts/sanitize-public-identities.mjs --env staging --audit
   ```

3. Production (captain only, requires the explicit project-id confirmation):

   ```bash
   node scripts/sanitize-public-identities.mjs --env prod --confirm-production ascend-prod-9c8f2 --dry-run
   node scripts/sanitize-public-identities.mjs --env prod --confirm-production ascend-prod-9c8f2 --apply
   node scripts/sanitize-public-identities.mjs --env prod --confirm-production ascend-prod-9c8f2 --audit
   ```

If an apply fails partway, fix the cause and rerun the same apply command; the ledger and per-object markers make the rerun safe.
If the ledger already shows success for the environment, add `--rerun` to apply again.

## Reversibility

All private identity data is retained: `users/{uid}.displayName` and `users/{uid}.profilePictureURL` keep the owner's custom name and photo, and self-only screens continue to render them.
The public presentation is governed by the single policy seam in `PublicClimberIdentity` (`.systemGenerated` today, `.accountAuthored` reserved).
A future moderated public-profile launch flips that seam and republishes identity from the retained private data; no data destroyed by this migration is needed to reverse it.
