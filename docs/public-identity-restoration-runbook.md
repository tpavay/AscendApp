# Public Identity Restoration Runbook

This is the captain-only runbook for `scripts/restore-public-identities.mjs`.
The migration restores validated account-authored display names and profile photos to public profiles, leaderboard rows, Live Replay entries, replay finishers, and First Ascent records.

## Safety properties

The command requires an explicit named environment and exactly one of `--dry-run`, `--apply`, or `--audit`.
Production also requires `--confirm-production ascend-prod-9c8f2`.
Apply is protected by the `_migrations` ledger operation `migration/public-identity-restoration` version 6.
Each user receives a completion marker only after every projection write for that user succeeds.
Every transactional page rereads the private user root and every target, then compares their Firestore update-time versions before writing.
A concurrent root or target edit invalidates the plan, causes a fresh full replan, and is retried at most three times.
The completion marker records the exact source version that produced the restored identity.
Reruns are idempotent and plan zero projection writes after all identity fields converge.
Trusted synthetic fixtures are never overwritten.
Global leaderboard rows receive the same explicit `published`, `pending_public_profile`, or `deleted` identity lifecycle as replay projections.
Public mirror writes fan out through four independent server-only checkpoint jobs, each processing a bounded page for one projection kind.
This keeps replay volume from starving global rows, finishers, or First Ascents.
Each distinct source-trigger delivery resets every cursor, including a delete-create-delete sequence whose first and last snapshots are both missing, while a repeated delivery remains an idempotent no-op.
The scheduler transaction also verifies that `users/{uid}` exists and deletes checkpoints instead of recreating them after account deletion.
Published global rows retain `identityPolicyVersion` and `identityChangedAt`, while pending and deleted rows clear the timestamp as part of server masking.
Only an explicitly pending anonymous projection may be republished.
Deleted projections remain protected, and legacy anonymous global rows are migrated once to the parseable permanent-deletion lifecycle with an empty photo and never reopened.
The migration changes only identity fields and never changes ranks, metrics, demographics, completion dates, or First Ascent ownership.
Missing `public_profile/current` documents are never fabricated.
They are reported as explicit skips, and audit remains failed until the source profile is repaired through the normal publication path.
Independent bounded sweeps cover global leaderboard rows, Live Replay entries, replay finishers, and First Ascent holders that the root-first pass cannot enumerate.
Every non-synthetic projection whose `users/{uid}` root is absent is transactionally normalized to permanent `deleted` identity, including stale real identity left by interrupted account cleanup.
Each sweep reads projection rows and user roots in the same transaction and changes only identity fields.
Final verification freshly enumerates user roots and every projection, so a user or projection created during apply cannot escape audit.

## Required deployment order

1. Deploy Firestore rules and indexes that make global leaderboard identity server-owned after creation, require identity lifecycle state, and provide the `blocked.blockedUid`, `entries.userId`, and `finishers.userId` collection-group field indexes.
2. Deploy both public profile identity propagation Cloud Functions.
3. Run this migration in dev, staging, and production in that order.
4. Run audit after each apply.
5. Release the app only after the production audit passes.

Do not run the restoration before the block and report moderation boundary is deployed.
The strict rules may be deployed before migration.
Legacy documents remain readable, but no client can overwrite existing leaderboard identity because rules reserve those fields for the server propagation path.
Leaderboard metrics refreshes preserve identity fields exactly, while new leaderboard creates must copy the current public profile identity and metadata.
The standalone leaderboard seed also reads and copies each existing public mirror exactly, including `photoURL` and `identityChangedAt`, and the seed audit compares those fields before release evidence is accepted.

## Dev

```bash
node scripts/restore-public-identities.mjs --env dev --dry-run
node scripts/restore-public-identities.mjs --env dev --apply
node scripts/restore-public-identities.mjs --env dev --audit
```

## Staging

```bash
node scripts/restore-public-identities.mjs --env staging --dry-run
node scripts/restore-public-identities.mjs --env staging --apply
node scripts/restore-public-identities.mjs --env staging --audit
```

Exercise block masking, reporting, profile navigation, profile edits, Live Replay, completion leaderboards, community avatars, and First Ascent rendering in staging before production.

## Production

```bash
node scripts/restore-public-identities.mjs --env prod --confirm-production ascend-prod-9c8f2 --dry-run
node scripts/restore-public-identities.mjs --env prod --confirm-production ascend-prod-9c8f2 --apply
node scripts/restore-public-identities.mjs --env prod --confirm-production ascend-prod-9c8f2 --audit
```

Record the migration ledger run ID and the final audit output with the release evidence.

## Failure recovery

Do not delete the ledger or per-user markers after a partial failure.
Fix the underlying Firestore or index problem, then rerun apply with `--rerun`.
Users whose projections and marker already match plan zero writes.
Users without a matching marker are reapplied, and their marker lands only after all of their writes succeed.
If a concurrent edit repeatedly exhausts the three-attempt replan budget, stop and investigate the writer instead of increasing the retry count.

## Audit meaning

Audit fails if any real-user projection differs from the validated account identity or stable UID fallback.
Audit also fails when a user lacks a version-matched identity digest marker.
Audit also fails on a missing public profile or a marker whose source version differs from the current private user root.
An account root may have an empty display name before onboarding finishes, but every public mirror receives a non-empty stable UID-derived fallback.
