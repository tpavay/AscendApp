# Production backend rollout runbook

## Purpose and safety boundary

This runbook closes production-readiness gate 8 from the 2026-07-21 production audit.
It prepares one GitHub Actions operation that builds the production binary, deploys the compatible backend in dependency order, verifies the critical backend state, and only then uploads the binary to TestFlight.

Every command that names the `production` Firebase alias or the production workflow is captain-only.
Do not run a production Firebase command while preparing or reviewing this change.
Do not combine the deploy targets into one Firebase CLI call because that provides no index-readiness barrier before dependent Functions become active.

The workflow uses the repository's protected `production` environment and requires `PRODUCTION_READY=true`.
The captain must approve the protected environment before production work begins.

## What this rollout contains

The audit examined an older `develop` SHA that declared 11 composite indexes and found nine of them deployed.
The two missing Live Replay indexes are both collection-scoped `entries` indexes:

- `isBestForUser ASCENDING`, then `stepsAtBucket ASCENDING`.
- `isBestForUser ASCENDING`, then `stepsAtBucket DESCENDING`.

The current query filters per-climb and per-routine live races with `isBestForUser == true`, then reads the window ahead in ascending `stepsAtBucket` order and the window behind in descending order.
Both matching definitions already exist exactly once in `firestore.indexes.json` after rebasing onto current `develop`, so this preparation does not add duplicates.

Current `develop` declares 13 composite indexes because later work also added the `workouts(source, climbId)` projection index and the routine completion `entries(finalSteps DESCENDING, __name__ ASCENDING)` index.
It also declares three collection-group field overrides for `blocked.blockedUid`, `entries.userId`, and `finishers.userId`.
The production workflow waits until every composite index reports `READY`, verifies that every field override is deployed, and requires each relevant field-index backfill operation to finish before Functions deploy.

The `cleanupDeletedUserData` function is implemented in `functions/src/accountCleanup.ts` and exported from `functions/src/index.ts`.
It is retry-enabled, discovers all `users/{uid}` subcollections, continues independent cleanup steps after a partial failure, and throws when any cleanup step fails so Cloud Functions retries it.
It also handles user-keyed data outside the user subtree, including notification devices, leaderboard rows, replay finisher state, First Ascent identity fields, feedback, lifecycle email jobs, and rate limits.
The implementation is covered by `functions/test/accountCleanup.test.ts`.
No source correction is required for the function, so the forward-looking production gap is deployment only.

The delete trigger is not retroactive.
If a production user document was deleted before `cleanupDeletedUserData` became active, deploying it will not sweep that historical deletion.
The captain must confirm whether any production account deletion occurred during the gap and open a separate, reviewed reconciliation task if one did.

## Captain preflight

Complete every item before starting the production workflow.

1. Confirm this rollout PR has merged through `develop` and the chosen release commit is on `main`.
2. Confirm CI is green for the exact release SHA.
3. Confirm the audit's `profile_stats` compatibility gate has been resolved by checking whether any distributed production-bundle build still writes the legacy `top_*_weeks` fields.
4. Confirm the repository-level `FIREBASE_TOKEN`, `GOOGLE_SERVICE_INFO_PRODUCTION_BASE64`, signing secrets, and App Store Connect secrets exist.
5. Confirm the `production` environment still requires the intended human approval and `PRODUCTION_READY` is `true` only for the approved release window.
6. Confirm no other Deploy Production run is queued or in progress.
7. Rerun the production replay backfill in read-only mode and require zero planned writes, or prepare and separately approve the migration before continuing.
8. Confirm the `Release` RevenueCat and Superwall keys are real.
   They ship as configured production publishable client keys, so the workflow's monetization preflight now verifies them before the archive instead of blocking the run.
   `Staging` carries its own staging publishable keys and clears the same preflight, and `Debug` is intentionally unset.
   The per-environment key split is owned by `docs/superwall-paywall-setup.md`.
9. Complete public identity restoration operation version 7 and require a green production audit before approving the workflow environment.
   This gate adds `identityPolicyVersion`, `identityChangedAt`, and global leaderboard `identityState` before the production binary can upload.

Use these read-only GitHub checks:

```sh
gh-axi run list --workflow deploy-production.yml --branch main --limit 10
gh-axi secret list
gh-axi variable list --env production
```

The captain-only replay check is:

```sh
node scripts/backfill-live-replay-best-per-user.mjs --project prod --dry-run
```

Do not use `--confirm-production` for this preflight.
If the dry-run reports writes, stop and prepare a separate migration review before deploying the binary.

The captain-only public identity gate is:

```sh
node scripts/restore-public-identities.mjs --env prod --confirm-production ascend-prod-9c8f2 --dry-run
node scripts/restore-public-identities.mjs --env prod --confirm-production ascend-prod-9c8f2 --apply
node scripts/restore-public-identities.mjs --env prod --confirm-production ascend-prod-9c8f2 --audit
```

Run these commands only after the moderation rules, identity policy rules, required indexes, `onPublicProfileIdentityWritten`, and `onPublicIdentityPropagationJobWritten` are deployed.
Do not approve the protected `production` environment while the audit reports a stale projection, an orphan public identity with noncurrent deleted identity, a missing public profile, or an incomplete version 7 marker.
For the first rollout of this policy, deploy that backend preparation as a separately reviewed captain operation before approving the release workflow.
The release workflow may redeploy the same backend SHA after approval because those deployments are idempotent.

## One-command launch

A merge to `main` that changes a watched path automatically creates a Deploy Production run.
Use that run and do not manually dispatch a duplicate.

If `main` is already at the approved release SHA and no push-triggered run exists, launch exactly one run with:

```sh
gh-axi workflow run deploy-production.yml --ref main
```

`deploy-production.yml` is the `Deploy Production` workflow at `.github/workflows/deploy-production.yml`.
Approve the protected `production` environment only after confirming the run's SHA is the approved release SHA.

The workflow performs the following order automatically:

1. Pass the production readiness gate.
2. Build and retain the signed production IPA.
3. Build the Functions and Hosting artifacts.
4. Deploy Firestore indexes.
5. Poll until all 13 composite indexes report `READY`, all three collection-group field overrides are present, and their relevant Firestore admin operations are complete.
6. Deploy Functions.
7. Verify `cleanupDeletedUserData`, `onPublicIdentityPropagationJobWritten`, `onPublicProfileIdentityWritten`, `onWorkoutWritten`, `onWorkoutReplaySplitsWritten`, and `unsubscribeFromEmails` report `ACTIVE`.
8. Deploy Firestore rules.
9. Deploy Storage rules.
10. Deploy Hosting.
11. Verify Hosting serves `/climbs/manifest.json` successfully.
12. Upload the already-built IPA to TestFlight only after every backend step succeeds.

This ordering makes indexes available before `onWorkoutWritten` can execute its `source + climbId` query.
It makes Functions available before Hosting publishes rewrites to `joinWaitlist` and `unsubscribeFromEmails`.
It keeps the backend ahead of the binary because `upload-testflight` depends on the complete `deploy-firebase` job.

## Exact deployment commands

The workflow is the authoritative deployment path and supplies the repository secret as `FIREBASE_TOKEN` plus the protected environment variable as `FIREBASE_PROJECT_ID_PRODUCTION`.
These are the exact Firebase operations it runs, shown for review and captain-only recovery.

### 1. Firestore indexes

```sh
npx -y firebase-tools@15.22.1 deploy --project production \
  --only firestore:indexes --non-interactive
```

Verify the deployment does not request deletion of an unexpected index.
Then wait for every declared index, including both `isBestForUser + stepsAtBucket` directions and all collection-group field overrides, to become usable:

```sh
deployed_spec_file="$(mktemp)"
operations_file="$(mktemp)"
npx -y firebase-tools@15.22.1 firestore:indexes \
  --project production --json > "$deployed_spec_file"
npx -y firebase-tools@15.22.1 firestore:operations:list \
  --project production --limit 1000 --json > "$operations_file"
npx -y firebase-tools@15.22.1 firestore:indexes \
  --project production --pretty \
  | node scripts/ci/assert-firestore-indexes-ready.mjs \
      firestore.indexes.json "$operations_file" "$deployed_spec_file"
```

Do not proceed while this command exits nonzero.
The pretty field-override listing omits query scope and serving state.
The gate therefore validates exact `COLLECTION_GROUP` scope from JSON and separately requires the latest relevant `FieldOperationMetadata` backfill for every declared field override to finish in `SUCCESSFUL` state.
A pending, failed, cancelled, or error-bearing terminal operation blocks Functions deployment.

Rollback: do not delete a newly created additive index during an incident.
An unused composite index does not change query results, and deleting it adds risk while providing no immediate recovery benefit.
Revert the declaration in a reviewed follow-up only after confirming no released query needs it.

### 2. Functions

```sh
npx -y firebase-tools@15.22.1 deploy --project production \
  --only functions --non-interactive --force
```

`--force` is intentionally scoped to Functions so the deployed set matches `functions/src/index.ts` without making rules, indexes, Storage, or Hosting destructive.

Verify the six gate-critical functions are active:

```sh
npx -y firebase-tools@15.22.1 --json functions:list \
  --project production \
  | node scripts/ci/assert-firebase-functions-active.mjs \
      cleanupDeletedUserData \
      onPublicIdentityPropagationJobWritten \
      onPublicProfileIdentityWritten \
      onWorkoutWritten \
      onWorkoutReplaySplitsWritten \
      unsubscribeFromEmails
```

Rollback: stop before the Firestore rules and TestFlight steps, inspect the failed Function logs, and redeploy the Functions from the last known good production SHA using the rollback worktree described below.
Do not remove a healthy `cleanupDeletedUserData` merely because an unrelated Function failed.
If the failure can be isolated, redeploy only the affected function with `--only functions:<functionId>`.

### 3. Firestore rules

```sh
npx -y firebase-tools@15.22.1 deploy --project production \
  --only firestore:rules --non-interactive
```

Verify the command reports a successful rules release.
Then use the production-signed smoke account to read and write its allowed private documents and confirm an unauthenticated client cannot read them.
Also confirm the current `profile_stats` write succeeds before uploading the binary.

Rollback: redeploy only `firestore:rules` from the last known good production SHA.
Do not roll rules back after distributing a binary that requires the new schema unless the rollback rules remain compatible with both schemas.

### 4. Storage rules

```sh
npx -y firebase-tools@15.22.1 deploy --project production \
  --only storage --non-interactive
```

Verify the command reports a successful rules release.
Using the production-signed smoke account, upload and delete one file beneath that account's `users/{uid}/...` prefix and confirm a second account cannot read or write it.

Rollback: redeploy only `storage` from the last known good production SHA.

### 5. Hosting

```sh
npm --prefix web ci
npm --prefix web run build
npx -y firebase-tools@15.22.1 deploy --project production \
  --only hosting --non-interactive
```

Verify the climb manifest is served from the environment-derived Hosting site:

```sh
PRODUCTION_PROJECT_ID="$(node -p 'require("./.firebaserc").projects.production')"
curl --fail --location --retry 5 --retry-all-errors \
  "https://${PRODUCTION_PROJECT_ID}.web.app/climbs/manifest.json" \
  --output /dev/null
```

Verify `/api/join-waitlist` and `/api/unsubscribe` route to their deployed Functions with safe test requests.
Do not submit a real email address as a routing probe.

Rollback: rebuild and redeploy only Hosting from the last known good production SHA.

## Rollback worktree

Prepare a clean rollback worktree from the SHA recorded by the last successful production deployment.
The captain must replace the placeholder before running these commands.

```sh
LAST_KNOWN_GOOD_SHA='<last-successful-production-sha>'
ROLLBACK_ROOT="$(mktemp -d)"
git worktree add "$ROLLBACK_ROOT/repo" "$LAST_KNOWN_GOOD_SHA"
cd "$ROLLBACK_ROOT/repo"
npm --prefix functions ci
npm --prefix web ci
npm --prefix web run build
```

Run only the rollback target required by the failed step:

```sh
npx -y firebase-tools@15.22.1 deploy --project production \
  --only functions --non-interactive --force
npx -y firebase-tools@15.22.1 deploy --project production \
  --only firestore:rules --non-interactive
npx -y firebase-tools@15.22.1 deploy --project production \
  --only storage --non-interactive
npx -y firebase-tools@15.22.1 deploy --project production \
  --only hosting --non-interactive
```

These are alternatives, not a batch.
Do not run all four unless the incident requires a full backend rollback and compatibility with every already-distributed binary has been checked.

After the incident is closed, remove the temporary worktree from the original repository:

```sh
git worktree remove "$ROLLBACK_ROOT/repo"
rmdir "$ROLLBACK_ROOT"
```

## Post-deploy production verification

The workflow must reach green before selecting or distributing the TestFlight build.
Then complete these captain-only checks against production.

1. Confirm all declared Firestore indexes still report `READY` with the index assertion command above.
2. Confirm the five critical Functions still report `ACTIVE` with the function assertion command above.
3. Inspect recent cleanup logs with `npx -y firebase-tools@15.22.1 functions:log --project production --only cleanupDeletedUserData --lines 50`.
4. Create one Google smoke account and one Apple smoke account in a production-signed physical-device build.
5. For each account, create a workout, replay presence, profile data, a push token, feedback, and user-scoped Storage data that exercise the cleanup paths.
6. Delete each account in the app and wait for the `Swept deleted user data` success log with no retry failure.
7. Confirm the Auth user, `users/{uid}` document and subcollections, top-level `notification_devices`, `leaderboard_stats`, replay finisher record, feedback, uid-keyed lifecycle email job, rate-limit record, and user Storage prefixes are gone.
8. Confirm a held First Ascent remains claimed and dated but renders as `Anonymous Climber` with no photo or avatar token.
9. Confirm the app returns to signed-out state and RevenueCat and Superwall no longer identify the deleted user.
10. Confirm the Apple credential is revoked and both providers can create a fresh account again.
11. Confirm a new production workout creates or updates `users/{uid}/landmarkResults` through `onWorkoutWritten`.
12. Confirm a modified client cannot publish an ineligible replay entry because `onWorkoutReplaySplitsWritten` derives eligibility from server-visible workout evidence.
13. Confirm a public profile and leaderboard document contain `identityPolicyVersion: 1` plus a timestamp `identityChangedAt`.
14. Confirm an old build cannot change `displayName` or `photoURL` without advancing the protected identity timestamp.

If any check fails, do not select the TestFlight build for App Review.
Capture the failing release SHA, Function execution ID, affected uid, and exact verification step before deciding whether to repair forward or use the scoped rollback.
