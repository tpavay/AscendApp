# Production backend rollout runbook

## Purpose and safety boundary

This runbook closes production-readiness gate 8 from the 2026-07-21 production audit.
It prepares one GitHub Actions operation that builds the production binary, deploys the compatible backend in dependency order, verifies the critical backend state, and only then uploads the binary to TestFlight.

Every command that names the `production` Firebase alias or the production workflow is captain-only.
Do not run a production Firebase command while preparing or reviewing this change.
Do not combine the deploy targets into one Firebase CLI call because that provides no index-readiness barrier before dependent Functions become active.

The workflow uses the repository's protected `production` environment and requires `PRODUCTION_READY=true`.
Exactly one job carries that environment, `Approve Production Deploy`, so the run requests a single approval before any build or deploy work starts.
The captain must approve that job before production work begins; nothing later in the run asks again.

## What this rollout contains

The audit examined an older `develop` SHA that declared 11 composite indexes and found nine of them deployed.
The two missing Live Replay indexes are both collection-scoped `entries` indexes:

- `isBestForUser ASCENDING`, then `stepsAtBucket ASCENDING`.
- `isBestForUser ASCENDING`, then `stepsAtBucket DESCENDING`.

The current query filters per-climb and per-routine live races with `isBestForUser == true`, then reads the window ahead in ascending `stepsAtBucket` order and the window behind in descending order.
Both matching definitions already exist exactly once in `firestore.indexes.json` after rebasing onto current `develop`, so this preparation does not add duplicates.

Current `develop` declares 13 composite indexes because later work also added the `workouts(source, climbId)` projection index and the routine completion `entries(finalSteps DESCENDING, __name__ ASCENDING)` index.
It also declares five field overrides, for `blocked.blockedUid`, `entries.userId`, `finishers.userId`, `entitlements.accessUntil`, and `_revenuecat_webhook_events.retainUntil`.
The first four carry a `COLLECTION_GROUP` scope, and `entries.userId` additionally restates its ascending and descending `COLLECTION`-scoped single-field indexes.
`_revenuecat_webhook_events.retainUntil` declares no index at all: it exists to carry the TTL policy that expires the webhook dedupe ledger.
That restatement is required because a field override replaces the field's entire index configuration, and the server's best-entry reconciliation still queries `entries` by `userId` inside a single leaderboard.
The production workflow waits until every composite index and every scope inside every field override reports `READY` before Functions deploy.

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
9. Confirm the production Remote Config template is published, so every kill switch exists before the binary that needs one ships.
   No deploy workflow publishes it to production; dev and staging receive new switches automatically, production stays a captain-only publish.
   See "Remote Config kill switches" below for the command, and `npm run remoteconfig:drift` for what is live in all three right now.
   The production `build-ios` job now refuses to archive while any flag the build reads is unreachable in `ascend-prod-9c8f2`, so a missed publish stops the release rather than shipping a decorative lever.
10. Complete every production captain action for server-side entitlement enforcement before this rollout: the `REVENUECAT_SERVER_CONFIG` Functions secret, the production RevenueCat webhook destination and its credentials, the App Store Server Notification URLs, the cross-service Storage-to-Firestore IAM role, and a reconciled grant for every account that already has paid access.
    Firestore and Storage rules deny paid data to a signed-in account with no server-owned grant, so a missed step here is a subscriber lockout rather than a degraded feature.
    `docs/revenuecat-server-entitlement-enforcement.md` owns the full action list; do not restate it here.

Use these read-only GitHub checks:

```sh
gh-axi run list --workflow deploy-production.yml --branch main --limit 10
gh-axi secret list
gh-axi variable list
```

The captain-only replay check is:

```sh
node scripts/backfill-live-replay-best-per-user.mjs --project prod --dry-run
```

Do not use `--confirm-production` for this preflight.
If the dry-run reports writes, stop and prepare a separate migration review before deploying the binary.

There is no public identity backfill to run.
Ascend is pre-launch: production holds no `users`, no `leaderboard_stats`, and no public-profile data, so account-authored identity only ever reaches production through the live write path.
Deploy the moderation rules, identity policy rules, required indexes, `onPublicProfileIdentityWritten`, and `onPublicIdentityPropagationJobWritten` before the binary that publishes identity, so the first published profile is validated and propagated by the server from the start.
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
2. Request the single `production` environment approval and hold until the captain grants it.
3. Build and retain the signed production IPA.
4. Build the Functions and Hosting artifacts.
5. Deploy Firestore indexes.
6. Poll the Firestore Admin API until all 13 composite indexes and every declared query scope inside all five field overrides report `READY`.
7. Deploy Functions.
8. Verify `cleanupDeletedUserData`, `expireRevenueCatEntitlements`, `onPublicIdentityPropagationJobWritten`, `onPublicProfileIdentityWritten`, `onWorkoutWritten`, `onWorkoutReplaySplitsWritten`, `reconcileAppAccess`, `revenueCatWebhook`, and `unsubscribeFromEmails` report `ACTIVE`.
9. Reconcile the whole deployed function set against this ref's `functions/src/index.ts` exports, failing on any missing, orphaned, or non-`ACTIVE` function.
10. Deploy Firestore rules.
11. Deploy Storage rules.
12. Deploy Hosting.
13. Verify Hosting serves `/climbs/manifest.json` successfully.
14. Upload the already-built IPA to TestFlight only after every backend step succeeds.
15. Hold the upload job until App Store Connect actually lists the uploaded build, so the next run's build number is derived from post-upload state.
    This step can add up to 15 minutes after a successful upload, and it fails the run when the build never appears; `scripts/ci/await-build-visible.mjs` owns why releasing the deploy concurrency group early would mint a duplicate build number.
16. Assert the run reached a real outcome, so a run that deployed nothing fails instead of reporting green.

This ordering makes indexes available before `onWorkoutWritten` can execute its `source + climbId` query.
It also puts the entitlement Functions and the `entitlements.accessUntil` expiry index in place before the Firestore and Storage rules that require a server-owned paid grant, so a missing RevenueCat secret stops the rollout instead of locking every subscriber out of the backend - `docs/revenuecat-server-entitlement-enforcement.md` owns that system.
It makes Functions available before Hosting publishes the rewrite to `unsubscribeFromEmails`.
It keeps the backend ahead of the binary because `upload-testflight` depends on the complete `deploy-firebase` job.

## Exact deployment commands

The workflow is the authoritative deployment path and supplies the repository secret `FIREBASE_TOKEN` plus the repository variable `FIREBASE_PROJECT_ID_PRODUCTION`.
Both are repository-scoped: the `production` environment holds no secrets and no variables of its own, so list them without an `--env` filter.
Sections 1-5 are the exact Firebase operations it runs, shown for review and captain-only recovery.
Section 6 is the one deploy target the workflow deliberately never touches, so it is captain-only by construction rather than only for recovery.

### 1. Firestore indexes

```sh
npx -y firebase-tools@15.22.1 deploy --project production \
  --only firestore:indexes --non-interactive
```

Verify the deployment does not request deletion of an unexpected index.
Then wait for every declared index, including both `isBestForUser + stepsAtBucket` directions and all five field overrides, to become usable:

```sh
firebase_bin="$(npm exec --yes --package=firebase-tools@15.22.1 -- which firebase)"
firebase_tools_root="$(cd "$(dirname "$firebase_bin")/../firebase-tools" && pwd -P)"
FIREBASE_TOOLS_ROOT="$firebase_tools_root" \
  node scripts/ci/wait-for-firestore-indexes.mjs \
    firestore.indexes.json ascend-prod-9c8f2 "(default)"
```

This command calls the Firestore Admin API directly rather than through the CLI's option parsing, so its second argument must be the literal project ID.
Passing a `.firebaserc` alias such as `production` is refused before any Firestore call, with the alias named and the project ID it maps to quoted back so the correct argument is in the failure itself.
The alias is never resolved for you, because a stale mapping would point the production readiness check at the wrong project.
The same refusal fires when `.firebaserc` is unreadable or declares no `projects` map, since the argument cannot be proven literal without it.
The command authenticates with `FIREBASE_TOKEN` when that is exported, and otherwise falls back to the refresh token of the logged-in Firebase CLI account, so a captain running it by hand needs an active `firebase login` session.

Do not proceed while this command exits nonzero.
The gate reads the current serving state for every composite index and every scope inside each field override directly from the Firestore Admin API.
It matches the deployed definitions to `firestore.indexes.json` exactly and proceeds only when every match reports `READY`.
A missing, creating, repair-needed, unspecified, or unexpected configuration blocks Functions deployment and is named with its current state.

Only `CREATING` is worth waiting on, so only `CREATING` gets the full 60-minute window.
A freshly deployed index appears as `CREATING`, never as absent, so anything still missing or unexpected two minutes in is a definition mismatch that no amount of waiting resolves.
The command fails those as verification errors and names every one of them with its state.
A declared field override must exist as a Firestore resource even when it declares no indexes, so an override that was never applied cannot pass vacuously.

That two-minute structural grace is an estimate, not a measurement.
Composite indexes are well understood here, but a cold field override only becomes visible to `listFieldOverrides` once Firestore flips `indexConfig.usesAncestorConfig` to false, and that window has never been measured because measuring it requires writing to a project.
If a production deploy ever aborts with a definition-mismatch verdict on an override that was in fact still being created, raise the grace instead of editing code:

```sh
FIRESTORE_INDEX_STRUCTURAL_GRACE_MS=300000 \
FIREBASE_TOOLS_ROOT="$firebase_tools_root" \
  node scripts/ci/wait-for-firestore-indexes.mjs \
    firestore.indexes.json ascend-prod-9c8f2 "(default)"
```

In CI the same knob is the `FIRESTORE_INDEX_STRUCTURAL_GRACE_MS` repository variable, read by the `Wait for every declared Firestore index` step.
Leaving it unset keeps the two-minute default.
The value is milliseconds and must be finite, strictly positive, and below the 60-minute readiness window; anything else fails the step closed rather than falling back to a default, because a grace at or above the window would silently restore the hour-long burn this gate exists to prevent.

The command sorts read failures into three classes.
A rejection that carries an HTTP 400, 401, or 403, or that names a permission or scope problem outright, fails on the first poll, because every later poll fails identically and retrying only converts a visible error into a spent hour.
An expired or revoked `FIREBASE_TOKEN` normally lands here: the OAuth refresh returns 400, the pinned CLI passes the stale token through, and Firestore answers `HTTP Error: 401`.
A transport, DNS, throttling, or 5xx failure is retried up to fifteen consecutive polls - five minutes - before the run fails as a verification error rather than a false readiness timeout.

Between those sits `Authentication Error: Your credentials are no longer valid`, along with `Authentication Error.` and `Unable to getAccessToken`.
Do not read that wording as proof the token is dead.
The pinned CLI's `refreshTokens()` collapses several unrelated refresh-layer failures into it: it calls the OAuth endpoint with `resolveOnHTTPError`, so a 5xx returns a body with no `access_token` and raises the same error a DNS or socket failure does, none of them carrying an HTTP status.
The gate therefore retries that wording across three consecutive polls - about forty seconds - and only then fails, so one OAuth hiccup cannot kill a production release while a genuinely unusable credential still fails quickly.
When it does fail, check whether the OAuth endpoint was healthy at that moment before rotating the token.

Do not replace this command with `firebase firestore:operations:list --token` while Firebase CLI 15.22.1 is pinned.
That command omits the CLI authentication hook, so `--token` is ignored on a clean runner even though adjacent index commands authenticate successfully.
The direct state reader installs the workflow refresh token into the pinned CLI client explicitly and checks the state that determines whether an index can serve queries.
Because it loads that CLI's private `lib/auth.js` and `lib/firestore/api.js`, it asserts the resolved package is exactly `firebase-tools@15.22.1` and refuses to run against any other tree.
Bumping the CLI pin therefore requires updating `PINNED_FIREBASE_TOOLS_VERSION` in `scripts/lib/firestore-index-state-reader.mjs` and re-verifying both private modules against the new release.

Rollback: do not delete a newly created additive index during an incident.
An unused composite index does not change query results, and deleting it adds risk while providing no immediate recovery benefit.
Revert the declaration in a reviewed follow-up only after confirming no released query needs it.

### 2. Functions

```sh
npx -y firebase-tools@15.22.1 deploy --project production \
  --only functions --non-interactive --force
```

`--force` is intentionally scoped to Functions so the deployed set matches `functions/src/index.ts` without making rules, indexes, Storage, or Hosting destructive.

Verify the nine gate-critical functions are active:

```sh
npx -y firebase-tools@15.22.1 --json functions:list \
  --project production \
  | node scripts/ci/assert-firebase-functions-active.mjs \
      cleanupDeletedUserData \
      expireRevenueCatEntitlements \
      onPublicIdentityPropagationJobWritten \
      onPublicProfileIdentityWritten \
      onWorkoutWritten \
      onWorkoutReplaySplitsWritten \
      reconcileAppAccess \
      revenueCatWebhook \
      unsubscribeFromEmails
```

That list is curated, so it proves those nine exports and says nothing about the rest of the project.
Then reconcile the whole deployed set against the checked-out source, which is what catches a function nobody thought to add to the curated list and one deleted from source but still serving traffic:

```sh
node scripts/verify-deployed-functions.mjs --project production
```

Run it from the ref production is supposed to be running, because the expectation is that ref's `functions/src/index.ts`.
A green `firebase deploy` log is not evidence that the project holds what the source declares; only this reconciliation is.

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
The smoke account needs a reconciled `users/{uid}/entitlements/app_access` grant for that check: private workouts, routines, and `profile_stats` are paid boundaries, so a signed-in account without a grant is denied by design.
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
Workout media and heart-rate sidecars authorize through a cross-service Firestore read of the same paid grant, so this check fails closed if that IAM role is missing or the smoke account has no grant; owner deletes stay available either way.

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

Verify `/api/unsubscribe` routes to its deployed Function with a safe test request.
Use a `GET`, which renders the confirmation page and never acts, rather than a `POST` that would opt someone out.

Rollback: rebuild and redeploy only Hosting from the last known good production SHA.

### 6. Remote Config kill switches

Publishes the parameters that let a shipped iOS binary be halted without a new submission.
This is the one step that is deliberately **not** part of any CI deploy for production.
Dev and staging now receive newly added switches automatically, additively, from `deploy-staging.yml`; production does not, and no workflow may invoke the additive publisher against `ascend-prod-9c8f2`.

Prefer the additive publisher, which can only add a parameter the project has never held and refuses to write while any switch is off:

```sh
node scripts/publish-new-kill-switches.mjs prod --confirm-production ascend-prod-9c8f2
node scripts/publish-new-kill-switches.mjs prod --confirm-production ascend-prod-9c8f2 --apply
```

Use the full replace when production has diverged and the checked-in template is the state you want restored:

```sh
node scripts/deploy-remote-config.mjs --env prod --confirm-production ascend-prod-9c8f2
node scripts/deploy-remote-config.mjs --env prod --confirm-production ascend-prod-9c8f2 --apply
```

Both read the live template first and refuse to publish while any managed flag is switched off.
Production was first published on 2026-08-02 and read back parameter by parameter; `remote-config-kill-switches.md` holds that record and owns the publish contract.
Re-run this whenever a flag is added - the production archive fails while any flag the build reads is unreachable on the backend.

Rollback: there is nothing to roll back - the checked-in template is the healthy state, with every switch on.
To *use* a switch, flip it to `false` in the Firebase console. See `remote-config-kill-switches.md`.

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
A run that concludes `cancelled` sends no email, so do not read silence as success: an open `deploy-health` issue means production is not running the head of `main`, and it closes itself once a deploy lands.
Then complete these captain-only checks against production.

1. Confirm all declared Firestore indexes still report `READY` with the index readiness command above.
2. Confirm the six critical Functions still report `ACTIVE`, and that the deployed set still reconciles against the release ref, with the two function commands above.
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
